import 'dart:io';

import 'package:gql/ast.dart';
import 'package:graphql_openapi_codegen/src/helpers.dart';
import 'package:path/path.dart' as path;

/// Generates a Dart class for a GraphQL union type.
///
/// This function is a core part of a code generation pipeline, responsible for
/// translating GraphQL's union types into a Dart representation. It creates a
/// Dart abstract class that serves as a common type for all its members,
/// which is essential for handling polymorphic data safely.
///
/// Parameters:
/// - [outputDir]: The directory where the generated file will be saved.
/// - [document]: The full GraphQL document AST, used to find member type definitions.
/// - [node]: The GraphQL `UnionTypeDefinitionNode` to be processed.
void generateUnionClass(
  Directory outputDir,
  DocumentNode document,
  UnionTypeDefinitionNode node,
) {
  final className = convertName(node.name.value);
  final fileName = toSnakeCase(className);
  final outputFile = File(path.join(outputDir.path, '$fileName.dart'));
  final deprecReason = getDeprecationReason(node.directives);
  final buffer = StringBuffer();

  // Declares what the body needs; the preamble itself is rendered once, below.
  final imports = ImportBlock()
    ..add('package:graphql_schema3/graphql_schema3.dart');

  // Finds the type definitions for each member of the union.
  final memberTypeDefs = node.types
      .map(
        (t) =>
            document.definitions.firstWhere(
                  (d) =>
                      d is TypeDefinitionNode && d.name.value == t.name.value,
                )
                as TypeDefinitionNode,
      )
      .toList();

  // Collects the converted Dart class names of the union members.
  final memberDartNames = <String>[];
  for (final def in memberTypeDefs) {
    final dartName = convertName(
      def.name.value,
    ); // ex: _BddInvoiceTotal -> BmcBddInvoiceTotal
    memberDartNames.add(dartName);

    // Generates the import statements for each member's file. This ensures the
    // generated union class can reference its members.
    final isObjectType = def is ObjectTypeDefinitionNode;
    final importFile =
        "${toSnakeCase(dartName)}${isObjectType ? '_type' : ''}.dart";
    imports.addLibFile(path.join(outputDir.path, importFile));
  }

  /// Adds `@Deprecated` and `@GraphQLDocumentation` annotations if applicable.
  final classDoc = docForAnnotation(
    node.description?.value,
    deprecated: deprecReason,
  );
  if (deprecReason != null) {
    buffer.writeln("@Deprecated(${dartStringLiteral(deprecReason)})");
  }
  if (classDoc.isNotEmpty) {
    buffer.writeln(
      "@GraphQLDocumentation(description: ${dartStringLiteral(classDoc)})",
    );
  }

  // Creates the list literal for the `@GraphQLUnion` annotation.
  final typesLiteral = '[${memberDartNames.join(', ')}]';

  // Generates the GraphQLUnion annotation, which is processed by the build runner.
  // The Dart class is defined as `abstract` because a union type doesn't
  // have its own fields; it's a conceptual grouping of other types.
  buffer.writeln('@GraphQLUnion(types: $typesLiteral)');
  buffer.writeln('abstract class $className {}');

  writeGeneratedLibrary(
    outputFile,
    description: node.description?.value,
    extra: ['GraphQL union: $className.', 'Auto generated. Do not edit.'],
    imports: imports,
    partFile: '$fileName.g.dart',
    body: buffer.toString(),
  );
}
