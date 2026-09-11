import 'dart:io';

import 'package:collection/collection.dart';
import 'package:gql/ast.dart' as gql;
import 'package:gql/ast.dart';
import 'package:graphql_openapi_codegen/src/consts.dart';
import 'package:graphql_openapi_codegen/src/generated_endpoint.dart';
import 'package:graphql_openapi_codegen/src/helpers.dart';
import 'package:path/path.dart' as path;
import 'package:recase/recase.dart';

/// Generates REST endpoints for a given GraphQL operation type (Query, Mutation, Subscription).
///
/// For each field in the GraphQL operation, a POST endpoint is created under `/operationName/fieldName`.
/// Example: `/query/getCompany` or `/mutation/createUser`.
///
/// The generated router uses the central `resolverRegistry` to dispatch calls.
void generateRestEndpoints(
  Directory outputDir,
  DocumentNode document,
  ObjectTypeDefinitionNode node,
  String opName,
) {
  final opLower = opName.toLowerCase();
  final fileName = '${opLower}_endpoints.dart';
  final out = File(path.join('${outputDir.path}/endpoints', fileName));
  final b = StringBuffer();

  // === Header ===
  writeDocComments(
    b,
    'Auto generated REST endpoints for $opName.',
    extra: ['Generated from GraphQL $opName.'],
  );

  final imports = ImportBlock()
    ..addAll(const [
      'dart:convert',
      'package:shelf/shelf.dart',
      'package:shelf_router/shelf_router.dart',
    ])
    ..addLibFile('$graphqlDirPath/graphql_resolvers_registry.dart');
  b.write(imports.render());
  b.writeln();

  // === Router ===
  b.writeln('Router ${opLower}Endpoints() {');
  b.writeln('  final router = Router();');
  b.writeln();

  for (final f in node.fields) {
    final route = '/$opLower/${f.name.value}';
    final resolverKey = '${ReCase(opName).pascalCase}.${f.name.value}';

    b.writeln("  // Endpoint for ${f.name.value}");

    final deprecReason = getDeprecationReason(node.directives);
    writeDocComments(
      b,
      node.description?.value,
      extra: [if (deprecReason != null) 'Deprecated: $deprecReason'],
    );

    b.writeln("  router.post('$route', (Request req) async {");
    b.writeln("    final body = await req.readAsString();");
    b.writeln(
      "    final args = body.isNotEmpty ? jsonDecode(body) as Map<String, dynamic> : <String, dynamic>{};",
    );
    b.writeln("    final resolver = resolverRegistry['$resolverKey'];");
    b.writeln("    if (resolver == null) {");
    b.writeln(
      "      return Response.internalServerError(body: 'Resolver not found: $resolverKey');",
    );
    b.writeln("    }");
    b.writeln("    try {");
    b.writeln("      final result = await resolver(null, args);");
    b.writeln(
      "      return Response.ok(jsonEncode(result), headers: {'Content-Type': 'application/json'});",
    );
    b.writeln("    } catch (e, st) {");
    b.writeln(
      "      return Response.internalServerError(body: 'Error: \$e\\n\$st');",
    );
    b.writeln("    }");
    b.writeln("  });");
    b.writeln();
  }

  b.writeln('  return router;');
  b.writeln('}');
  b.writeln();

  out.writeAsStringSync(b.toString());
}

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
    'void registerRestRoutes(Router router, {String prefix = "", Map<String, String>? cors}) {',
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

GeneratedEndpoint? generateQueryEndpointFile(
  Directory endpointsDir,
  DocumentNode document,
  FieldDefinitionNode field,
) {
  final fieldName = field.name.value;
  final pascal = convertName(fieldName);
  final snake = toSnakeCase(fieldName);
  final handlerName = 'query${pascal}Endpoint';
  final file = File(
    path.join('${endpointsDir.path}/endpoints', 'query_${snake}_endpoint.dart'),
  );

  if (file.existsSync()) {
    return GeneratedEndpoint(
      file.path,
      handlerName,
      '/query/$fieldName',
      field: field,
    );
  }

  final retBase = getBaseTypeName(field.type);
  final isListTop = isListType(field.type);
  final isScalarTop = isScalar(retBase);

  final resolverImports = <String>{};
  // the root resolver of the query
  final rootResolverImport = '../../resolvers/query_${snake}_resolver.dart';
  resolverImports.add(rootResolverImport);

  // Generate the body first to collect sub-resolver imports
  final body = StringBuffer();

  body.writeln('Handler $handlerName(Map<String, String>? cors) {');
  body.writeln('  return (Request req) async {');
  body.writeln('    final body = await req.readAsString();');
  body.writeln(
    '    final jsonBody = body.isNotEmpty ? jsonDecode(body) as Map<String, dynamic> : <String, dynamic>{};',
  );
  body.writeln('    final args = <String, dynamic>{ ...req.context };');

  // direct field args
  for (final arg in field.args) {
    final a = arg.name.value;
    body.writeln(
      "    if (jsonBody.containsKey('$a')) { args['$a'] = jsonBody['$a']; }",
    );
  }

  // call the root resolver
  final rootResolverFn = '${dartFieldNameForResolver(fieldName)}Resolver';
  body.writeln();
  body.writeln('    final result = await $rootResolverFn(null, args);');

  // top-level serialization
  if (isListTop) {
    if (isScalarTop) {
      body.writeln('    final wrapped = {"data": (result as List?) ?? []};');
    } else {
      body.writeln('    final resultList = (result as List?) ?? [];');
      body.writeln(
        '    final resultJson = resultList.map((e) => e.toJson()).toList();',
      );
      // nested population (for each item)
      // NOTE: if the top-level is a list of objects, loop here over each item
      // and call emitNestedPopulation with parentSerVar/itemJson variables.
      body.writeln('    final wrapped = {"data": resultJson};');
    }
  } else {
    if (isScalarTop) {
      body.writeln('    final wrapped = {"data": result};');
    } else {
      body.writeln(
        '    final resultJson = result?.toJson() ?? <String, dynamic>{};',
      );
      // ---- nested resolvers from the type returned by the query ----
      emitNestedPopulation(
        body,
        document,
        parentGqlType: retBase, // e.g. "_Company"
        argsAccessor: 'jsonBody',
        parentSerVar: 'result',
        parentJsonVar: 'resultJson',
        depth: 2,
        resolverImports: resolverImports,
      );
      body.writeln('    final wrapped = {"data": resultJson};');
    }
  }

  body.writeln(
    '    return Response.ok(jsonEncode(wrapped), headers: {"Content-Type": "application/json"});',
  );
  body.writeln('  };');
  body.writeln('}');

  // Now that all imports are known:
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
  buf.write(body.toString());

  file.createSync(recursive: true);
  file.writeAsStringSync(buf.toString());

  return GeneratedEndpoint(
    file.path,
    handlerName,
    '/query/$fieldName',
    field: field,
  );
}

GeneratedEndpoint? generateMutationEndpointFile(
  Directory endpointsDir,
  DocumentNode document,
  FieldDefinitionNode field,
) {
  final fieldName = field.name.value;
  final pascal = convertName(fieldName);
  final snake = toSnakeCase(fieldName);
  final handlerName = 'mutation${pascal}Endpoint';
  final file = File(
    path.join(
      '${endpointsDir.path}/endpoints',
      'mutation_${snake}_endpoint.dart',
    ),
  );

  if (file.existsSync()) {
    return GeneratedEndpoint(
      file.path,
      handlerName,
      '/mutation/$fieldName',
      field: field,
    );
  }

  final retBase = getBaseTypeName(field.type);
  final isListTop = isListType(field.type);
  final isScalarTop = isScalar(retBase);

  final resolverImports = <String>{};
  resolverImports.add('../../resolvers/mutation_${snake}_resolver.dart');

  final body = StringBuffer();

  body.writeln('Handler $handlerName(Map<String, dynamic>? cors) {');
  body.writeln('  return (Request req) async {');
  body.writeln('    final body = await req.readAsString();');
  body.writeln(
    '    final jsonBody = body.isNotEmpty ? jsonDecode(body) as Map<String, dynamic> : <String, dynamic>{};',
  );
  body.writeln('    final args = <String, dynamic>{};');

  // Direct arguments
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
      body.writeln('    final wrapped = {"data": (result as List?) ?? []};');
    } else {
      body.writeln('    final resultList = (result as List?) ?? [];');
      body.writeln(
        '    final resultJson = resultList.map((e) => e.toJson()).toList();',
      );
      // option to recurse for each item
      body.writeln('    final wrapped = {"data": resultJson};');
    }
  } else {
    if (isScalarTop) {
      body.writeln('    final wrapped = {"data": result};');
    } else {
      body.writeln(
        '    final resultJson = result?.toJson() ?? <String, dynamic>{};',
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
      body.writeln('    final wrapped = {"data": resultJson};');
    }
  }

  body.writeln(
    '    return Response.ok(jsonEncode(wrapped), headers: {"Content-Type": "application/json"});',
  );
  body.writeln('  };');
  body.writeln('}');

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
  buf.write(body.toString());

  file.createSync(recursive: true);
  file.writeAsStringSync(buf.toString());

  return GeneratedEndpoint(
    file.path,
    handlerName,
    '/mutation/$fieldName',
    field: field,
  );
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
  buf.writeln("import 'dart:async';");
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

  file.createSync(recursive: true);
  file.writeAsStringSync(buf.toString());

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
