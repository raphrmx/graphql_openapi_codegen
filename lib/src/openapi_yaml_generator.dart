import 'dart:io';

import 'package:gql/ast.dart' as gql;
import 'package:graphql_openapi_codegen/src/config.dart';
import 'package:graphql_openapi_codegen/src/generated_endpoint.dart';
import 'package:graphql_openapi_codegen/src/helpers.dart';
import 'package:path/path.dart' as path;

void generateOpenApiYaml(
  Directory outputDir,
  gql.DocumentNode document, {
  required List<GeneratedEndpoint> queryFiles,
  required List<GeneratedEndpoint> mutationFiles,
  required List<GeneratedEndpoint> subscriptionFiles,
}) {
  final out = File(path.join(outputDir.path, 'openapi.yaml'));
  final b = StringBuffer();

  b.writeln('openapi: 3.0.3');
  b.writeln('info:');
  final title = importerConfig.apiName.isEmpty
      ? importerConfig.packageName
      : importerConfig.apiName;
  b.writeln('  title: $title REST');
  b.writeln('  version: "${readPubspecVersion()}"');

  /// The base URLs belong to whoever deploys the API, so they are declared in
  /// `pubspec.yaml` rather than written here.
  if (importerConfig.apiServers.isNotEmpty) {
    b.writeln('servers:');
    for (final url in importerConfig.apiServers) {
      b.writeln('  - url: $url');
    }
  }
  b.writeln('paths:');

  // ---------- PATHS: Query & Mutation ----------
  for (final e in [...queryFiles, ...mutationFiles]) {
    final field = e.field;

    b.writeln('  ${e.routePath}:');
    b.writeln('    post:');
    b.writeln('      operationId: ${e.handlerName}');
    if (field?.description?.value.isNotEmpty ?? false) {
      b.writeln(
        '      summary: "${field!.description!.value.replaceAll('"', '\\"')}"',
      );
    }
    if (field?.directives.any((d) => d.name.value == 'deprecated') == true) {
      b.writeln('      deprecated: true');
    }

    // ✅ requestBody -> $ref to the root composite schema (no "input:" wrapper)
    final rootSchemaName = rootCompositeSchemaNameFor(e);
    b.writeln('      requestBody:');
    b.writeln('        required: true');
    b.writeln('        content:');
    b.writeln('          application/json:');
    b.writeln('            schema:');
    b.writeln('              \$ref: "#/components/schemas/$rootSchemaName"');

    // ---- responses (unchanged) ----
    b.writeln('      responses:');
    b.writeln("        '200':");
    b.writeln('          description: Successful response');
    b.writeln('          content:');
    b.writeln('            application/json:');
    b.writeln('              schema:');
    b.writeln('                type: object');
    b.writeln('                properties:');
    b.writeln('                  data:');

    if (field != null) {
      final baseRet = getBaseTypeName(field.type);
      final needsAllOfRet = !isScalar(baseRet) && !isListType(field.type);
      writeTypeSchemaForYaml(
        b,
        field.type,
        indent: '                    ',
        wrapAllOfIfRef: needsAllOfRet,
      );
    } else {
      b.writeln('                    type: object');
    }
  }

  // ---------- PATHS: Subscription (SSE) ----------
  for (final e in subscriptionFiles) {
    b.writeln('  ${e.routePath}:');
    b.writeln('    get:');
    b.writeln('      operationId: ${e.handlerName}');
    if (e.field?.description?.value.isNotEmpty ?? false) {
      b.writeln(
        '      summary: "${e.field!.description!.value.replaceAll('"', '\\"')}"',
      );
    }
    if (e.field?.directives.any((d) => d.name.value == 'deprecated') == true) {
      b.writeln('      deprecated: true');
    }
    b.writeln('      responses:');
    b.writeln("        '200':");
    b.writeln('          description: Stream of events');
    b.writeln('          content:');
    b.writeln('            text/event-stream:');
    b.writeln('              schema:');
    b.writeln('                type: string');
  }

  // ---------- COMPONENTS / SCHEMAS ----------
  b.writeln('components:');
  b.writeln('  schemas:');

  final usedTypes = collectUsedTypes(
    document,
    queryFiles,
    mutationFiles,
    subscriptionFiles,
  );

  // ✅ Nested REST composite schemas (only resolvers with args)
  final emitted = <String>{};
  for (final e in queryFiles) {
    if (e.field != null) {
      emitCompositeInputSchema(
        b,
        document,
        e.field!,
        prefix: 'Query',
        emitted: emitted,
      );
    }
  }
  for (final e in mutationFiles) {
    if (e.field != null) {
      emitCompositeInputSchema(
        b,
        document,
        e.field!,
        prefix: 'Mutation',
        emitted: emitted,
      );
    }
  }

  // Objects
  for (final def
      in document.definitions.whereType<gql.ObjectTypeDefinitionNode>()) {
    if (!usedTypes.contains(def.name.value)) continue;
    final typeName = def.name.value;
    b.writeln('    $typeName:');
    b.writeln('      type: object');
    if (def.description?.value != null) {
      b.writeln(
        '      description: "${def.description!.value.replaceAll('"', '\\"')}"',
      );
    }
    b.writeln('      properties:');
    for (final f in def.fields) {
      final fname = f.name.value;
      final fdesc = f.description?.value.replaceAll('"', '\\"');
      final fdepr = f.directives.any((d) => d.name.value == 'deprecated');

      b.writeln('        $fname:');
      if (fdesc != null && fdesc.isNotEmpty) {
        b.writeln('          description: "$fdesc"');
      }
      if (fdepr) b.writeln('          deprecated: true');

      final base = getBaseTypeName(f.type);
      final needsAllOf = !isScalar(base) && !isListType(f.type);
      writeTypeSchemaForYaml(
        b,
        f.type,
        indent: '          ',
        wrapAllOfIfRef: needsAllOf,
      );
    }
  }

  // Inputs
  for (final def
      in document.definitions.whereType<gql.InputObjectTypeDefinitionNode>()) {
    if (!usedTypes.contains(def.name.value)) continue;
    final typeName = def.name.value;
    b.writeln('    $typeName:');
    b.writeln('      type: object');
    if (def.description?.value != null) {
      b.writeln(
        '      description: "${def.description!.value.replaceAll('"', '\\"')}"',
      );
    }

    final req = <String>[];
    for (final f in def.fields) {
      if (isNonNullTop(f.type)) req.add(f.name.value);
    }
    if (req.isNotEmpty) {
      b.writeln('      required:');
      for (final r in req) {
        b.writeln('        - $r');
      }
    }

    b.writeln('      properties:');
    for (final f in def.fields) {
      final fname = f.name.value;
      final fdesc = f.description?.value.replaceAll('"', '\\"');
      final fdepr = f.directives.any((d) => d.name.value == 'deprecated');

      b.writeln('        $fname:');
      if (fdesc != null && fdesc.isNotEmpty) {
        b.writeln('          description: "$fdesc"');
      }
      if (fdepr) b.writeln('          deprecated: true');

      final base = getBaseTypeName(f.type);
      final needsAllOf = !isScalar(base) && !isListType(f.type);
      writeTypeSchemaForYaml(
        b,
        f.type,
        indent: '          ',
        wrapAllOfIfRef: needsAllOf,
      );
    }
  }

  // Enums
  for (final def
      in document.definitions.whereType<gql.EnumTypeDefinitionNode>()) {
    if (!usedTypes.contains(def.name.value)) continue;
    final enumName = def.name.value;
    b.writeln('    $enumName:');
    b.writeln('      type: string');
    if (def.description?.value != null) {
      b.writeln(
        '      description: "${def.description!.value.replaceAll('"', '\\"')}"',
      );
    }
    b.writeln('      enum:');
    for (final v in def.values) {
      b.writeln('        - ${v.name.value}');
    }
  }

  // Scalars
  for (final def
      in document.definitions.whereType<gql.ScalarTypeDefinitionNode>()) {
    if (!usedTypes.contains(def.name.value)) continue;
    final scalarName = def.name.value;
    b.writeln('    $scalarName:');
    b.writeln('      type: ${openApiTypeFromGraphQL(scalarName)}');
    if (def.description?.value != null) {
      b.writeln(
        '      description: "${def.description!.value.replaceAll('"', '\\"')}"',
      );
    }
  }

  out.writeAsStringSync(b.toString());
}
