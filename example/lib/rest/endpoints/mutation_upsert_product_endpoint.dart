// Created once by GraphQL/REST Code-Gen. Edit freely; it will NOT be overwritten.
import 'dart:convert';

import 'package:acme_shop_api/resolvers/mutation_upsert_product_resolver.dart';
import 'package:shelf/shelf.dart';

Handler mutationUpsertProductEndpoint(Map<String, String>? cors) {
  return (Request req) async {
    final body = await req.readAsString();
    final jsonBody = body.isNotEmpty
        ? jsonDecode(body) as Map<String, dynamic>
        : <String, dynamic>{};
    final args = <String, dynamic>{...req.context};
    if (jsonBody.containsKey('input')) args['input'] = jsonBody['input'];

    final result = await upsertProductResolver(null, args);
    final resultJson = result.toJson();
    final wrapped = {'data': resultJson};
    return Response.ok(
      jsonEncode(wrapped),
      headers: {'Content-Type': 'application/json', ...?cors},
    );
  };
}
