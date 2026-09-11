import 'package:collection/collection.dart';
import 'package:gql/ast.dart';
import 'package:graphql_openapi_codegen/src/helpers.dart';
import 'package:recase/recase.dart';

/// Represents information about a generated Dart symbol, including its identifier
/// and the path to the file where it is defined.
///
/// This is a simple data class that provides a structured way to return
/// both the name of a generated symbol and its corresponding import path.
class SymbolInfo {
  final String ident;
  final String importPath;
  const SymbolInfo(this.ident, this.importPath);
}

/// Determines the generated Dart symbol and import path for a given GraphQL named type.
///
/// This is a core utility function in a code generator. It maps a GraphQL
/// type name to a corresponding Dart symbol and file location based on a
/// predefined set of naming conventions and file structures. This is crucial for
/// correctly generating import statements and referencing types.
///
/// Parameters:
/// - [document]: The full GraphQL document AST, used to find type definitions.
/// - [gqlName]: The GraphQL name of the type (e.g., 'DeviceInput', 'User').
///
/// Returns:
/// - A `SymbolInfo` object containing the Dart identifier and import path.
SymbolInfo symbolForNamed(DocumentNode document, String gqlName) {
  // Finds the definition for the GraphQL type. `firstWhereOrNull` is used
  /// for a safe lookup that returns `null` if no definition is found.
  final def = document.definitions
      .whereType<TypeDefinitionNode>()
      .firstWhereOrNull((d) => d.name.value == gqlName);

  /// Converts the GraphQL name to a Dart base name, then to `camelCase` for the symbol identifier.
  final dartBase = convertName(gqlName);
  final lower = ReCase(dartBase).camelCase;

  /// --- Mapping Logic ---

  /// If the type is an input object, it uses a specific naming and file path convention.
  if (def is InputObjectTypeDefinitionNode) {
    final ident = '${lower}InputGraphQLType';
    final importPath = '${toSnakeCase(dartBase)}.dart';
    return SymbolInfo(ident, importPath);
  }

  /// If the type is a standard object, it uses a different convention.
  if (def is ObjectTypeDefinitionNode) {
    final ident = '${lower}GraphQLType';
    final importPath = '${toSnakeCase(dartBase)}_type.dart';
    return SymbolInfo(ident, importPath);
  }

  /// If the type is an enum, it points to a centralized `enums.dart` file.
  /// This is a design choice to group all small enum types into a single location.
  if (def is EnumTypeDefinitionNode) {
    final ident = '${lower}GraphQLType';
    return SymbolInfo(ident, 'enums.dart');
  }

  /// Provides a fallback for any other type (e.g., scalars, custom scalars) that
  /// might not have a specific handling rule.
  return SymbolInfo(
    '${lower}GraphQLType',
    '${toSnakeCase(dartBase)}_type.dart',
  );
}
