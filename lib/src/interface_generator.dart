import 'dart:io';

import 'package:gql/ast.dart';
import 'package:graphql_openapi_codegen/src/helpers.dart';
import 'package:graphql_openapi_codegen/src/type_info.dart';
import 'package:path/path.dart' as path;
import 'package:recase/recase.dart';

/// Generates a Dart abstract class from a GraphQL interface type definition.
///
/// This function automates the creation of Dart interfaces, which are crucial
/// for modeling polymorphism in a type-safe manner. It translates a GraphQL
/// `interface` into a Dart `abstract class` that defines the shared fields
/// and their types. The generated file is part of a larger, cohesive
/// generated codebase.
///
/// Parameters:
/// - [outputDir]: The directory where the generated Dart file will be saved.
/// - [node]: The GraphQL `InterfaceTypeDefinitionNode` to be processed.
void generateInterfaceClass(
  Directory outputDir,
  InterfaceTypeDefinitionNode node,
) {
  final className = ReCase(node.name.value).pascalCase;
  final fileName = toSnakeCase(className);
  final outputFile = File(path.join(outputDir.path, '$fileName.dart'));
  final deprecReason = getDeprecationReason(node.directives);
  final buffer = StringBuffer();

  final classDoc = docForAnnotation(
    node.description?.value,
    deprecated: deprecReason,
  );

  /// Conditionally applies the `@Deprecated` annotation if the GraphQL interface
  /// is marked as deprecated. This ensures that the generated Dart code provides
  /// correct compiler warnings.
  if (deprecReason != null) {
    buffer.writeln("@Deprecated(${dartStringLiteral(deprecReason)})");
  }

  /// Conditionally adds the `@GraphQLDocumentation` annotation with the formatted
  /// documentation string.
  if (classDoc.isNotEmpty) {
    buffer.writeln(
      "@GraphQLDocumentation(description: ${dartStringLiteral(classDoc)})",
    );
  }

  /// Begins the Dart abstract class definition. Abstract classes are the idiomatic
  /// way to represent interfaces in Dart, as they can define abstract fields.
  buffer.writeln('abstract class $className {');

  /// Iterates through each field of the GraphQL interface and generates the
  /// corresponding abstract getter in the Dart class. The type information is
  /// translated using a helper function to ensure correctness and nullability.
  for (final field in node.fields) {
    final typeInfo = getDartType(field.type);
    buffer.writeln(
      '  ${typeInfo.dartType}${typeInfo.isNullable ? '?' : ''} get ${dartFieldNameForProperty(field.name.value)};',
    );
  }

  /// Closes the class definition.
  buffer.writeln('}');

  writeGeneratedLibrary(
    outputFile,
    description: node.description?.value,
    extra: ['GraphQL interface: $className.', 'Auto generated. Do not edit.'],
    // The annotations written above come from `graphql_schema3`; the file used
    // to emit them without importing anything, so it would not have compiled.
    imports: ImportBlock()..add('package:graphql_schema3/graphql_schema3.dart'),
    body: buffer.toString(),
  );
}
