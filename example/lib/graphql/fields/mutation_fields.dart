/// Auto generated Mutation fields. Do not edit.
/// Generated from GraphQL Mutation.
library;

import 'package:acme_shop_api/models/product_input.dart';
import 'package:acme_shop_api/models/product_type.dart';
import 'package:acme_shop_api/resolvers/mutation_upsert_product_resolver.dart';
import 'package:graphql_schema3/graphql_schema3.dart';

final Iterable<GraphQLObjectField<dynamic, dynamic>> mutationFields = [
  field(
    'upsertProduct',
    productGraphQLType.nonNullable(),
    description:
        'Creates a product, or replaces the one already carrying that SKU.',
    inputs: [
      GraphQLFieldInput('input', productInputInputGraphQLType.nonNullable()),
    ],
    resolve: upsertProductResolver,
  ),
];
