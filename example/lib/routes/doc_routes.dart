/// Auto generated documentation routes.
/// Mounts the GraphQL and REST documentation pages.
library;

import 'package:acme_shop_api/routes/graphql_doc_route.dart';
import 'package:acme_shop_api/routes/rest_doc_route.dart';
import 'package:shelf_router/shelf_router.dart';

void registerDocRoutes(
  Router router, {
  String prefix = '',
  Map<String, String>? cors,
}) {
  router.get('$prefix/docs/graphql', graphQLDocHandler(cors ?? const {}));
  router.get('$prefix/docs/rest', restDocHandler(cors ?? const {}));
}
