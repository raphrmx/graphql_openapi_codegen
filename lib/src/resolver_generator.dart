import 'dart:io';

import 'package:gql/ast.dart';
import 'package:graphql_openapi_codegen/src/consts.dart';
import 'package:graphql_openapi_codegen/src/helpers.dart';
import 'package:graphql_openapi_codegen/src/type_info.dart';
import 'package:path/path.dart' as p;
import 'package:path/path.dart' as path;
import 'package:recase/recase.dart';

const _scalarNames = <String>{
  'String',
  'Int',
  'Float',
  'Boolean',
  'ID',
  'DateTime',
  'JSON',
};

bool _isScalarName(String name) => _scalarNames.contains(name);

bool _isOperation(String name) =>
    name == 'Query' || name == 'Mutation' || name == 'Subscription';

/// All NamedTypeNodes contained in a TypeNode (unwraps lists)
Iterable<String> _namedTypeNames(TypeNode t) sync* {
  if (t is NamedTypeNode) {
    yield t.name.value;
  } else if (t is ListTypeNode) {
    yield* _namedTypeNames(t.type);
  }
}

TypeDefinitionNode? _findTypeDef(DocumentNode doc, String gqlName) {
  for (final d in doc.definitions) {
    if (d is TypeDefinitionNode && d.name.value == gqlName) return d;
  }
  return null;
}

/// Computes the relative import path (from lib/graphql/resolvers/)
/// for a GraphQL NamedType (Object/Input/Interface/Union/Enum).
String? _importPathForNamed(DocumentNode doc, String gqlName) {
  if (_isScalarName(gqlName)) return null;
  final def = _findTypeDef(doc, gqlName);
  if (def == null) return null;

  final dartName = convertName(def.name.value);
  final snake = ReCase(dartName).snakeCase;

  if (def is ObjectTypeDefinitionNode) {
    return "../models/${snake}_type.dart";
  } else if (def is InputObjectTypeDefinitionNode) {
    return "../models/$snake.dart";
  } else if (def is InterfaceTypeDefinitionNode) {
    return "../models/$snake.dart";
  } else if (def is UnionTypeDefinitionNode) {
    return "../models/$snake.dart";
  } else if (def is EnumTypeDefinitionNode) {
    return "../models/enums.dart";
  }
  return null;
}

class _ArgSpec {
  final String name;
  final String dartTypeWithNull;
  // also keep the GraphQL named types for imports
  final List<String> referencedGqlNames;
  _ArgSpec(this.name, this.dartTypeWithNull, this.referencedGqlNames);
}

class _ResolverSpec {
  final String typeGql; // e.g. _Company
  final String typeDart; // e.g. BmcCompany
  final String field; // e.g. establishments
  final String retDart; // e.g. List<BmcEstablishment>?
  final List<String> retNamedGql; // e.g. ['_Establishment']
  final List<_ArgSpec> args;
  _ResolverSpec({
    required this.typeGql,
    required this.typeDart,
    required this.field,
    required this.retDart,
    required this.retNamedGql,
    required this.args,
  });
}

List<_ResolverSpec> _collectResolvers(
  DocumentNode doc, {
  bool includeOperations = true,
}) {
  final out = <_ResolverSpec>[];
  for (final def in doc.definitions.whereType<ObjectTypeDefinitionNode>()) {
    if (!includeOperations && _isOperation(def.name.value)) continue;

    final typeGql = def.name.value;
    final typeDart = convertName(typeGql);

    for (final f in def.fields.where((f) => f.args.isNotEmpty)) {
      final retInfo = getDartType(f.type);
      final retDart = '${retInfo.dartType}${retInfo.isNullable ? '?' : ''}';
      final retNamed = _namedTypeNames(f.type).toList();

      final args = <_ArgSpec>[];
      for (final a in f.args) {
        final at = getDartType(a.type);
        final atDart = '${at.dartType}${at.isNullable ? '?' : ''}';
        final argNamed = _namedTypeNames(a.type).toList();
        args.add(_ArgSpec(a.name.value, atDart, argNamed));
      }

      out.add(
        _ResolverSpec(
          typeGql: typeGql,
          typeDart: typeDart,
          field: f.name.value,
          retDart: retDart,
          retNamedGql: retNamed,
          args: args,
        ),
      );
    }
  }
  return out;
}

void _writeResolverStub(String rootDir, DocumentNode doc, _ResolverSpec spec) {
  final typeSnake = ReCase(spec.typeDart).snakeCase;
  final fieldSnake = ReCase(spec.field).snakeCase;
  final file = File(
    p.join(
      rootDir,
      resolversDirPath,
      '${typeSnake}_${fieldSnake}_resolver.dart',
    ),
  );
  if (file.existsSync()) return; // do not overwrite

  final fnName =
      '${ReCase(spec.typeDart).camelCase}${ReCase(spec.field).pascalCase}Resolver';

  // === IMPORTS ===
  /// [ImportBlock] holds URIs, not whole directives: the paths that
  /// `_importPathForNamed` returns are relative to this resolver's directory
  /// and get resolved into `package:` URIs here.
  final imports = ImportBlock()..add('dart:async');

  // Parent type (always ObjectType here)
  imports.addRelative(resolversDirPath, '../models/${typeSnake}_type.dart');

  // Return: all named types encountered
  for (final gqlName in spec.retNamedGql) {
    final imp = _importPathForNamed(doc, gqlName);
    if (imp != null) imports.addRelative(resolversDirPath, imp);
  }

  // Args: all named types encountered
  for (final a in spec.args) {
    for (final gqlName in a.referencedGqlNames) {
      final imp = _importPathForNamed(doc, gqlName);
      if (imp != null) imports.addRelative(resolversDirPath, imp);
    }
  }

  final buf = StringBuffer();

  buf.writeln(
    "// Created once by GraphQL Code-Gen. Edit freely; it will NOT be overwritten.",
  );
  buf.write(imports.render());
  buf.writeln();

  // === FUNCTION ===
  /// The body is assembled first so the signature can tell whether it actually
  /// awaits. Emitting `async` on a body that only forwards a future is what
  /// `unnecessary_async` and `async_return_with_no_await` both complain about.
  final body = StringBuffer();
  body.writeln('  final o = serialized! as ${spec.typeDart};');

  if (spec.args.isEmpty) {
    body.writeln('  return o.${spec.field}();');
  } else {
    // We prefer NAMED parameters for readability
    body.writeln('  return o.${spec.field}(');
    for (final a in spec.args) {
      body.writeln(
        "    ${a.name}: args['${a.name}'] as ${a.dartTypeWithNull},",
      );
    }
    body.writeln('  );');
  }

  final asyncKeyword = awaitsSomething(body.toString()) ? ' async' : '';
  buf.writeln(
    'FutureOr<${spec.retDart}> $fnName(Object? serialized, Map<String, dynamic> args)$asyncKeyword {',
  );
  buf.write(body.toString());
  buf.writeln('}');

  file.createSync(recursive: true);
  file.writeAsStringSync(buf.toString());
}

void _writeRegisterAll(String rootDir, List<_ResolverSpec> specs) {
  final dir = Directory(p.join(rootDir, resolversDirPath));
  dir.createSync(recursive: true);

  final out = File(p.join(dir.path, 'register_all.dart'));
  final buf = StringBuffer();

  buf.writeln('// Auto-generated. Overwritten on each run.');

  /// The registry is only needed when there is something to register in it.
  final imports = ImportBlock();
  if (specs.isNotEmpty) {
    imports.addLibFile('$graphqlDirPath/graphql_resolvers_registry.dart');
  }
  for (final s in specs) {
    final typeSnake = ReCase(s.typeDart).snakeCase;
    final fieldSnake = ReCase(s.field).snakeCase;
    imports.addLibFile(
      p.join(resolversDirPath, '${typeSnake}_${fieldSnake}_resolver.dart'),
    );
  }
  buf.write(imports.render());
  buf.writeln();
  buf.writeln('void registerAllResolvers() {');
  final lines = <String>{};
  for (final s in specs) {
    final key = '${s.typeDart}.${s.field}';
    final fnName =
        '${ReCase(s.typeDart).camelCase}${ReCase(s.field).pascalCase}Resolver';
    lines.add("  resolverRegistry['$key'] = $fnName;");
  }
  for (final l in (lines.toList()..sort())) {
    buf.writeln(l);
  }
  buf.writeln('}');

  out.writeAsStringSync(buf.toString());
}

int generateResolversFromDocument({
  required String rootDir,
  required DocumentNode document,
  bool includeOperations = true,
}) {
  final specs = _collectResolvers(
    document,
    includeOperations: includeOperations,
  );
  for (final s in specs) {
    _writeResolverStub(rootDir, document, s);
  }
  _writeRegisterAll(rootDir, specs);
  return specs.length;
}

void ensureResolverRegistryFile(Directory outputDir) {
  final registryFile = File(
    path.join(outputDir.path, 'graphql_resolvers_registry.dart'),
  );

  if (registryFile.existsSync()) return;

  const content = '''
// Created once by GraphQL Code-Gen. Edit freely; it will NOT be overwritten.

import 'dart:async';

typedef GraphQLFieldResolverFn = FutureOr<dynamic> Function(
  Object? serialized,
  Map<String, dynamic> argumentValues,
);

final Map<String, GraphQLFieldResolverFn> resolverRegistry = <String, GraphQLFieldResolverFn>{};

/// Convenience helper (optional)
void registerResolver(String key, GraphQLFieldResolverFn fn) {
  resolverRegistry[key] = fn;
}
''';

  writeCreatedOnceFile(registryFile, content);
}

void writeSubscriptionResolverStub(
  String rootDir,
  DocumentNode doc,
  FieldDefinitionNode field,
) {
  final fieldName = field.name.value; // e.g. newMessage
  final fileName = 'subscription_${toSnakeCase(fieldName)}_resolver.dart';
  final file = File(p.join(rootDir, resolversDirPath, fileName));
  if (file.existsSync()) return; // do not overwrite

  final retInfo = getDartType(field.type);
  final retDart = '${retInfo.dartType}${retInfo.isNullable ? '?' : ''}';

  final buf = StringBuffer();

  buf.writeln(
    "// Created once by GraphQL/REST Code-Gen. Edit freely; it will NOT be overwritten.",
  );
  final imports = ImportBlock()..add('dart:async');

  // import the return type if it is not a scalar
  for (final gqlName in _namedTypeNames(field.type)) {
    final imp = _importPathForNamed(doc, gqlName);
    if (imp != null) imports.addRelative(resolversDirPath, imp);
  }
  buf.write(imports.render());
  buf.writeln();

  buf.writeln("/// Resolver for Subscription.$fieldName");
  buf.writeln(
    "Stream<$retDart> ${fieldName}Resolver(Object? _, Map<String, dynamic> args) {",
  );
  buf.writeln("  // TODO: implement subscription logic");
  buf.writeln(
    "  throw UnimplementedError('${fieldName}Resolver is not implemented');",
  );
  buf.writeln("}");

  file.createSync(recursive: true);
  file.writeAsStringSync(buf.toString());
}

void generateNestedResolver(
  StringBuffer b,
  DocumentNode document,
  FieldDefinitionNode field,
  String parentTypeDart, // e.g. "BmcCompany"
  String parentVar, // e.g. "result" or "item"
  int depth,
) {
  final indent = '  ' * depth;
  final fieldName = field.name.value;
  final baseType = getBaseTypeName(field.type);
  final isPrimitive = isScalar(baseType);

  // 🔹 Full resolver name
  final resolverName =
      '${ReCase(parentTypeDart).camelCase}${ReCase(fieldName).pascalCase}Resolver';

  // If the field has args, generate REST logic
  if (field.args.isNotEmpty) {
    // List case
    b.writeln("${indent}if (jsonBody['$fieldName'] is List) {");
    b.writeln("$indent  final ${fieldName}List = <dynamic>[];");
    b.writeln(
      "$indent  for (dynamic subArgs in jsonBody['$fieldName'] as List) {",
    );
    b.writeln("$indent    if (subArgs is! Map<String, dynamic>) continue;");
    b.writeln(
      "$indent    final items = await $resolverName($parentVar, subArgs);",
    );

    b.writeln("$indent    for (final item in items ?? []) {");
    if (isPrimitive) {
      b.writeln("$indent      ${fieldName}List.add(item);");
    } else {
      b.writeln("$indent      final itemJson = item.toJson();");

      // recursive if complex type
      final typeDef = findObjectTypeDef(document, baseType);
      if (typeDef != null) {
        for (final subField in typeDef.fields) {
          generateNestedResolver(
            b,
            document,
            subField,
            convertName(baseType), // child type
            "item",
            depth + 3,
          );
        }
      }
      b.writeln("$indent      ${fieldName}List.add(itemJson);");
    }
    b.writeln("$indent    }");
    b.writeln("$indent  }");
    b.writeln("$indent  ${parentVar}Json['$fieldName'] = ${fieldName}List;");
    b.writeln("$indent}");

    // Map case (e.g. bookingDatesData)
    b.writeln(
      "${indent}else if (jsonBody['$fieldName'] is Map<String, dynamic>) {",
    );
    b.writeln(
      "$indent  final subArgs = jsonBody['$fieldName'] as Map<String, dynamic>;",
    );
    b.writeln(
      "$indent  final items = await $resolverName($parentVar, subArgs);",
    );
    if (isPrimitive) {
      b.writeln("$indent  ${parentVar}Json['$fieldName'] = items;");
    } else {
      b.writeln(
        "$indent  ${parentVar}Json['$fieldName'] = items?.map((e) => e.toJson()).toList() ?? [];",
      );
    }
    b.writeln("$indent}");
  }
}
