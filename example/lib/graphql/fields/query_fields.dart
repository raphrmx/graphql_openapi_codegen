/// Auto generated Query fields. Do not edit.
/// Generated from GraphQL Query.
library;

import 'package:acme_shop_api/models/product_query.dart';
import 'package:acme_shop_api/models/product_type.dart';
import 'package:acme_shop_api/resolvers/query_product_resolver.dart';
import 'package:graphql_schema3/graphql_schema3.dart';

final Iterable<GraphQLObjectField<dynamic, dynamic>> queryFields = [
  field(
    'product',
    productGraphQLType,
    description:
        'Reads one product, or null when the catalogue does not hold it.',
    inputs: [
      GraphQLFieldInput('query', productQueryInputGraphQLType.nonNullable()),
    ],
    resolve: productResolver,
  ),
];
