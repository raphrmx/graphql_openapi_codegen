import 'dart:io';

import 'package:collection/collection.dart';
import 'package:gql/ast.dart';
import 'package:graphql_openapi_codegen/src/config.dart';
import 'package:graphql_openapi_codegen/src/consts.dart';
import 'package:graphql_openapi_codegen/src/helpers.dart';
import 'package:graphql_openapi_codegen/src/type_info.dart';
import 'package:path/path.dart' as path;
import 'package:recase/recase.dart';

/// Generates a Dart class definition from a GraphQL type definition.
///
/// This function serves as the core logic for translating a GraphQL schema node
/// into a compilable Dart class. It handles two primary node types:
/// `ObjectTypeDefinitionNode` (for GraphQL query/mutation types) and `InputObjectTypeDefinitionNode`
/// (for GraphQL input types), generating the appropriate class structure for each.
///
/// Parameters:
/// - [buffer]: The `StringBuffer` to which the generated code will be written.
/// - [node]: The GraphQL `TypeDefinitionNode` representing the type to be generated.
/// - [isInput]: A flag indicating if the node represents an input type. This is crucial for
///   applying correct annotations and validation logic.
/// - [implementsInterfaces]: A list of interface names this class should implement.
/// - [overrideFieldNames]: A set of field names inherited from interfaces that must
///   be marked with the `@override` annotation.
void generateClass(
  StringBuffer buffer,
  TypeDefinitionNode node, {
  bool isInput = false,
  List<String> implementsInterfaces = const [],
  Set<String> overrideFieldNames = const {},
}) {
  final className = convertName(node.name.value);
  final deprecReason = getDeprecationReason(node.directives);
  final isObjectType = node is ObjectTypeDefinitionNode;

  /// Retrieves all fields from the GraphQL type and separates them into
  /// properties and resolver methods. This early separation is key to
  /// correctly structuring the Dart class, as fields with arguments are
  /// treated as behaviors (methods) rather than data members.
  final allFields = getFieldsForType(node);

  /// `propertyFields` holds fields that will become class properties. For `Input` types,
  /// all fields are properties. For `Object` types, only fields without arguments are considered properties.
  final propertyFields = <dynamic>[];

  /// `methodFields` holds fields that will be generated as resolver methods.
  /// This applies exclusively to `ObjectTypeDefinitionNode` and its fields with arguments.
  final methodFields = <FieldDefinitionNode>[];

  for (final f in allFields) {
    if (isObjectType && f is FieldDefinitionNode && f.args.isNotEmpty) {
      methodFields.add(f);
    } else {
      propertyFields.add(f);
    }
  }

  final hasProps = propertyFields.isNotEmpty;

  // --- Class documentation and annotations
  /// Generates a documentation comment block (`///`) for the class based on the
  /// GraphQL schema description. This promotes self-documenting code.
  writeDocComments(
    buffer,
    node.description?.value,
    extra: [if (deprecReason != null) 'Deprecated: $deprecReason'],
  );

  final classDoc = docForAnnotation(
    node.description?.value,
    deprecated: deprecReason,
  );

  /// Adds a `@Deprecated` annotation to the class if a deprecation reason is present
  /// in the GraphQL schema. This correctly signals to Dart's static analysis tools
  /// that the class is obsolete.
  if (deprecReason != null) {
    buffer.writeln("@Deprecated(${dartStringLiteral(deprecReason)})");
  }

  /// Applies GraphQL-specific annotations based on the class type.
  /// This metadata is critical for GraphQL server frameworks to recognize
  /// and correctly process the generated class.
  if (isInput) {
    buffer.writeln('@GraphQLInputClass()');
  } else {
    buffer.writeln('@graphQLClass');
  }

  if (classDoc.isNotEmpty) {
    buffer.writeln(
      "@GraphQLDocumentation(description: ${dartStringLiteral(classDoc)})",
    );
  }

  /// Conditionally adds `@CopyWith` and `@JsonSerializable` annotations.
  /// This optimizes the generated code by including these annotations only when
  /// they are needed (i.e., when the class has properties that can be copied or serialized).
  if (hasProps && importerConfig.copyWith) buffer.writeln("@CopyWith()");
  if (hasProps) buffer.writeln("@JsonSerializable()");

  buffer.writeln(
    'class $className${implementsInterfaces.isNotEmpty ? ' implements ${implementsInterfaces.join(', ')}' : ''} {',
  );

  // ====== 1) PROPERTIES ======
  /// Iterates through the properties to generate `final` fields.
  for (final field in propertyFields) {
    final fieldName = field is FieldDefinitionNode
        ? field.name.value
        : (field as InputValueDefinitionNode).name.value;
    final dartName = dartFieldNameForProperty(fieldName);

    final typeInfo = getDartType(
      field is FieldDefinitionNode
          ? field.type
          : (field as InputValueDefinitionNode).type,
    );
    final fieldDeprecReason = getDeprecationReason(
      field is FieldDefinitionNode
          ? field.directives
          : (field as InputValueDefinitionNode).directives,
    );

    final extras = <String>[
      if (!typeInfo.isNullable) 'Required.' else 'Optional.',
    ];
    if (field is InputValueDefinitionNode && field.defaultValue != null) {
      extras.add('Default: ${printConstValue(field.defaultValue!)}');
    }

    /// Generates documentation and annotations for each individual field.
    writeDocComments(
      buffer,
      field is FieldDefinitionNode
          ? field.description?.value
          : (field as InputValueDefinitionNode).description?.value,
      extra: [
        if (fieldDeprecReason != null) 'Deprecated: $fieldDeprecReason',
        ...extras,
      ],
      padding: '  ',
    );
    final fieldDoc = docForAnnotation(
      field is FieldDefinitionNode
          ? field.description?.value
          : (field as InputValueDefinitionNode).description?.value,
      deprecated: fieldDeprecReason,
    );
    if (fieldDeprecReason != null) {
      buffer.writeln("  @Deprecated(${dartStringLiteral(fieldDeprecReason)})");
    }
    if (fieldDoc.isNotEmpty) {
      buffer.writeln(
        "  @GraphQLDocumentation(description: ${dartStringLiteral(fieldDoc)})",
      );
    }

    /// Adds an `@override` annotation if the field is defined in an interface
    /// implemented by this class. This is crucial for type safety and proper
    /// method overriding in Dart.
    if (overrideFieldNames.contains(dartName)) {
      buffer.writeln('  @override');
    }

    /// Uses `@JsonKey` to map the Dart field name to the original GraphQL field name
    /// if they differ. This ensures correct JSON serialization/deserialization.
    if (fieldName != dartName) {
      buffer.writeln("  @JsonKey(name: '$fieldName')");
    }
    buffer.writeln(
      '  final ${typeInfo.dartType}${typeInfo.isNullable ? '?' : ''} $dartName;',
    );
  }

  // ====== 2) RESOLVER METHODS (ObjectType only) ======
  /// Generates resolver methods for fields with arguments on GraphQL object types.
  if (isObjectType) {
    for (final field in methodFields) {
      final fieldName = field.name.value;
      final dartName = dartFieldNameForProperty(fieldName);

      final retInfo = getDartType(field.type);

      /// A resolver method returns a `Future` because GraphQL operations are asynchronous.
      /// The return type is wrapped in a `Future` to reflect this behavior.
      final returnType =
          'Future<${retInfo.dartType}${retInfo.isNullable ? '?' : ''}>';

      final fieldDeprecReason = getDeprecationReason(field.directives);
      writeDocComments(
        buffer,
        field.description?.value,
        extra: [
          if (fieldDeprecReason != null) 'Deprecated: $fieldDeprecReason',
          'Resolver method.',
        ],
        padding: '  ',
      );
      if (fieldDeprecReason != null) {
        buffer.writeln(
          "  @Deprecated(${dartStringLiteral(fieldDeprecReason)})",
        );
      }

      /// Marks the method with `@GraphQLResolver`, signaling to the framework
      /// that this method is intended to resolve a specific GraphQL field.
      buffer.writeln('  @GraphQLResolver()');

      if (overrideFieldNames.contains(dartName)) {
        buffer.writeln('  @override');
      }

      /// Generates named parameters for the method, marking non-nullable fields as `required`.
      final namedParams = <String>[];
      for (final arg in field.args) {
        final argName = dartFieldNameForProperty(arg.name.value);
        final argInfo = getDartType(arg.type);
        final argType = '${argInfo.dartType}${argInfo.isNullable ? '?' : ''}';
        final piece = argInfo.isNullable
            ? '$argType $argName'
            : 'required $argType $argName';
        namedParams.add(piece);
      }
      final paramsSig = namedParams.isEmpty
          ? ''
          : '{ ${namedParams.join(', ')} }';

      /// The method body defaults to throwing `UnimplementedError`, which
      /// forces the developer to provide an implementation. This is a common
      /// and effective pattern in code generation. It is not declared `async`:
      /// a body that only throws never awaits, and the modifier would be
      /// flagged. Whoever implements the method adds it back if they need it.
      buffer.writeln('  $returnType $dartName($paramsSig) {');
      buffer.writeln('    throw UnimplementedError();');
      buffer.writeln('  }');
      buffer.writeln();
    }
  }

  // ====== Constructor ======
  buffer.writeln();

  if (!hasProps) {
    /// An empty constructor is generated for types without properties.
    buffer.writeln('  $className();');
  } else {
    /// A named-argument constructor is generated to ensure flexibility and clarity,
    /// marking non-nullable fields as `required`.
    buffer.writeln('  $className({');
    for (final field in propertyFields) {
      final fieldName = field is FieldDefinitionNode
          ? field.name.value
          : (field as InputValueDefinitionNode).name.value;
      final dartName = dartFieldNameForProperty(fieldName);
      final isRequired = !getDartType(
        field is FieldDefinitionNode
            ? field.type
            : (field as InputValueDefinitionNode).type,
      ).isNullable;
      if (isRequired) {
        buffer.writeln('    required this.$dartName,');
      } else {
        buffer.writeln('    this.$dartName,');
      }
    }
    buffer.writeln('  })');

    /// Adds `assert` statements for custom validation directives on input types.
    /// This provides immediate feedback during development if a value is invalid.
    final asserts = <String>[];
    if (node is InputObjectTypeDefinitionNode) {
      for (final f in node.fields) {
        for (final directive in f.directives) {
          if (directive.name.value.startsWith('_')) {
            final validatorName =
                'valid${ReCase(directive.name.value.substring(1)).pascalCase}';
            asserts.add(
              '$validatorName(${dartFieldNameForProperty(f.name.value)})',
            );
          } else {
            final validatorName =
                'valid${ReCase(directive.name.value).pascalCase}';
            asserts.add(
              '$validatorName(${dartFieldNameForProperty(f.name.value)})',
            );
          }
        }
      }
    }

    if (asserts.isNotEmpty) {
      buffer.writeln(
        '      : assert(${asserts.join('),\n             assert(')});',
      );
    } else {
      buffer.writeln(';');
    }
  }

  // ====== JSON serialization methods ======
  /// Generates the `fromJson` factory and `toJson` method. This factory pattern is
  /// standard for deserialization and enables easy integration with `json_serializable`.
  if (hasProps) {
    buffer.writeln();
    buffer.writeln(
      '  factory $className.fromJson(Object? json) => _\$${className}FromJson({...?(json as Map<String, dynamic>?)});',
    );
    buffer.writeln();
    buffer.writeln(
      '  Map<String, dynamic> toJson() => _\$${className}ToJson(this);',
    );
  }

  buffer.writeln('}');
}

/// Manages the generation and writing of a Dart file for a given GraphQL type.
///
/// This function is the primary entry point for the file generation process. It
/// orchestrates all necessary steps, including file naming, import management,
/// and invoking `generateClass` to write the content.
///
/// Parameters:
/// - [outputDir]: The target directory where the file will be saved.
/// - [document]: The parsed GraphQL document containing all type definitions.
/// - [node]: The GraphQL `TypeDefinitionNode` for which the file is being generated.
void generateClassFile(
  Directory outputDir,
  DocumentNode document,
  TypeDefinitionNode node,
) {
  final className = convertName(node.name.value);
  final isObjectType = node is ObjectTypeDefinitionNode;
  final fileName = toSnakeCase(className) + (isObjectType ? '_type' : '');
  final outputFile = File(path.join(outputDir.path, '$fileName.dart'));

  // Detection of properties / resolvers
  final allFields = getFieldsForType(node);
  final needsValidators = needsValidatorsForInput(node);
  final hasProps = allFields.any((f) {
    if (node is ObjectTypeDefinitionNode && f is FieldDefinitionNode) {
      return f.args.isEmpty; // property
    }
    return true; // for Input, these are all properties
  });
  final hasResolver =
      node is ObjectTypeDefinitionNode &&
      node.fields.whereType<FieldDefinitionNode>().any(
        (f) => f.args.isNotEmpty,
      );

  /// Declares what the body needs rather than writing the directives out.
  /// [ImportBlock] renders them de-duplicated, sorted and as `package:` URIs.
  final imports = ImportBlock()
    ..add('package:graphql_schema3/graphql_schema3.dart');

  if (hasProps) {
    imports.add('package:json_annotation/json_annotation.dart');

    /// Only pulled in when the annotation is actually emitted, so a package
    /// that turns `copy_with` off does not have to depend on it.
    if (importerConfig.copyWith) {
      imports.add('package:copy_with_extension/copy_with_extension.dart');
    }
  }

  /// The resolver registry links the generated class to the GraphQL execution
  /// context, so it is only needed by a class that declares resolvers.
  if (hasResolver) {
    imports.addLibFile('$graphqlDirPath/graphql_resolvers_registry.dart');
  }

  if (needsValidators) {
    imports.addLibFile('$validatorsDirPath/validators.dart');
  }

  /// Other GraphQL types used as field types in this class.
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
        toSnakeCase(importName) + (importedIsObjectType ? '_type' : '');
    imports.addLibFile(path.join(outputDir.path, '$importFileName.dart'));
  }

  final unionInterfaces = unionsForType(document, node.name.value);
  for (final u in unionInterfaces) {
    imports.addLibFile(path.join(outputDir.path, '${toSnakeCase(u)}.dart'));
  }

  // Interface handling and @override detection
  final overrides = <String>{};
  if (node is ObjectTypeDefinitionNode && node.interfaces.isNotEmpty) {
    final ifaceNames =
        node.interfaces
            .map((i) => ReCase(i.name.value).pascalCase)
            .toSet()
            .toList()
          ..sort();
    for (final iface in ifaceNames) {
      imports.addLibFile(
        path.join(outputDir.path, '${toSnakeCase(iface)}.dart'),
      );

      /// Identifies all fields from the implemented interfaces and their extensions
      /// to correctly apply the `@override` annotation, which is a key part of
      /// robust type-safe programming in Dart.
      final ifaceDef =
          document.definitions.firstWhereOrNull(
                (d) =>
                    d is InterfaceTypeDefinitionNode && d.name.value == iface,
              )
              as InterfaceTypeDefinitionNode?;
      if (ifaceDef != null) {
        for (final f in ifaceDef.fields) {
          overrides.add(dartFieldNameForProperty(f.name.value));
        }
      }
      for (final ext
          in document.definitions.whereType<InterfaceTypeExtensionNode>().where(
            (e) => e.name.value == iface,
          )) {
        for (final f in ext.fields) {
          overrides.add(dartFieldNameForProperty(f.name.value));
        }
      }
    }
  }

  final implementsInterfaces = <String>[
    if (node is ObjectTypeDefinitionNode)
      ...node.interfaces.map((i) => ReCase(i.name.value).pascalCase),
    ...unionInterfaces,
  ];

  /// The class definition itself, assembled apart from the preamble.
  final body = StringBuffer();
  generateClass(
    body,
    node,
    implementsInterfaces: implementsInterfaces,
    overrideFieldNames: overrides,
  );

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
