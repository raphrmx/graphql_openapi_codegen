import 'package:gql/ast.dart';

import 'package:graphql_openapi_codegen/src/helpers.dart';

/// A simple data class that holds information about a converted Dart type.
///
/// This class is used as a return type for `getDartType` to encapsulate both
/// the type name as a string and its nullability, allowing for cleaner
/// and more type-safe handling of complex return types.
class TypeInfo {
  final String dartType;
  final bool isNullable;

  TypeInfo(this.dartType, this.isNullable);
}

/// Recursively converts a GraphQL type definition into its corresponding Dart type information.
///
/// This function is a cornerstone of a GraphQL code generator. Its primary role
/// is to map the GraphQL type system, including scalars, lists, and custom
/// types, to a strongly-typed Dart representation. The recursive nature of this
/// function allows it to correctly handle nested structures, such as `[[String!]!]!`.
///
/// Parameters:
/// - [type]: The GraphQL `TypeNode` to be translated.
///
/// Returns:
/// - A `TypeInfo` object containing the Dart type string and its nullability.
TypeInfo getDartType(TypeNode type) {
  /// Handles `NamedTypeNode`s, which represent a single type (e.g., `String`, `User`).
  if (type is NamedTypeNode) {
    final name = type.name.value;
    String dartType;

    /// Uses a `switch` statement to map standard GraphQL scalar names to
    /// their corresponding idiomatic Dart types. This is the most direct form
    /// of type translation.
    switch (name) {
      case 'String':
        dartType = 'String';
      case 'Int':
        dartType = 'int';
      case 'Float':
        dartType = 'double';
      case 'Boolean':
        dartType = 'bool';
      case 'ID':
        dartType = 'String';
      case 'DateTime':
        dartType = 'DateTime';
      case 'JSON':
        dartType = 'Map<String, dynamic>';
      default:

        /// Any other named type is a custom one (object, enum, ...), and the
        /// Dart class name comes from the naming convention alone. This used to
        /// re-read and re-parse the whole SDL here, once per named type, only
        /// to throw the result away.
        dartType = convertName(name);
    }

    /// Returns the converted type name along with its nullability.
    return TypeInfo(dartType, !type.isNonNull);
  }

  /// Handles `ListTypeNode`s. This is the **recursive** part of the function.
  /// It calls `getDartType` on the list's inner type to get its Dart type and
  /// nullability, then correctly wraps it in a Dart `List<...>`.
  if (type is ListTypeNode) {
    final innerTypeInfo = getDartType(type.type);
    return TypeInfo(
      'List<${innerTypeInfo.dartType}${innerTypeInfo.isNullable ? '?' : ''}>',
      !type.isNonNull,
    );
  }

  /// Provides a fallback for any unrecognized type. This is a defensive measure
  /// to prevent crashes with unsupported type nodes.
  return TypeInfo('dynamic', true);
}
