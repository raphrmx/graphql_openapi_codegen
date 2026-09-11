// A class that represents a reference to a GraphQL type.
///
/// This class encapsulates the three core components of any GraphQL type:
/// the base type itself (e.g., String, Int), its nullability, and whether it
/// is a list. The design is recursive, allowing for the correct representation
/// of complex list structures (e.g., `[[String!]!]!`).
///
/// This abstraction is essential for a code generator to reliably translate
/// GraphQL schema type definitions into a valid, strongly-typed Dart representation.
class GraphQLTypeRef {
  /// The base GraphQL type name, such as `graphQLString` or a custom type name like `myTypeGraphQLType`.
  /// This field is null for list types, as the base type is represented by the `inner` field.
  final String? base;

  /// A boolean flag indicating whether the type is non-nullable (`!`).
  /// A value of `true` means the type cannot be null.
  final bool isNonNull;

  /// A boolean flag indicating whether the type is a list (`[]`).
  final bool isList;

  /// For list types, this field holds the `GraphQLTypeRef` for the inner
  /// type of the list. It is `null` for non-list types.
  final GraphQLTypeRef? inner;

  /// Private constructor for scalar types.
  ///
  /// This factory is used to create a reference to a scalar GraphQL type.
  GraphQLTypeRef.scalar(this.base, this.isNonNull)
    : isList = false,
      inner = null;

  /// Private constructor for custom object or enum types.
  ///
  /// This factory is used to create a reference to a custom GraphQL type.
  GraphQLTypeRef.custom(this.base, this.isNonNull)
    : isList = false,
      inner = null;

  /// Private constructor for list types.
  ///
  /// This factory constructs a list type by encapsulating the type of its
  /// elements within the `inner` field. The `base` field is intentionally
  /// set to `null` to indicate that this is a list type.
  GraphQLTypeRef.list(this.inner, this.isNonNull) : isList = true, base = null;

  /// Generates the Dart expression for the GraphQL type.
  ///
  /// This getter recursively builds the full type expression required for a
  /// `graphql_schema` library definition. It correctly handles the nesting
  /// of lists and the application of `nonNullable()` to the final expression.
  ///
  /// Returns:
  /// A `String` representing the Dart expression for the GraphQL type.
  String get dartExpr {
    String expr;
    if (isList) {
      expr = 'listOf(${inner!.dartExpr})';
    } else {
      expr = base!;
    }
    if (isNonNull) {
      expr = '$expr.nonNullable()';
    }
    return expr;
  }
}
