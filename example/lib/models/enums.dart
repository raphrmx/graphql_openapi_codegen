// ignore_for_file: constant_identifier_names
/// The enums of the GraphQL schema.
/// Auto generated file. Please do not edit manually.
library;

import 'package:graphql_schema3/graphql_schema3.dart';

part 'enums.g.dart';

/// Whether a product can be ordered right now.
@graphQLClass
@GraphQLDocumentation(
  description: 'Whether a product can be ordered right now.',
)
enum Availability { IN_STOCK, OUT_OF_STOCK }
