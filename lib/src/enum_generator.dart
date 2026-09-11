import 'dart:io';

import 'package:gql/ast.dart';
import 'package:graphql_openapi_codegen/src/helpers.dart';
import 'package:path/path.dart' as path;

final enumBuffer = StringBuffer();

/// Generates a Dart enum class from a GraphQL enum type definition.
///
/// This function is designed to handle the generation of a single enum entry within a shared file.
/// This approach is efficient as it avoids creating a separate file for each small enum,
/// which would lead to a cluttered project structure and increased build times. Instead,
/// all enums are collected and written to a single `enums.dart` file by [ensureEnumsFile].
///
/// Parameters:
/// - [outputDir]: The output directory where the `enums.dart` file will be stored.
/// - [document]: The GraphQL document node containing the schema.
/// - [node]: The GraphQL `EnumTypeDefinitionNode` to be converted into a Dart enum.
void generateEnumClass(
  Directory outputDir,
  DocumentNode document,
  EnumTypeDefinitionNode node,
) {
  final deprecReason = getDeprecationReason(node.directives);
  final className = convertName(node.name.value);

  /// Separates the enums with a blank line. The preamble is not written here:
  /// a library doc comment has to sit against the `library;` directive, so the
  /// whole preamble is assembled once, in [ensureEnumsFile].
  if (enumBuffer.isNotEmpty) enumBuffer.writeln();

  final classDoc = docForAnnotation(
    node.description?.value,
    deprecated: deprecReason,
  );

  /// The documentation comes first, then the annotations, then the declaration.
  /// A doc comment written between two annotations documents nothing.
  writeDocComments(
    enumBuffer,
    node.description?.value,
    extra: [if (deprecReason != null) 'Deprecated: $deprecReason'],
  );

  /// The `@graphQLClass` annotation provides a clear link between the generated
  /// Dart code and its GraphQL schema origin, which is useful for future
  /// introspection or tooling.
  enumBuffer.writeln('@graphQLClass');

  /// Applies the `@Deprecated` annotation if the GraphQL enum is marked as deprecated.
  /// This helps in maintaining code quality by providing compiler warnings
  /// when deprecated enums are used.
  if (deprecReason != null) {
    enumBuffer.writeln('@Deprecated(${dartStringLiteral(deprecReason)})');
  }

  if (classDoc.isNotEmpty) {
    enumBuffer.writeln(
      '@GraphQLDocumentation(description: ${dartStringLiteral(classDoc)})',
    );
  }

  /// Generates the Dart enum declaration.
  enumBuffer.writeln('enum $className {');

  /// Iterates through each value of the GraphQL enum and generates a corresponding
  /// constant in the Dart enum. This direct mapping ensures perfect synchronization
  /// between the schema and the code.
  for (final child in node.values) {
    final valueDeprecReason = getDeprecationReason(child.directives);
    final valueDoc = docForAnnotation(
      child.description?.value,
      deprecated: valueDeprecReason,
    );

    writeDocComments(
      enumBuffer,
      child.description?.value,
      padding: '  ',
      extra: [if (valueDeprecReason != null) 'Deprecated: $valueDeprecReason'],
    );

    if (valueDeprecReason != null) {
      enumBuffer.writeln(
        '  @Deprecated(${dartStringLiteral(valueDeprecReason)})',
      );
    }

    if (valueDoc.isNotEmpty) {
      enumBuffer.writeln(
        '  @GraphQLDocumentation(description: ${dartStringLiteral(valueDoc)})',
      );
    }
    enumBuffer.writeln('  ${child.name.value},');
  }
  enumBuffer.writeln('}');
}

/// Ensures that the buffer containing generated enum code is written to a file.
///
/// This function is a critical part of the single-file generation strategy.
/// It should be called after all enum types have been processed.
/// The check `if (enumBuffer.isNotEmpty)` is a defensive measure to prevent
/// the creation of an empty `enums.dart` file if no enums were defined in the schema.
///
/// After writing the file, the buffer is cleared to prepare for the next generation run,
/// preventing duplicate content.
///
/// Parameters:
/// - [outputDir]: The output directory where the final `enums.dart` file will be created.
void ensureEnumsFile(Directory outputDir) {
  if (enumBuffer.isEmpty) return;

  final enumFile = File(path.join(outputDir.path, 'enums.dart'));

  writeGeneratedLibrary(
    enumFile,
    description: 'The enums of the GraphQL schema.',
    extra: ['Auto generated file. Please do not edit manually.'],
    imports: ImportBlock()..add('package:graphql_schema3/graphql_schema3.dart'),
    partFile: 'enums.g.dart',
    // GraphQL spells its enum values in SCREAMING_CASE, and the Dart constants
    // mirror the schema on purpose: renaming them would change both the wire
    // format and every call site. The rule is silenced rather than obeyed.
    ignoreForFile: const ['constant_identifier_names'],
    body: enumBuffer.toString(),
  );

  enumBuffer.clear();
}
