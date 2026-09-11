// Created once by GraphQL Code-Gen. Edit freely; it will NOT be overwritten.
import 'package:acme_shop_api/catalogue.dart';
import 'package:acme_shop_api/models/enums.dart';
import 'package:acme_shop_api/models/product_input.dart';
import 'package:acme_shop_api/models/product_type.dart';

/// Creates a product, or replaces the one already carrying that SKU.
///
/// `ProductInput` asserts the SKU format in its own constructor, through the
/// `@_skuFormat` directive, so nothing here has to check it again.
Future<Product> upsertProductResolver(
  Object? serialized,
  Map<String, dynamic> args,
) {
  final input = ProductInput.fromJson(args['input']);
  final product = Product(
    sku: input.sku,
    label: input.label,
    priceCents: input.priceCents,
    availability: input.availability ?? Availability.IN_STOCK,
  );
  catalogue[product.sku] = product;
  return Future.value(product);
}
