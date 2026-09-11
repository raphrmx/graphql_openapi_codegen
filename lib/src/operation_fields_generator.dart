import 'dart:io';

import 'package:gql/ast.dart';
import 'package:graphql_openapi_codegen/src/graphql_type_ref.dart';
import 'package:graphql_openapi_codegen/src/helpers.dart';
import 'package:graphql_openapi_codegen/src/symbol_info.dart';
import 'package:path/path.dart' as path;

void generateOperationFieldsFile(
  Directory outputDir,
  DocumentNode document,
  ObjectTypeDefinitionNode node, // Query / Mutation / Subscription
  String opName, // "Query" | "Mutation" | "Subscription"
) {
  final neededImports = <String>{}; // file names under the models directory
  final resolverImports =
      <String>{}; // file names under the resolvers directory
  final resolversDir = Directory(
    path.join(outputDir.parent.parent.path, 'resolvers'),
  );
  final modelsDir = Directory(
    path.join(outputDir.parent.parent.path, 'models'),
  );
  if (!resolversDir.existsSync()) resolversDir.createSync(recursive: true);

  final fileName = '${opName.toLowerCase()}_fields.dart';
  final out = File(path.join(outputDir.path, fileName));
  final b = StringBuffer();

  final imports = ImportBlock()
    ..add('package:graphql_schema3/graphql_schema3.dart');

  // --- util: GraphQL type reference + collect neededImports
  GraphQLTypeRef graphQLRef(TypeNode t) {
    if (t is ListTypeNode) {
      final inner = graphQLRef(t.type);
      return GraphQLTypeRef.list(inner, t.isNonNull);
    }
    final nt = t as NamedTypeNode;
    switch (nt.name.value) {
      case 'String':
        return GraphQLTypeRef.scalar('graphQLString', nt.isNonNull);
      case 'Int':
        return GraphQLTypeRef.scalar('graphQLInt', nt.isNonNull);
      case 'Float':
        return GraphQLTypeRef.scalar('graphQLFloat', nt.isNonNull);
      case 'Boolean':
        return GraphQLTypeRef.scalar('graphQLBoolean', nt.isNonNull);
      case 'ID':
        return GraphQLTypeRef.scalar('graphQLId', nt.isNonNull);
      case 'DateTime':
        return GraphQLTypeRef.scalar('graphQLDate', nt.isNonNull);
      case 'JSON':
        return GraphQLTypeRef.scalar('graphQLJson', nt.isNonNull);
      default:
        final sym = symbolForNamed(document, nt.name.value);
        if (sym.importPath.isNotEmpty) {
          neededImports.add(sym.importPath);
        }
        return GraphQLTypeRef.custom(sym.ident, nt.isNonNull);
    }
  }

  // --- PRE-PASS: build fields, collect imports, create stubs
  final built = <Map<String, dynamic>>[];
  for (final f in node.fields) {
    final resolverName = '${dartFieldNameForResolver(f.name.value)}Resolver';
    final fieldSnake = toSnakeCase(f.name.value);
    final opLower = opName.toLowerCase();
    resolverImports.add('${opLower}_${fieldSnake}_resolver.dart');

    // Ensure the stub (uses ensureOpResolverStub with scalar filtering)
    final retType = resolverReturnTypeFor(f.type, document, opName);
    ensureOpResolverStub(
      resolversDir: resolversDir,
      document: document,
      opName: opName,
      field: f,
      resolverName: resolverName,
      retType: retType,
    );

    // Collect model imports via graphQLRef on return + args
    final returnRef = graphQLRef(f.type);
    final inputsExpr = <String>[];
    for (final arg in f.args) {
      final argRef = graphQLRef(arg.type);
      final sb = StringBuffer(
        "GraphQLFieldInput('${arg.name.value}', ${argRef.dartExpr}",
      );
      if (arg.defaultValue != null) {
        final dv = printDefaultForJsonKey(arg.defaultValue!, arg.type).trim();

        /// The SDL spells optional arguments `x: T = null`, so the node exists
        /// even when the value is nothing. Rendered, that is Dart's own default
        /// for the parameter, and passing it back is what
        /// `avoid_redundant_argument_values` reports.
        if (dv != 'null') sb.write(', defaultValue: $dv');
      }
      sb.write(')');
      inputsExpr.add(sb.toString());
    }

    final desc = f.description?.value ?? '';
    built.add({
      'name': f.name.value,
      'returnRefExpr': returnRef.dartExpr,
      'inputsExpr': inputsExpr,
      'desc': desc,
      'resolverName': resolverName,
    });
  }

  // --- IMPORTS: collected during the pre-pass, rendered by [ImportBlock]
  for (final imp in resolverImports) {
    imports.addLibFile(path.join(resolversDir.path, imp));
  }
  for (final imp in neededImports) {
    imports.addLibFile(path.join(modelsDir.path, imp));
  }

  // --- Write the fields
  final listName = '${opName.toLowerCase()}Fields';
  b.writeln(
    'final Iterable<GraphQLObjectField<dynamic, dynamic>> $listName = [',
  );

  for (final it in built) {
    final fieldName = it['name'] as String;
    final returnRefExpr = it['returnRefExpr'] as String;
    final inputsExpr = it['inputsExpr'] as List<String>;
    final desc = it['desc'] as String;
    final resolverName = it['resolverName'] as String;

    b.writeln('  field(');
    b.writeln("    '$fieldName',");
    b.writeln('    $returnRefExpr,');
    if (desc.isNotEmpty) {
      b.writeln('    description: ${dartStringLiteral(desc)},');
    }
    if (inputsExpr.isNotEmpty) {
      b.writeln('    inputs: [');
      for (final i in inputsExpr) {
        b.writeln('      $i,');
      }
      b.writeln('    ],');
    }
    b.writeln('    resolve: $resolverName,');
    b.writeln('  ),');
  }

  b.writeln('];');

  /// `dart:async` is only pulled in when the rendered fields actually mention a
  /// future; the file used to import it unconditionally and never use it.
  if (b.toString().contains('Future')) imports.add('dart:async');

  writeGeneratedLibrary(
    out,
    description: 'Auto generated $opName fields. Do not edit.',
    extra: ['Generated from GraphQL $opName.'],
    imports: imports,
    body: b.toString(),
  );
}
