/// Identifies the one product to read.
/// GraphQL type: ProductQuery.
/// Auto generated file. Please do not edit manually.
library;

import 'package:acme_shop_api/validators/validators.dart';
import 'package:graphql_schema3/graphql_schema3.dart';
import 'package:json_annotation/json_annotation.dart';

part 'product_query.g.dart';

/// Identifies the one product to read.
@GraphQLInputClass()
@GraphQLDocumentation(description: 'Identifies the one product to read.')
@JsonSerializable()
class ProductQuery {
  /// Required.
  final String sku;

  ProductQuery({required this.sku}) : assert(validSkuFormat(sku));

  factory ProductQuery.fromJson(Object? json) =>
      _$ProductQueryFromJson({...?(json as Map<String, dynamic>?)});

  Map<String, dynamic> toJson() => _$ProductQueryToJson(this);
}
