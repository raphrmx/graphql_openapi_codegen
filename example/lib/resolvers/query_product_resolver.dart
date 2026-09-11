// Created once by GraphQL Code-Gen. Edit freely; it will NOT be overwritten.
import 'package:acme_shop_api/catalogue.dart';
import 'package:acme_shop_api/models/product_query.dart';
import 'package:acme_shop_api/models/product_type.dart';

/// Reads one product, or null when the catalogue does not hold it.
///
/// [args] arrives the same way through both front doors: the GraphQL executor
/// coerces the `query` argument, the REST endpoint hands over the decoded JSON
/// body, and `ProductQuery.fromJson` takes either.
Future<Product?> productResolver(
  Object? serialized,
  Map<String, dynamic> args,
) {
  final query = ProductQuery.fromJson(args['query']);
  return Future.value(catalogue[query.sku]);
}
