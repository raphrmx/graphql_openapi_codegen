import 'dart:io';

import 'package:collection/collection.dart';
import 'package:gql/ast.dart' as gql;
import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:graphql_openapi_codegen/src/config.dart';
import 'package:graphql_openapi_codegen/src/consts.dart';
import 'package:graphql_openapi_codegen/src/dart_library.dart';
import 'package:graphql_openapi_codegen/src/generated_endpoint.dart';
import 'package:graphql_openapi_codegen/src/symbol_info.dart';
import 'package:path/path.dart' as path;
import 'package:recase/recase.dart';

export 'dart_library.dart';

/// Converts a string from PascalCase or camelCase to snake_case.
///
/// This function is a robust utility for standardizing naming conventions,
/// which is crucial in code generation and data processing. It correctly handles
/// a variety of common cases, including acronyms and consecutive uppercase letters.
///
/// The process involves two main steps:
/// 1.  Splitting the input string based on a regular expression that identifies
///     word boundaries.
/// 2.  Joining the resulting lowercase segments with underscores.
///
/// For example:
/// - "camelCase" becomes "camel_case"
/// - "PascalCase" becomes "pascal_case"
/// - "HTMLParser" becomes "html_parser"
/// - "userIDCard" becomes "user_id_card"
///
/// Parameters:
/// - [input]: The input string to be converted.
///
/// Returns:
/// - A new string in snake_case format.
String toSnakeCase(String input) {
  final r = RegExp('(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])');
  return input.split(r).map((s) => s.toLowerCase()).join('_');
}

/// Converts a GraphQL identifier to a Dart-friendly name.
String convertName(String name) {
  if (name.startsWith('_')) {
    /// The SDL marks a host type with a leading underscore, which cannot start
    /// a public Dart identifier. The prefix that replaces it belongs to
    /// whoever names the classes, so it is configuration.
    return '${importerConfig.classPrefix}${ReCase(name.substring(1)).pascalCase}';
  }
  return ReCase(name).pascalCase;
}

/// Formats a documentation string for use within a Dart annotation.
///
/// This utility is specifically designed to prepare documentation text
/// to be embedded directly as a string literal within a Dart annotation,
/// such as `@GraphQLDocumentation(description: '...')`. The primary goal
/// It only assembles the text; the literal itself is built by
/// `dartStringLiteral`, which picks the quotes and does the escaping.
///
/// Parameters:
/// - [raw]: The raw documentation string, typically sourced from a GraphQL schema. Can be null.
/// - [deprecated]: An optional string providing a deprecation reason.
///
/// Returns:
/// - The documentation text, or an empty string if no content is provided.
///   Quoting and escaping are `dartStringLiteral`'s job, not this one's.
String docForAnnotation(String? raw, {String? deprecated}) {
  final parts = <String>[];
  if (raw != null && raw.trim().isNotEmpty) {
    parts.add(raw.trim());
  }
  if (deprecated != null && deprecated.trim().isNotEmpty) {
    parts.add('Deprecated: ${deprecated.trim()}');
  }
  return parts.join('\n\n');
}

/// Retrieves the deprecation reason from a list of GraphQL directive nodes.
///
/// This utility function is designed to parse the standard GraphQL `@deprecated`
/// directive. It provides a robust way to extract the reason for deprecation,
/// which is essential for generating correct `@Deprecated` annotations in Dart code.
///
/// The function first checks for the presence of the `@deprecated` directive.
/// If found, it then attempts to find the optional `reason` argument.
///
/// Parameters:
/// - [directives]: A `List<DirectiveNode>` representing the directives attached to a GraphQL type or field.
///
/// Returns:
/// - A `String?` containing the deprecation reason. Returns `null` if the `@deprecated`
///   directive is not present.
/// - If the directive is present but the `reason` argument is missing or invalid,
///   it returns a standard, non-null default message.
String? getDeprecationReason(List<DirectiveNode> directives) {
  final dep = directives.firstWhereOrNull((d) => d.name.value == 'deprecated');
  if (dep == null) return null;
  final reasonArg = dep.arguments.firstWhereOrNull(
    (a) => a.name.value == 'reason',
  );
  if (reasonArg == null) return 'This item is deprecated.';
  final v = reasonArg.value;
  if (v is StringValueNode) return v.value;
  return 'This item is deprecated.';
}

/// Retrieves the fields or types associated with a given GraphQL type definition node.
///
/// This is a versatile utility function that acts as a single point of access for
/// extracting the component parts of different GraphQL type kinds. It abstracts
/// the specific field access logic for each node type, simplifying the code
/// in the consumer functions (e.g., in a code generator).
///
/// The function correctly handles three distinct GraphQL type nodes:
/// - `InputObjectTypeDefinitionNode`: Returns the input fields.
/// - `ObjectTypeDefinitionNode`: Returns the fields of the object type.
///
/// Parameters:
/// - [node]: The GraphQL `TypeDefinitionNode` for which to retrieve the fields.
///
/// Returns:
/// - A `List<dynamic>` containing the fields or types of the node.
/// - Returns an empty list (`[]`) if the provided node type is not supported.
List<dynamic> getFieldsForType(TypeDefinitionNode node) {
  if (node is InputObjectTypeDefinitionNode) {
    return List<dynamic>.from(node.fields);
  } else if (node is ObjectTypeDefinitionNode) {
    return List<dynamic>.from(node.fields);
  }
  return [];
}

/// Converts a GraphQL field name into a valid and idiomatic Dart property name.
///
/// This utility function applies a standard naming convention to GraphQL fields,
/// ensuring they conform to Dart's camelCase style. It also handles a specific
/// convention for private or internal fields, which is crucial for maintaining
/// a consistent and readable codebase in a generated environment.
///
/// Parameters:
/// - [graphQLFieldName]: The name of the field as defined in the GraphQL schema.
///
/// Returns:
/// - A `String` representing the formatted Dart property name.
String dartFieldNameForProperty(String graphQLFieldName) {
  if (graphQLFieldName.startsWith('_')) {
    final core = graphQLFieldName.substring(1);
    return 'bmc${ReCase(core).pascalCase}';
  }
  return ReCase(graphQLFieldName).camelCase;
}

/// Converts a GraphQL constant `ValueNode` into a valid Dart string literal.
///
/// This recursive utility is essential for code generation, allowing for the direct
/// embedding of default values from a GraphQL schema (e.g., in `@JsonSerializable`
/// or constructor initializers). It ensures that each value type is correctly
/// formatted according to Dart's syntax rules.
///
/// Parameters:
/// - [v]: The GraphQL `ValueNode` to be converted.
///
/// Returns:
/// - A `String` representing the Dart-compatible literal value.
String printConstValue(ValueNode v) {
  if (v is StringValueNode) return '"${v.value}"';
  if (v is IntValueNode) return v.value;
  if (v is FloatValueNode) return v.value;
  if (v is BooleanValueNode) return v.value ? 'true' : 'false';
  if (v is EnumValueNode) return v.name.value;
  if (v is NullValueNode) return 'null';
  if (v is ListValueNode) {
    return '[${v.values.map(printConstValue).join(', ')}]';
  }
  if (v is ObjectValueNode) {
    final pairs = v.fields.map(
      (f) => '${f.name.value}: ${printConstValue(f.value)}',
    );
    return '{${pairs.join(', ')}}';
  }
  return v.toString();
}

/// Prints a GraphQL `ValueNode` as a Dart default value literal for `@JsonKey` annotations.
///
/// This function is a type-aware utility designed to generate Dart code for default
/// values, with special handling for enums and nested lists. It correctly formats
/// values to be embedded within `@JsonKey(defaultValue: ...)` arguments, ensuring
/// the generated code is syntactically correct and type-safe.
///
/// Parameters:
/// - [v]: The GraphQL `ValueNode` representing the default value.
/// - [type]: The GraphQL `TypeNode` that describes the type of the value.
///
/// Returns:
/// - A `String` containing the Dart literal representation of the value.
String printDefaultForJsonKey(ValueNode v, TypeNode type) {
  if (type is ListTypeNode) {
    if (v is ListValueNode) {
      final itemT = type.type;
      final items = v.values
          .map((iv) => printDefaultForJsonKey(iv, itemT))
          .join(', ');
      return '[$items]';
    }
    return printConstValue(v);
  }

  final named = type as NamedTypeNode;
  final name = named.name.value;

  final doc = gql_lang.parseString(File(schemaFilePath).readAsStringSync());
  final enumDef =
      doc.definitions.firstWhereOrNull(
            (d) => d is EnumTypeDefinitionNode && d.name.value == name,
          )
          as EnumTypeDefinitionNode?;

  if (enumDef != null && v is EnumValueNode) {
    final enumDart = convertName(name);
    return '$enumDart.${v.name.value}';
  }

  // Scalars
  if (v is StringValueNode) return "'${v.value.replaceAll("'", r"\'")}'";
  if (v is IntValueNode) return v.value;
  if (v is FloatValueNode) return v.value;
  if (v is BooleanValueNode) return v.value ? 'true' : 'false';
  if (v is NullValueNode) return 'null';
  if (v is ListValueNode) return printConstValue(v);
  if (v is ObjectValueNode) return printConstValue(v);
  return printConstValue(v);
}

/// Collects all necessary import statements for a given GraphQL type definition.
///
/// This function serves as the top-level entry point for import discovery
/// for a single type. It works by iterating through the fields of the provided
/// `TypeDefinitionNode` and delegating the import collection for each field's
/// type to the `collectTypeImports` utility. This approach ensures that the
/// generated file includes all required dependencies for any other types
/// referenced within its fields.
///
/// Parameters:
/// - [document]: The full GraphQL document AST, used to resolve type names to their definitions.
/// - [node]: The `TypeDefinitionNode` (e.g., Object, Input) for which to collect imports.
///
/// Returns:
/// - A `Set<String>` of unique import names (e.g., 'User', 'ProductInput').
///   Using a `Set` guarantees that each import is listed only once,
///   preventing redundant import statements in the generated code.
Set<String> getImportsForType(DocumentNode document, TypeDefinitionNode node) {
  final imports = <String>{};
  final fields = getFieldsForType(node);
  for (final field in fields) {
    final fieldType = field is InputValueDefinitionNode
        ? field.type
        : (field as FieldDefinitionNode).type;
    collectTypeImports(
      document,
      fieldType,
      imports,
      convertName(node.name.value),
    );
    // Also import types used as field arguments (e.g. an input object passed to
    // a nested resolver field). Without this they resolve to InvalidType and
    // graphql_generator3's inferType fails.
    if (field is FieldDefinitionNode) {
      for (final arg in field.args) {
        collectTypeImports(
          document,
          arg.type,
          imports,
          convertName(node.name.value),
        );
      }
    }
  }
  return imports;
}

/// Recursively collects unique import names for a given GraphQL type node.
///
/// This is a critical utility function in a code generator, responsible for
/// traversing the potentially complex structure of a GraphQL type (e.g., lists,
/// non-null wrappers) to identify the base named types that require an import.
/// The function's recursive design ensures that it can correctly handle deeply
/// nested types like `[[User!]]!`.
///
/// Parameters:
/// - [document]: The full GraphQL Document AST, used to look up type definitions.
/// - [type]: The `TypeNode` to be analyzed for import requirements.
/// - [imports]: A `Set<String>` to which unique import names are added. Using a `Set`
///   is an efficient way to guarantee that no duplicate imports are collected.
/// - [parentName]: The name of the parent type currently being generated. This is
///   used to prevent a type from attempting to import itself.
void collectTypeImports(
  DocumentNode document,
  TypeNode type,
  Set<String> imports,
  String parentName,
) {
  if (type is ListTypeNode) {
    collectTypeImports(document, type.type, imports, parentName);
    return;
  }
  if (type is NamedTypeNode) {
    final name = type.name.value;
    if (!isScalar(name)) {
      final definition = document.definitions.firstWhereOrNull(
        (def) => def is TypeDefinitionNode && def.name.value == name,
      );
      if (definition is InputObjectTypeDefinitionNode) {
        final importName = convertName(name);
        if (importName != parentName) {
          imports.add(importName);
        }
      } else if (definition is ObjectTypeDefinitionNode) {
        final importName = convertName(name);
        if (importName != parentName) {
          imports.add(importName);
        }
      } else if (definition is EnumTypeDefinitionNode) {
        imports.add('enums');
      }
    }
  }
}

/// Checks if a given string name corresponds to a built-in GraphQL scalar type.
///
/// This utility function is essential for a code generator to differentiate
/// between standard, predefined types (which do not require custom code or imports)
/// and custom types defined in the user's schema. This distinction is fundamental
/// for generating clean and correct code.
///
/// Parameters:
/// - [name]: The name of the GraphQL type to check.
///
/// Returns:
/// - A `bool` value; `true` if the name is a recognized scalar, otherwise `false`.
bool isScalar(String name) {
  return const {
    'String',
    'Int',
    'Float',
    'Boolean',
    'ID',
    'DateTime',
    'JSON',
    'Id',
  }.contains(name);
}

String openApiTypeFromGraphQL(String gqlType) {
  switch (gqlType) {
    case 'String':
      return 'string';
    case 'Int':
      return 'integer';
    case 'Float':
      return 'number';
    case 'Boolean':
      return 'boolean';
    case 'ID':
      return 'string';
    case 'Id':
      return 'string';
    default:
      return 'object';
  }
}

/// Converts a GraphQL field name into a valid and idiomatic Dart resolver method name.
///
/// This utility function is crucial for ensuring that the generated code adheres to
/// standard Dart naming conventions for methods. It handles a specific case for
/// internal fields, providing a consistent and safe naming strategy.
///
/// Parameters:
/// - [graphQLFieldName]: The name of the field as defined in the GraphQL schema.
///
/// Returns:
/// - A `String` representing the formatted Dart resolver method name.
String dartFieldNameForResolver(String graphQLFieldName) {
  if (graphQLFieldName.startsWith('_')) {
    final core = graphQLFieldName.substring(1);
    return 'bmc${ReCase(core).pascalCase}';
  }
  return ReCase(graphQLFieldName).camelCase;
}

/// Checks if a given string corresponds to a defined GraphQL enum type.
///
/// This is a simple but crucial utility function in a code generator or schema
/// analysis tool. Its primary purpose is to quickly determine if a named type
/// is an enumeration, which often requires special handling during code generation
/// (e.g., generating a Dart `enum` class instead of a regular class).
///
/// Parameters:
/// - [doc]: The full GraphQL document Abstract Syntax Tree (AST), which contains
///   all type definitions.
/// - [name]: The name of the type to check.
///
/// Returns:
/// - `true` if a GraphQL enum definition with the matching name is found in the document,
/// - `false` otherwise.
bool isEnumName(DocumentNode doc, String name) {
  final def = doc.definitions
      .whereType<EnumTypeDefinitionNode>()
      .firstWhereOrNull((e) => e.name.value == name);
  return def != null;
}

/// Determines the appropriate Dart output type for a given GraphQL type node.
///
/// This is a core function of the code generator, responsible for translating the
/// GraphQL type system into Dart's strongly-typed system. It handles the mapping
/// of complex type structures, including scalars, lists, enums, and custom objects,
/// while correctly managing type nullability.
///
/// Parameters:
/// - [t]: The GraphQL `TypeNode` to be translated.
/// - [doc]: The full GraphQL document AST, used to look up type definitions.
///
/// Returns:
/// - A `String` representing the valid Dart type, including nullability (`?`) where necessary.
String dartOutputTypeFor(TypeNode t, DocumentNode doc) {
  /// **1. Handles Recursive List Types**
  /// The function first checks for a list type. This is the base case for recursion,
  /// allowing it to unwrap the list structure (`[String!]!`) and correctly
  /// determine the inner type before wrapping it in `List<...>`. It also correctly
  /// applies nullability to the list itself.
  if (t is ListTypeNode) {
    final inner = dartOutputTypeFor(t.type, doc);
    final listStr = 'List<$inner>';
    return t.isNonNull ? listStr : '$listStr?';
  }

  /// The type must be a `NamedTypeNode` at this point.
  final nt = t as NamedTypeNode;
  final gqlName = nt.name.value;

  /// **2. Handles Enums**
  /// If the type is an enum, the code generator makes a deliberate choice to
  /// represent it as a `String` in Dart. This is a design decision that simplifies
  /// the serialization/deserialization process. The correct nullability is applied.
  if (isEnumName(doc, gqlName)) {
    return nt.isNonNull ? 'String' : 'String?';
  }

  /// **3. Handles Scalar Types**
  /// A `switch` statement maps standard GraphQL scalars to their corresponding
  /// idiomatic Dart types. This is the most direct form of type translation.
  switch (gqlName) {
    case 'String':
      return nt.isNonNull ? 'String' : 'String?';
    case 'Int':
      return nt.isNonNull ? 'int' : 'int?';
    case 'Float':
      return nt.isNonNull ? 'double' : 'double?';
    case 'Boolean':
      return nt.isNonNull ? 'bool' : 'bool?';
    case 'ID':
      return nt.isNonNull ? 'String' : 'String?';
    case 'DateTime':
      return nt.isNonNull ? 'DateTime' : 'DateTime?';
    case 'JSON':
      return nt.isNonNull ? 'Map<String, dynamic>' : 'Map<String, dynamic>?';
  }

  /// **4. Handles Custom Types (Objects, Interfaces, Unions)**
  /// Any remaining named type is a custom one. The Dart class name comes from
  /// the naming convention alone, so the schema needs no second look here.
  final model = convertName(gqlName);
  return nt.isNonNull ? model : '$model?';
}

/// Determines the appropriate Dart return type for a GraphQL field resolver.
///
/// This function is crucial for code generation as it ensures resolver method
/// signatures are valid and reflect the asynchronous nature of GraphQL operations.
/// It distinguishes between standard queries/mutations and subscriptions,
/// which have different data delivery models.
///
/// Parameters:
/// - [t]: The GraphQL `TypeNode` of the field.
/// - [doc]: The full GraphQL document AST, used to look up type definitions.
/// - [opName]: The name of the parent GraphQL operation ('Query', 'Mutation', or 'Subscription').
///
/// Returns:
/// - A `String` representing the Dart return type, encapsulated in a `Future` or `Stream`.
String resolverReturnTypeFor(TypeNode t, DocumentNode doc, String opName) {
  final base = dartOutputTypeFor(t, doc);
  if (opName == 'Subscription') {
    return 'FutureOr<Stream<$base>>';
  }
  return 'Future<$base>';
}

/// Checks if a given GraphQL input type requires custom validation logic.
///
/// This utility function is an important part of an efficient code generation
/// workflow. By analyzing the presence of directives on an input type's fields,
/// it determines if a separate validation file needs to be generated. This
/// prevents the creation of unnecessary boilerplate code.
///
/// Parameters:
/// - [node]: The GraphQL `TypeDefinitionNode` to be checked.
///
/// Returns:
/// - `true` if the node is an input type with one or more fields containing a directive.
/// - `false` otherwise.
bool needsValidatorsForInput(TypeDefinitionNode node) {
  /// Ensures the function is operating on a valid input type node.
  /// This check acts as a guard clause, providing robustness and preventing
  /// potential runtime errors if the function is called with the wrong node type.
  if (node is! InputObjectTypeDefinitionNode) return false;

  /// Iterates through each field of the input object. The goal is to find
  /// the first field that requires validation.
  for (final f in node.fields) {
    /// **Early Exit Optimization**: If any field has directives, the function
    /// immediately returns `true`. This short-circuits the loop, making the
    /// check highly efficient as it doesn't need to process the rest of the fields.
    if (f.directives.isNotEmpty) return true;
  }

  /// If the loop completes without finding any fields with directives,
  /// it means no custom validation is needed for this input type.
  return false;
}

/// Ensures the existence of an operation-level resolver stub file.
///
/// This function is a key component of a "win-win" code generation strategy.
/// It creates a placeholder file for a GraphQL resolver (e.g., for a Query, Mutation, or Subscription field)
/// only if the file doesn't already exist. This prevents the developer's
/// custom implementation from being overwritten during subsequent code generation runs.
/// The function's name, `ensureOpResolverStub`, clearly communicates its purpose:
/// to ensure a stub exists without creating a new one if it's already there.
///
/// Parameters:
/// - [resolversDir]: The target directory for the resolver stubs.
/// - [document]: The full GraphQL document AST, used to determine necessary imports.
/// - [opName]: The name of the GraphQL operation ('Query', 'Mutation', 'Subscription').
/// - [field]: The specific GraphQL field node for which the resolver is being generated.
/// - [resolverName]: The name of the resolver function in Dart.
/// - [retType]: The Dart return type of the resolver, including `Future` or `Stream`.
void ensureOpResolverStub({
  required Directory resolversDir,
  required DocumentNode document,
  required String opName, // "Query" | "Mutation" | "Subscription"
  required FieldDefinitionNode field,
  required String resolverName,
  required String retType,
}) {
  final opLower = opName.toLowerCase();
  final fieldSnake = toSnakeCase(field.name.value);
  final file = File(
    path.join(resolversDir.path, '${opLower}_${fieldSnake}_resolver.dart'),
  );

  /// The core of the "stubbing" mechanism. If the file already exists, the function
  /// returns immediately, ensuring that the developer's work is never overwritten.
  if (file.existsSync()) return;

  final imports = <String>{"import 'dart:async';"};

  // List of scalars
  const scalarNames = {
    'String',
    'Int',
    'Float',
    'Boolean',
    'ID',
    'DateTime',
    'JSON',
    'Upload',
  };

  /// A local generator function to recursively extract named types from a TypeNode.
  /// This is essential for discovering custom types nested within lists (e.g., in a `List<User>`).
  Iterable<String> namedTypesIn(TypeNode t) sync* {
    if (t is NamedTypeNode) {
      yield t.name.value;
    } else if (t is ListTypeNode) {
      yield* namedTypesIn(t.type);
    }
  }

  /// Iterates through all the named types found in the return type.
  for (final name in namedTypesIn(field.type)) {
    /// Skips standard scalar types, as they do not require an import statement.
    if (scalarNames.contains(name)) continue;

    final sym = symbolForNamed(document, name);

    /// Adds an import statement for the corresponding model file. The path is
    /// constructed based on a helper function, assuming a known file structure.
    if (sym.importPath.isNotEmpty) {
      imports.add("import '../models/${sym.importPath}';");
    }
  }

  /// Builds the content of the resolver file using a `StringBuffer` for efficiency.
  final buf = StringBuffer()
    ..writeln(
      '// Created once by GraphQL Code-Gen. Edit freely; it will NOT be overwritten.',
    );

  /// Adds the collected import statements, sorted for consistent output.
  for (final i in (imports.toList()..sort())) {
    buf.writeln(i);
  }
  buf.writeln();

  /// Writes the function signature and a placeholder `UnimplementedError` to guide the developer.
  /// The body is built first so the signature can tell whether it awaits: a body
  /// that only throws never does, and `async` on it would be flagged.
  final body = StringBuffer();
  body.writeln("  // TODO: implement $opName.${field.name.value}");
  body.writeln('  throw UnimplementedError();');

  final asyncKeyword = awaitsSomething(body.toString()) ? ' async' : '';
  buf.writeln(
    '$retType $resolverName(Object? serialized, Map<String, dynamic> args)$asyncKeyword {',
  );
  buf.write(body.toString());
  buf.writeln('}');

  /// Ensures the directory structure exists before writing the file.
  file.createSync(recursive: true);

  /// Writes the content to the new resolver file.
  file.writeAsStringSync(buf.toString());
}

/// Finds all GraphQL union types that contain a given type.
///
/// This utility function is crucial for GraphQL code generation, particularly
/// for handling polymorphism. When generating code for a specific type (e.g., `Device`),
/// this function helps identify which union types it belongs to (e.g., `SearchResult`),
/// which is essential for correct serialization and deserialization logic.
///
/// Parameters:
/// - [document]: The full GraphQL document Abstract Syntax Tree (AST).
/// - [gqlTypeName]: The GraphQL name of the type to search for (e.g., 'Device').
///
/// Returns:
/// - A `List<String>` of Dart names for the union types that contain the given type.
List<String> unionsForType(DocumentNode document, String gqlTypeName) {
  final unions = <String>[];

  /// Iterates through all `UnionTypeDefinitionNode`s in the GraphQL document.
  for (final def in document.definitions.whereType<UnionTypeDefinitionNode>()) {
    /// Checks if the current union type's list of possible types contains the target type.
    final contains = def.types.any((t) => t.name.value == gqlTypeName);
    if (contains) {
      /// If the union contains the type, its converted Dart name is added to the list.
      /// The `convertName` function (assumed to be a helper) translates the
      /// GraphQL name (e.g., 'TestUnion') into a valid Dart class name.
      unions.add(convertName(def.name.value)); // e.g. TestUnion
    }
  }

  return unions;
}

bool isListType(gql.TypeNode type) => type is gql.ListTypeNode;

String getBaseTypeName(gql.TypeNode type) {
  var current = type;
  while (current is gql.ListTypeNode) {
    current = current.type;
  }
  return current is gql.NamedTypeNode ? current.name.value : '';
}

/// Only the top level matters for "required": a nullable list of non-null
/// items is still an optional argument.
bool isNonNullTop(gql.TypeNode t) => t.isNonNull;

gql.ObjectTypeDefinitionNode? findObjectTypeDef(
  gql.DocumentNode document,
  String typeName,
) {
  return document.definitions
      .whereType<gql.ObjectTypeDefinitionNode>()
      .firstWhereOrNull((d) => d.name.value == typeName);
}

void writeTypeSchemaForYaml(
  StringBuffer b,
  gql.TypeNode type, {
  String indent = '',
  bool wrapAllOfIfRef = false,
}) {
  final base = getBaseTypeName(type);
  final isList = isListType(type);
  final isScalarType = isScalar(base);
  final isRequired = isNonNullTop(type);

  if (isList) {
    b.writeln('${indent}type: array');
    if (!isRequired) b.writeln('${indent}nullable: true');
    b.writeln('${indent}items:');
    if (isScalarType) {
      b.writeln('$indent  type: ${openApiTypeFromGraphQL(base)}');
    } else {
      b.writeln('$indent  \$ref: "#/components/schemas/$base"');
    }
  } else {
    if (isScalarType) {
      b.writeln('${indent}type: ${openApiTypeFromGraphQL(base)}');
      if (!isRequired) b.writeln('${indent}nullable: true');
    } else {
      if (wrapAllOfIfRef) {
        b.writeln('${indent}allOf:');
        b.writeln('$indent  - \$ref: "#/components/schemas/$base"');
      } else {
        b.writeln('$indent\$ref: "#/components/schemas/$base"');
      }
      if (!isRequired) b.writeln('${indent}nullable: true');
    }
  }
}

String normalizeImportPath(String filePath, String from) {
  return path.relative(filePath, from: from).replaceAll(r'\', '/');
}

String rootCompositeSchemaNameFor(GeneratedEndpoint e) {
  final op = e.routePath.startsWith('/mutation/') ? 'Mutation' : 'Query';
  final raw = e.field?.name.value ?? e.routePath.split('/').last;
  final fieldPascal = ReCase(raw).pascalCase;
  return '$op${fieldPascal}Input';
}

/// Emits a nested input schema for `field` and its sub-resolvers.
/// - `prefix` = "Query" or "Mutation"
/// - `parentChain` builds the hierarchical name (e.g. "Query_company")
void emitCompositeInputSchema(
  StringBuffer b,
  gql.DocumentNode document,
  gql.FieldDefinitionNode field, {
  required String prefix,
  String? parentChain,
  required Set<String> emitted,
}) {
  final currentChain = (parentChain == null)
      ? '${ReCase(prefix).pascalCase}${ReCase(field.name.value).pascalCase}'
      : '$parentChain${ReCase(field.name.value).pascalCase}';
  final schemaName = '${currentChain}Input';

  if (!emitted.add(schemaName)) return;

  b.writeln('    $schemaName:');
  b.writeln('      type: object');

  final requiredArgs = <String>[];
  for (final a in field.args) {
    if (isNonNullTop(a.type)) requiredArgs.add(a.name.value);
  }
  if (requiredArgs.isNotEmpty) {
    b.writeln('      required:');
    for (final r in requiredArgs) {
      b.writeln('        - $r');
    }
  }

  b.writeln('      properties:');

  for (final arg in field.args) {
    final name = arg.name.value;
    final desc = arg.description?.value.replaceAll('"', '\\"');
    final depr = arg.directives.any((d) => d.name.value == 'deprecated');

    b.writeln('        $name:');
    if (desc != null && desc.isNotEmpty) {
      b.writeln('          description: "$desc"');
    }
    if (depr) b.writeln('          deprecated: true');

    final base = getBaseTypeName(arg.type);
    final needsAllOf = !isScalar(base) && !isListType(arg.type);
    writeTypeSchemaForYaml(
      b,
      arg.type,
      indent: '          ',
      wrapAllOfIfRef: needsAllOf,
    );
  }

  final baseReturn = getBaseTypeName(field.type);
  final retObjDef = document.definitions
      .whereType<gql.ObjectTypeDefinitionNode>()
      .firstWhereOrNull((d) => d.name.value == baseReturn);

  if (retObjDef == null) {
    return;
  }

  for (final sub in retObjDef.fields) {
    if (sub.args.isEmpty) continue;

    final childSchemaName =
        '$currentChain${ReCase(sub.name.value).pascalCase}Input';

    b.writeln('        ${sub.name.value}:');
    b.writeln('          \$ref: "#/components/schemas/$childSchemaName"');

    emitCompositeInputSchema(
      b,
      document,
      sub,
      prefix: prefix,
      parentChain: currentChain,
      emitted: emitted,
    );
  }
}

String resolverFnFor(String parentGqlTypeName, String fieldName) {
  // e.g. parentGqlTypeName = "_Company" -> convertName = "BmcCompany"
  // => "bmcCompany" + "Establishments" + "Resolver"
  final parentDart = convertName(parentGqlTypeName); // BmcCompany
  final parentCamel = ReCase(parentDart).camelCase; // bmcCompany
  final fieldPascal = ReCase(fieldName).pascalCase; // Establishments
  return '$parentCamel${fieldPascal}Resolver'; // bmcCompanyEstablishmentsResolver
}

void emitNestedPopulation(
  StringBuffer b,
  gql.DocumentNode document, {
  required String parentGqlType,
  required String argsAccessor,
  required String parentSerVar,
  required String parentJsonVar,
  required int depth,
  required Set<String> resolverImports,
  bool isRoot = true,
}) {
  final indent = '  ' * depth;

  final parentDef = findObjectTypeDef(document, parentGqlType);
  if (parentDef == null) return;

  for (final field in parentDef.fields) {
    if (field.args.isEmpty) continue;

    final name = field.name.value;
    final childBase = getBaseTypeName(field.type);
    final isListRet = isListType(field.type);
    final isScalarRet = isScalar(childBase);

    final resolverFn = subResolverFnName(parentGqlType, name);
    final resolverImp = subResolverImportPath(parentGqlType, name);
    resolverImports.add(resolverImp);

    // Generate a unique args name based on the field
    final argVar = '${name}Args';

    // --- Cas MAP ---
    b.writeln("${indent}if ($argsAccessor['$name'] is Map<String, dynamic>) {");
    b.writeln(
      "$indent  final $argVar = $argsAccessor['$name']! as Map<String, dynamic>;",
    );
    b.writeln(
      '$indent  final res = await $resolverFn($parentSerVar, $argVar);',
    );

    if (isListRet) {
      if (isScalarRet) {
        b.writeln(
          "$indent  $parentJsonVar['$name'] = (res ?? []) as List<dynamic>;",
        );
      } else {
        b.writeln(
          "$indent  $parentJsonVar['$name'] = await Future.wait((res ?? []).map((it) async {",
        );
        b.writeln('$indent    final itemJson = it.toJson();');
        final childObjDef = findObjectTypeDef(document, childBase);
        if (childObjDef != null) {
          emitNestedPopulation(
            b,
            document,
            parentGqlType: childBase,
            argsAccessor: argVar,
            parentSerVar: 'it',
            parentJsonVar: 'itemJson',
            depth: depth + 2,
            resolverImports: resolverImports,
            isRoot: false,
          );
        }
        b.writeln('$indent    return itemJson;');
        b.writeln('$indent  }));');
      }
    }

    b.writeln('$indent}');
  }
}

String resolverNameFor(String parentType, String fieldName) {
  final parent = ReCase(parentType).pascalCase; // e.g. Company -> Company
  final field = ReCase(
    fieldName,
  ).pascalCase; // e.g. establishments -> Establishments
  return 'bmc$parent${field}Resolver'; // bmcCompanyEstablishmentsResolver
}

String resolverImportPath(String endpointDir, String resolverFileName) {
  final resolverFilePath = path.join(
    endpointDir,
    '../resolvers',
    resolverFileName,
  );
  return normalizeImportPath(resolverFilePath, endpointDir);
}

void collectNestedResolversImports(
  Set<String> imports,
  String endpointDir,
  DocumentNode document,
  FieldDefinitionNode field, {
  required String parentType,
}) {
  final baseType = getBaseTypeName(field.type);
  final typeDef = findObjectTypeDef(document, baseType);
  if (typeDef == null) return;

  for (final sub in typeDef.fields) {
    if (sub.args.isNotEmpty) {
      final resolverName =
          '${dartFieldNameForResolver(parentType)}${convertName(sub.name.value)}Resolver';
      final fileName = '${ReCase(resolverName).snakeCase}.dart';
      imports.add(resolverImportPath(endpointDir, fileName));

      // recursive if there are still sub-fields
      collectNestedResolversImports(
        imports,
        endpointDir,
        document,
        sub,
        parentType: convertName(baseType),
      );
    }
  }
}

String subResolverFnName(String parentGqlType, String fieldName) {
  // e.g. _Company + establishments -> bmcCompanyEstablishmentsResolver
  final parentDart = convertName(parentGqlType); // BmcCompany
  return '${ReCase(parentDart).camelCase}${ReCase(fieldName).pascalCase}Resolver';
}

String subResolverImportPath(String parentGqlType, String fieldName) {
  // e.g. _Company + establishments -> ../../resolvers/bmc_company_establishments_resolver.dart
  final parentDart = convertName(parentGqlType); // BmcCompany
  final parentSnake = ReCase(parentDart).snakeCase; // bmc_company
  final fieldSnake = ReCase(fieldName).snakeCase; // establishments
  return '../../resolvers/${parentSnake}_${fieldSnake}_resolver.dart';
}

/// The version the generated OpenAPI document carries.
///
/// A package that is never published may declare no version at all, so this
/// falls back rather than aborting the whole generation.
String readPubspecVersion() => importerConfig.packageVersion;

Set<String> collectUsedTypes(
  gql.DocumentNode document,
  List<GeneratedEndpoint> queryFiles,
  List<GeneratedEndpoint> mutationFiles,
  List<GeneratedEndpoint> subscriptionFiles,
) {
  final used = <String>{};

  void exploreType(gql.TypeNode type) {
    final base = getBaseTypeName(type);
    if (isScalar(base)) return;
    if (!used.add(base)) return; // already visited

    // Find the matching definition
    final def = document.definitions.firstWhereOrNull(
      (d) => d is gql.TypeDefinitionNode && d.name.value == base,
    );

    if (def == null) return;

    if (def is gql.ObjectTypeDefinitionNode) {
      for (final f in def.fields) {
        exploreType(f.type);
        for (final arg in f.args) {
          exploreType(arg.type);
        }
      }
    } else if (def is gql.InputObjectTypeDefinitionNode) {
      for (final f in def.fields) {
        exploreType(f.type);
      }
    } else if (def is gql.EnumTypeDefinitionNode) {
      // nothing to explore
    }
  }

  for (final e in [...queryFiles, ...mutationFiles, ...subscriptionFiles]) {
    final field = e.field;
    if (field != null) {
      // explore args
      for (final arg in field.args) {
        exploreType(arg.type);
      }
      // explore return
      exploreType(field.type);
    }
  }

  return used;
}
