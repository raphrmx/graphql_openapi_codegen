import 'dart:io';

import 'package:collection/collection.dart';
import 'package:gql/ast.dart' as gql;
import 'package:gql/ast.dart';
import 'package:graphql_openapi_codegen/src/config.dart';
import 'package:graphql_openapi_codegen/src/consts.dart';
import 'package:graphql_openapi_codegen/src/generated_endpoint.dart';
import 'package:graphql_openapi_codegen/src/helpers.dart';
import 'package:path/path.dart' as path;

/// Generates a central router that mounts all REST endpoints
/// (Query, Mutation, Subscription).
///
/// This file allows the server to expose all auto-generated REST routes
/// by calling `buildRestRouter()`.
void generateRestRoutesFile(
  Directory restDir, {
  required List<GeneratedEndpoint> queryFiles,
  required List<GeneratedEndpoint> mutationFiles,
  required List<GeneratedEndpoint> subscriptionFiles,
}) {
  final out = File(path.join(restDir.path, 'rest_routes.dart'));
  final b = StringBuffer();

  final routeImports = ImportBlock()
    ..add('package:shelf_router/shelf_router.dart');

  // Endpoint imports
  for (final f in [...queryFiles, ...mutationFiles, ...subscriptionFiles]) {
    routeImports.addLibFile(f.filePath);
  }

  b.writeln(
    'void registerRestRoutes(Router router, '
    '{String prefix = ${dartStringLiteral(importerConfig.restPrefix)}, '
    'Map<String, String>? cors}) {',
  );

  for (final e in queryFiles) {
    b.writeln(
      "  router.post('\$prefix${e.routePath}', ${e.handlerName}(cors));",
    );
  }
  for (final e in mutationFiles) {
    b.writeln(
      "  router.post('\$prefix${e.routePath}', ${e.handlerName}(cors));",
    );
  }
  for (final e in subscriptionFiles) {
    b.writeln("  router.get('\$prefix${e.routePath}', ${e.handlerName}());");
  }

  b.writeln('}');

  writeGeneratedLibrary(
    out,
    description: 'Auto generated central REST routes.',
    extra: const ['Aggregates all Query/Mutation/Subscription REST endpoints.'],
    imports: routeImports,
    body: b.toString(),
  );
}

/// Writes the handler for one `Query` field, and returns what mounts it.
///
/// Created once: a handler that already exists is described, not rewritten.
GeneratedEndpoint? generateQueryEndpointFile(
  Directory endpointsDir,
  DocumentNode document,
  FieldDefinitionNode field,
) => _generateOperationEndpointFile(
  endpointsDir,
  document,
  field,
  opName: 'query',
);

/// Writes the handler for one `Mutation` field, and returns what mounts it.
///
/// Same shape as the `Query` handler down to the last line. They used to be two
/// copies that drifted: one spread `req.context` into the arguments and the
/// other did not, and one typed its CORS map `Map<String, dynamic>` while the
/// router that calls it passes `Map<String, String>`.
GeneratedEndpoint? generateMutationEndpointFile(
  Directory endpointsDir,
  DocumentNode document,
  FieldDefinitionNode field,
) => _generateOperationEndpointFile(
  endpointsDir,
  document,
  field,
  opName: 'mutation',
);

/// The one implementation behind both.
///
/// [opName] is `query` or `mutation`, lower case: it names the file, the
/// handler, the resolver it calls and the route it answers on.
GeneratedEndpoint? _generateOperationEndpointFile(
  Directory endpointsDir,
  DocumentNode document,
  FieldDefinitionNode field, {
  required String opName,
}) {
  final fieldName = field.name.value;
  final pascal = convertName(fieldName);
  final snake = toSnakeCase(fieldName);
  final handlerName = '$opName${pascal}Endpoint';
  final routePath = '/$opName/$fieldName';
  final file = File(
    path.join(
      '${endpointsDir.path}/endpoints',
      '${opName}_${snake}_endpoint.dart',
    ),
  );

  if (file.existsSync()) {
    return GeneratedEndpoint(file.path, handlerName, routePath, field: field);
  }

  final retBase = getBaseTypeName(field.type);
  final isListTop = isListType(field.type);
  final isScalarTop = isScalar(retBase);

  // The root resolver of the operation. Sub-resolvers discovered while walking
  // the returned type are added to the same set.
  final resolverImports = <String>{
    '../../resolvers/${opName}_${snake}_resolver.dart',
  };

  // The body comes first: it is what tells us which sub-resolvers to import.
  final body = StringBuffer();

  body.writeln('Handler $handlerName(Map<String, String>? cors) {');
  body.writeln('  return (Request req) async {');
  body.writeln('    final body = await req.readAsString();');
  body.writeln(
    '    final jsonBody = body.isNotEmpty ? jsonDecode(body) as Map<String, dynamic> : <String, dynamic>{};',
  );
  // Whatever middleware put on the request travels to the resolver, which is
  // how an authenticated user reaches it.
  body.writeln('    final args = <String, dynamic>{...req.context};');

  for (final arg in field.args) {
    final a = arg.name.value;
    body.writeln(
      "    if (jsonBody.containsKey('$a')) args['$a'] = jsonBody['$a'];",
    );
  }

  final rootResolverFn = '${dartFieldNameForResolver(fieldName)}Resolver';
  body.writeln();
  body.writeln('    final result = await $rootResolverFn(null, args);');

  if (isListTop) {
    if (isScalarTop) {
      body.writeln("    final wrapped = {'data': (result as List?) ?? []};");
    } else {
      body.writeln('    final resultList = (result as List?) ?? [];');
      body.writeln(
        '    final resultJson = resultList.map((e) => e.toJson()).toList();',
      );
      body.writeln("    final wrapped = {'data': resultJson};");
    }
  } else if (isScalarTop) {
    body.writeln("    final wrapped = {'data': result};");
  } else {
    // A field the schema declares non-null hands back a non-null resolver
    // result, so the null-aware call the other branch needs would be reported
    // as `invalid_null_aware_operator`.
    body.writeln(
      field.type.isNonNull
          ? '    final resultJson = result.toJson();'
          : '    final resultJson = result?.toJson() ?? <String, dynamic>{};',
    );
    emitNestedPopulation(
      body,
      document,
      parentGqlType: retBase,
      argsAccessor: 'jsonBody',
      parentSerVar: 'result',
      parentJsonVar: 'resultJson',
      depth: 2,
      resolverImports: resolverImports,
    );
    body.writeln("    final wrapped = {'data': resultJson};");
  }

  // `...?cors` is what makes the parameter mean something. It used to be
  // accepted and then dropped, so mounting the router with `cors:` changed
  // nothing about what the endpoints answered.
  body.writeln('    return Response.ok(jsonEncode(wrapped), headers: {');
  body.writeln("      'Content-Type': 'application/json',");
  body.writeln('      ...?cors,');
  body.writeln('    });');
  body.writeln('  };');
  body.writeln('}');

  // Now that every sub-resolver is known.
  final buf = StringBuffer()
    ..writeln(
      '// Created once by GraphQL/REST Code-Gen. Edit freely; it will NOT be overwritten.',
    );
  final imports = ImportBlock()
    ..addAll(const ['dart:convert', 'package:shelf/shelf.dart']);
  for (final imp in resolverImports) {
    imports.addRelative(endpointsDirPath, imp);
  }
  buf.write(imports.render());
  buf.writeln();
  buf.write(body.toString());

  writeCreatedOnceFile(file, buf.toString());

  return GeneratedEndpoint(file.path, handlerName, routePath, field: field);
}

GeneratedEndpoint? generateSubscriptionEndpointFile(
  Directory endpointsDir,
  DocumentNode document,
  FieldDefinitionNode field,
) {
  final fieldName = field.name.value;
  final pascal = convertName(fieldName);
  final snake = toSnakeCase(fieldName);
  final handlerName = 'subscription${pascal}Endpoint';
  final file = File(
    path.join(
      '${endpointsDir.path}/endpoints',
      'subscription_${snake}_endpoint.dart',
    ),
  );

  if (file.existsSync()) {
    return GeneratedEndpoint(
      file.path,
      handlerName,
      '/subscription/$fieldName',
      field: field,
    );
  }

  final rootResolverFn = '${dartFieldNameForResolver(fieldName)}Resolver';
  final resolverImports = <String>{};
  resolverImports.add('../../resolvers/subscription_${snake}_resolver.dart');

  final buf = StringBuffer();
  buf.writeln(
    "// Created once by GraphQL/REST Code-Gen. Edit freely; it will NOT be overwritten.",
  );
  final imports = ImportBlock()
    ..addAll(const ['dart:convert', 'package:shelf/shelf.dart']);
  for (final imp in resolverImports) {
    imports.addRelative(endpointsDirPath, imp);
  }
  buf.write(imports.render());
  buf.writeln();

  buf.writeln("Handler $handlerName() {");
  buf.writeln("  return (Request req) async {");
  buf.writeln("    final body = await req.readAsString();");
  buf.writeln(
    "    final jsonBody = body.isNotEmpty ? jsonDecode(body) as Map<String, dynamic> : <String, dynamic>{};",
  );
  buf.writeln("    final args = <String, dynamic>{};");

  for (final arg in field.args) {
    final a = arg.name.value;
    buf.writeln(
      "    if (jsonBody.containsKey('$a')) args['$a'] = jsonBody['$a'];",
    );
  }

  buf.writeln();
  buf.writeln("    final stream = await $rootResolverFn(null, args);");
  buf.writeln("    req.hijack((channel) {");
  buf.writeln("      channel.sink.add(utf8.encode(");
  buf.writeln(
    "        'HTTP/1.1 200 OK\\r\\n'"
    " 'Content-Type: text/event-stream\\r\\n'"
    " 'Cache-Control: no-cache\\r\\n'"
    " 'Connection: keep-alive\\r\\n'"
    " '\\r\\n',",
  );
  buf.writeln("      ));");
  buf.writeln();
  buf.writeln("      stream.listen(");
  buf.writeln("        (event) {");
  buf.writeln("          final data = jsonEncode(event);");
  buf.writeln("          channel.sink.add(utf8.encode('data: \$data\\n\\n'));");
  buf.writeln("        },");
  buf.writeln("        onError: (err, st) {");
  buf.writeln(
    "          channel.sink.add(utf8.encode('event: error\\ndata: \$err\\n\\n'));",
  );
  buf.writeln("        },");
  buf.writeln("        onDone: () {");
  buf.writeln("          channel.sink.close();");
  buf.writeln("        },");
  buf.writeln("      );");
  buf.writeln("    });");
  buf.writeln("  };");
  buf.writeln("}");

  writeCreatedOnceFile(file, buf.toString());

  return GeneratedEndpoint(
    file.path,
    handlerName,
    '/subscription/$fieldName',
    field: field,
  );
}

void emitRestJsonExtractor(
  StringBuffer b,
  gql.DocumentNode document,
  gql.FieldDefinitionNode field, {
  String parentAccessor = 'jsonBody',
  String indent = '    ',
}) {
  // Add all direct field arguments
  for (final arg in field.args) {
    final argName = arg.name.value;
    b.writeln(
      "$indent"
      "if ($parentAccessor.containsKey('$argName')) {",
    );
    b.writeln("$indent  args['$argName'] = $parentAccessor['$argName'];");
    b.writeln("$indent}");
  }

  // Get the return type (e.g. Company, Establishment...)
  final base = getBaseTypeName(field.type);
  final typeDef = document.definitions
      .whereType<gql.ObjectTypeDefinitionNode>()
      .firstWhereOrNull((d) => d.name.value == base);

  if (typeDef != null) {
    // For each sub-field that has arguments
    for (final subField in typeDef.fields.where((f) => f.args.isNotEmpty)) {
      final name = subField.name.value;

      // We assume this field is an array
      b.writeln(
        "$indent"
        "if ($parentAccessor['$name'] is List && $parentAccessor['$name'].isNotEmpty as bool) {",
      );
      b.writeln(
        "$indent  for (final item in $parentAccessor['$name'] as List<Map<String, dynamic>>) {",
      );
      emitRestJsonExtractor(
        b,
        document,
        subField,
        parentAccessor: 'item',
        indent: '$indent    ',
      );
      b.writeln("$indent  }");
      b.writeln("$indent}");
    }
  }
}
