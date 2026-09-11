import 'dart:io';

import 'package:gql/ast.dart' as gql;
import 'package:graphql_openapi_codegen/src/config.dart';
import 'package:graphql_openapi_codegen/src/generated_endpoint.dart';
import 'package:graphql_openapi_codegen/src/helpers.dart';
import 'package:path/path.dart' as path;

/// Writes the `required:` list for a set of fields, if any is non-null.
void _writeRequired(StringBuffer b, Iterable<String> required) {
  if (required.isEmpty) return;
  b.writeln('      required:');
  for (final name in required) {
    b.writeln('        - $name');
  }
}

void generateOpenApiYaml(
  Directory outputDir,
  gql.DocumentNode document, {
  required List<GeneratedEndpoint> queryFiles,
  required List<GeneratedEndpoint> mutationFiles,
  required List<GeneratedEndpoint> subscriptionFiles,
}) {
  final out = File(path.join(outputDir.path, 'openapi.yaml'));
  final b = StringBuffer();

  b.writeln('openapi: 3.1.1');
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

    b.writeln('  ${importerConfig.restPrefix}${e.routePath}:');
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
      writeTypeSchemaForYaml(b, field.type, indent: '                    ');
    } else {
      b.writeln('                    type: object');
    }
  }

  // ---------- PATHS: Subscription (SSE) ----------
  for (final e in subscriptionFiles) {
    b.writeln('  ${importerConfig.restPrefix}${e.routePath}:');
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
    _writeRequired(
      b,
      def.fields.where((f) => isNonNullTop(f.type)).map((f) => f.name.value),
    );
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

      writeTypeSchemaForYaml(b, f.type, indent: '          ');
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

    _writeRequired(
      b,
      def.fields.where((f) => isNonNullTop(f.type)).map((f) => f.name.value),
    );

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

      writeTypeSchemaForYaml(b, f.type, indent: '          ');
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
