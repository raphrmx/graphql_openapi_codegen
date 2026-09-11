import 'dart:io';

import 'package:collection/collection.dart';
import 'package:gql/ast.dart';
import 'package:graphql_openapi_codegen/src/class_generator.dart';
import 'package:graphql_openapi_codegen/src/config.dart';
import 'package:graphql_openapi_codegen/src/consts.dart';
import 'package:graphql_openapi_codegen/src/helpers.dart';
import 'package:path/path.dart' as path;

/// Generates a Dart class file for a GraphQL input type or object type.
///
/// This function is a central part of a code generation pipeline. It takes a
/// GraphQL type definition and generates a complete Dart file, including
/// documentation, necessary imports, and the class definition itself. The
/// generated class is ready for use with popular packages like `json_annotation`
/// and `copy_with_extension`.
///
/// Parameters:
/// - [outputDir]: The directory where the generated file will be saved.
/// - [document]: The full GraphQL document AST, used to resolve type dependencies.
/// - [node]: The GraphQL `TypeDefinitionNode` to be processed.
void generateInputClassFile(
  Directory outputDir,
  DocumentNode document,
  TypeDefinitionNode node,
) {
  final className = convertName(node.name.value);
  final isObjectType = node is ObjectTypeDefinitionNode;

  /// Determines the file name based on the class name and type. A naming
  /// convention is used to ensure consistency (e.g., `user_input.dart`).
  final fileName = toSnakeCase(className) + (isObjectType ? '_input' : '');
  final outputFile = File(path.join(outputDir.path, '$fileName.dart'));

  /// Determines if the input type requires a separate validator file.
  final needsValidators = needsValidatorsForInput(node);

  /// Declares what the body needs rather than writing the directives out.
  /// [ImportBlock] renders them de-duplicated, sorted and as `package:` URIs.
  final imports = ImportBlock()
    ..addAll(const [
      'package:graphql_schema3/graphql_schema3.dart',
      'package:json_annotation/json_annotation.dart',
    ]);

  /// Only pulled in when the annotation is actually emitted, so a package that
  /// turns `copy_with` off does not have to depend on it.
  if (importerConfig.copyWith) {
    imports.add('package:copy_with_extension/copy_with_extension.dart');
  }

  /// Custom types referenced by the current type.
  final importedTypes = getImportsForType(document, node).toList()
    ..sort((a, b) => a.compareTo(b));
  for (final importName in importedTypes) {
    final importedNode =
        document.definitions.firstWhereOrNull(
              (d) =>
                  d is TypeDefinitionNode &&
                  convertName(d.name.value) == importName,
            )
            as TypeDefinitionNode?;
    final importedIsObjectType = importedNode is ObjectTypeDefinitionNode;
    final importFileName =
        toSnakeCase(importName) + (importedIsObjectType ? '_input' : '');
    imports.addLibFile(path.join(outputDir.path, '$importFileName.dart'));
  }

  if (needsValidators) {
    imports.addLibFile('$validatorsDirPath/validators.dart');
  }

  /// Delegates the class generation to a separate function. This separation of
  /// concerns makes the code more modular and easier to maintain.
  final body = StringBuffer();
  generateClass(body, node, isInput: true);

  writeGeneratedLibrary(
    outputFile,
    description: node.description?.value,
    extra: [
      'GraphQL type: ${node.name.value}.',
      'Auto generated file. Please do not edit manually.',
    ],
    imports: imports,
    partFile: '$fileName.g.dart',
    body: body.toString(),
  );
}
