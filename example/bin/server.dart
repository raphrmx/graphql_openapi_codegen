/// The whole server: mount what the generator wrote, and serve.
///
/// ```bash
/// dart run bin/server.dart
/// ```
///
/// Then open http://localhost:8080/docs/graphql to query the API from the
/// Playground, or http://localhost:8080/docs/rest to call it from Swagger UI.
library;

import 'dart:convert';
import 'dart:io';

import 'package:acme_shop_api/graphql/fields/mutation_fields.dart';
import 'package:acme_shop_api/graphql/fields/query_fields.dart';
import 'package:acme_shop_api/rest/rest_routes.dart';
import 'package:acme_shop_api/routes/doc_routes.dart';
import 'package:graphql_schema3/graphql_schema3.dart';
import 'package:graphql_server3/graphql_server3.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

/// The schema, assembled from the two generated field lists.
///
/// This is the only place the GraphQL side has to be wired by hand, and it does
/// not change when the schema does: adding a query adds an entry to
/// `queryFields`, which is regenerated.
final GraphQLSchema schema = GraphQLSchema(
  queryType: objectType('Query', fields: queryFields),
  mutationType: objectType('Mutation', fields: mutationFields),
);

Future<void> main() async {
  final graphQL = GraphQL(schema);
  final router = Router();

  // POST /graphql, the API itself. The Playground page posts here.
  router.post('/graphql', (Request request) async {
    final body = jsonDecode(await request.readAsString());
    final payload = body as Map<String, dynamic>;
    try {
      final data = await graphQL.parseAndExecute(
        payload['query'] as String,
        operationName: payload['operationName'] as String?,
        variableValues: (payload['variables'] as Map?)?.cast() ?? const {},
      );
      return _json({'data': data});
    } on GraphQLException catch (e) {
      return _json(e.toJson());
    }
  });

  // GET /static/openapi.yaml, the document Swagger UI reads. It is the
  // `routes.openapi` of pubspec.yaml, so the generated page already points
  // here; serving the file is ours to do.
  router.get('/static/openapi.yaml', (Request request) async {
    final file = File('assets/openapi.yaml');
    if (!file.existsSync()) {
      return Response.notFound('Run the generator first.');
    }
    return Response.ok(
      await file.readAsString(),
      headers: {'Content-Type': 'application/yaml'},
    );
  });

  // Everything below is generated, and regenerated when the schema moves.
  registerRestRoutes(router);
  registerDocRoutes(router);

  final server = await io.serve(router.call, InternetAddress.anyIPv4, 8080);
  stdout.writeln('Listening on http://localhost:${server.port}');
  stdout.writeln(
    '  GraphQL Playground  http://localhost:${server.port}/docs/graphql',
  );
  stdout.writeln(
    '  Swagger UI          http://localhost:${server.port}/docs/rest',
  );
}

Response _json(Object? payload) => Response.ok(
  jsonEncode(payload),
  headers: {'Content-Type': 'application/json'},
);
