/// The full state of a product, as the caller wants it stored.
/// GraphQL type: ProductInput.
/// Auto generated file. Please do not edit manually.
library;

import 'package:acme_shop_api/models/enums.dart';
import 'package:acme_shop_api/validators/validators.dart';
import 'package:graphql_schema3/graphql_schema3.dart';
import 'package:json_annotation/json_annotation.dart';

part 'product_input.g.dart';

/// The full state of a product, as the caller wants it stored.
@GraphQLInputClass()
@GraphQLDocumentation(
  description: 'The full state of a product, as the caller wants it stored.',
)
@JsonSerializable()
class ProductInput {
  /// Required.
  final String sku;

  /// Required.
  final String label;

  /// Required.
  final int priceCents;

  /// Optional.
  /// Default: IN_STOCK
  final Availability? availability;

  ProductInput({
    required this.sku,
    required this.label,
    required this.priceCents,
    this.availability,
  }) : assert(validSkuFormat(sku));

  factory ProductInput.fromJson(Object? json) =>
      _$ProductInputFromJson({...?(json as Map<String, dynamic>?)});

  Map<String, dynamic> toJson() => _$ProductInputToJson(this);
}
