// Created once by GraphQL/REST Code-Gen. Edit freely; it will NOT be overwritten.
import 'dart:convert';

import 'package:acme_shop_api/resolvers/query_product_resolver.dart';
import 'package:shelf/shelf.dart';

Handler queryProductEndpoint(Map<String, String>? cors) {
  return (Request req) async {
    final body = await req.readAsString();
    final jsonBody = body.isNotEmpty
        ? jsonDecode(body) as Map<String, dynamic>
        : <String, dynamic>{};
    final args = <String, dynamic>{...req.context};
    if (jsonBody.containsKey('query')) args['query'] = jsonBody['query'];

    final result = await productResolver(null, args);
    final resultJson = result?.toJson() ?? <String, dynamic>{};
    final wrapped = {'data': resultJson};
    return Response.ok(
      jsonEncode(wrapped),
      headers: {'Content-Type': 'application/json', ...?cors},
    );
  };
}
