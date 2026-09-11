/// Auto generated central REST routes.
/// Aggregates all Query/Mutation/Subscription REST endpoints.
library;

import 'package:acme_shop_api/rest/endpoints/mutation_upsert_product_endpoint.dart';
import 'package:acme_shop_api/rest/endpoints/query_product_endpoint.dart';
import 'package:shelf_router/shelf_router.dart';

void registerRestRoutes(
  Router router, {
  String prefix = '/rest',
  Map<String, String>? cors,
}) {
  router.post('$prefix/query/product', queryProductEndpoint(cors));
  router.post(
    '$prefix/mutation/upsertProduct',
    mutationUpsertProductEndpoint(cors),
  );
}
