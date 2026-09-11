import 'package:gql/ast.dart';

/// Merges GraphQL type extensions into their base type definitions within a document.
///
/// This function is crucial for a GraphQL schema parser that must handle `extend`
/// syntax. The GraphQL specification allows for type definitions and their
/// extensions to be defined in separate places. This method reconciles these
/// separate nodes by combining the fields, interfaces, directives, and other
/// properties from extension nodes into their corresponding base type definitions.
///
/// This process is performed in two main passes to ensure correct and efficient
/// merging:
/// 1.  An initial pass to index all base type definitions by a unique key.
/// 2.  A second pass to find and merge all extension definitions into their
///     indexed base types.
///
/// Parameters:
/// - [doc]: The input `DocumentNode` containing both type definitions and extensions.
///
/// Returns:
/// - A new `DocumentNode` where all type extensions have been merged into
///   their base type definitions.
DocumentNode mergeExtensions(DocumentNode doc) {
  final byKey = <String, TypeDefinitionNode>{};
  final passthrough = <DefinitionNode>[];

  /// Creates a unique key for each type definition based on its runtime type and name.
  /// This ensures that base types and their extensions can be uniquely identified,
  /// even if they share the same name (e.g., `ObjectTypeDefinitionNode` vs `InputObjectTypeDefinitionNode`).
  String defKey(TypeDefinitionNode d) => '${d.runtimeType}-${d.name.value}';

  /// First pass: Index all base type definitions and separate other nodes.
  /// This pass populates the `byKey` map, which acts as a lookup table for
  /// the second pass. Nodes that are not type definitions (e.g., `OperationDefinitionNode`)
  /// are added to the `passthrough` list for inclusion in the final document.
  for (final d in doc.definitions) {
    if (d is TypeDefinitionNode) {
      byKey[defKey(d)] = d;
    } else {
      passthrough.add(d);
    }
  }

  /// Second pass: Merge extension nodes into their base types.
  /// This loop iterates through the document again, specifically looking for extension nodes.
  /// For each extension found, it attempts to locate the corresponding base type
  /// in the `byKey` map. If found, a new, merged `TypeDefinitionNode` is created
  /// with the combined properties from both the base and the extension.
  for (final d in doc.definitions) {
    if (d is ObjectTypeExtensionNode) {
      final k = 'ObjectTypeDefinitionNode-${d.name.value}';
      final base = byKey[k] as ObjectTypeDefinitionNode?;
      if (base != null) {
        byKey[k] = ObjectTypeDefinitionNode(
          name: base.name,
          description: base.description,
          directives: [...base.directives, ...d.directives],
          interfaces: [...base.interfaces, ...d.interfaces],
          fields: [...base.fields, ...d.fields],
        );
      }
    } else if (d is InputObjectTypeExtensionNode) {
      final k = 'InputObjectTypeDefinitionNode-${d.name.value}';
      final base = byKey[k] as InputObjectTypeDefinitionNode?;
      if (base != null) {
        byKey[k] = InputObjectTypeDefinitionNode(
          name: base.name,
          description: base.description,

          /// Combines directives, interfaces, and fields from both the base type and the extension.
          /// The spread operator (`...`) creates new lists, ensuring that the original
          /// AST nodes are not mutated, which is a key principle of functional programming.
          directives: [...base.directives, ...d.directives],
          fields: [...base.fields, ...d.fields],
        );
      }
    } else if (d is InterfaceTypeExtensionNode) {
      final k = 'InterfaceTypeDefinitionNode-${d.name.value}';
      final base = byKey[k] as InterfaceTypeDefinitionNode?;
      if (base != null) {
        byKey[k] = InterfaceTypeDefinitionNode(
          name: base.name,
          description: base.description,
          directives: [...base.directives, ...d.directives],
          fields: [...base.fields, ...d.fields],
        );
      }
    } else if (d is EnumTypeExtensionNode) {
      final k = 'EnumTypeDefinitionNode-${d.name.value}';
      final base = byKey[k] as EnumTypeDefinitionNode?;
      if (base != null) {
        byKey[k] = EnumTypeDefinitionNode(
          name: base.name,
          description: base.description,
          directives: [...base.directives, ...d.directives],
          values: [...base.values, ...d.values],
        );
      }
    } else if (d is UnionTypeExtensionNode) {
      final k = 'UnionTypeDefinitionNode-${d.name.value}';
      final base = byKey[k] as UnionTypeDefinitionNode?;
      if (base != null) {
        byKey[k] = UnionTypeDefinitionNode(
          name: base.name,
          description: base.description,
          directives: [...base.directives, ...d.directives],
          types: [...base.types, ...d.types],
        );
      }
    } else if (d is ScalarTypeExtensionNode) {
      final k = 'ScalarTypeDefinitionNode-${d.name.value}';
      final base = byKey[k] as ScalarTypeDefinitionNode?;
      if (base != null) {
        byKey[k] = ScalarTypeDefinitionNode(
          name: base.name,
          description: base.description,
          directives: [...base.directives, ...d.directives],
        );
      }
    }
  }

  /// Constructs the final `DocumentNode`.
  /// The final document is built from the merged type definitions in `byKey.values`
  /// and the non-extension nodes from the `passthrough` list. The `where` clause
  /// on `passthrough` is a defensive measure to exclude any extension nodes that
  /// may have been added to the list in the first pass.
  return DocumentNode(
    definitions: [
      ...byKey.values,
      ...passthrough.where((d) => d is! TypeExtensionNode),
    ],
  );
}
