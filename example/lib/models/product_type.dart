/// A product on sale.
/// GraphQL type: Product.
/// Auto generated file. Please do not edit manually.
library;

import 'package:acme_shop_api/models/enums.dart';
import 'package:graphql_schema3/graphql_schema3.dart';
import 'package:json_annotation/json_annotation.dart';

part 'product_type.g.dart';

/// A product on sale.
@graphQLClass
@GraphQLDocumentation(description: 'A product on sale.')
@JsonSerializable()
class Product {
  /// The stock keeping unit. Unique across the catalogue.
  /// Required.
  @GraphQLDocumentation(
    description: 'The stock keeping unit. Unique across the catalogue.',
  )
  final String sku;

  /// Required.
  final String label;

  /// The price in cents, to keep the wire format free of floating point.
  /// Required.
  @GraphQLDocumentation(
    description:
        'The price in cents, to keep the wire format free of floating point.',
  )
  final int priceCents;

  /// Required.
  final Availability availability;

  Product({
    required this.sku,
    required this.label,
    required this.priceCents,
    required this.availability,
  });

  factory Product.fromJson(Object? json) =>
      _$ProductFromJson({...?(json as Map<String, dynamic>?)});

  Map<String, dynamic> toJson() => _$ProductToJson(this);
}
