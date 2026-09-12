import 'dart:io';

import 'package:graphql_openapi_codegen/src/build_yaml_generator.dart';
import 'package:graphql_openapi_codegen/src/config.dart';
import 'package:graphql_openapi_codegen/src/dart_library.dart';
import 'package:graphql_openapi_codegen/src/validator_generator.dart';
import 'package:test/test.dart';

/// Writes [pubspec] to a throwaway file and loads the configuration from it.
ImporterConfig loadFrom(String pubspec) {
  final dir = Directory.systemTemp.createTempSync('goc_test');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = File('${dir.path}/pubspec.yaml')..writeAsStringSync(pubspec);
  return ImporterConfig.load(file.path);
}

void main() {
  group('configuration', () {
    test('falls back to a plain layout when the section is absent', () {
      final config = loadFrom('name: acme\n');

      expect(config.packageName, 'acme');
      expect(config.schemaPath, 'lib/schema.graphql');
      expect(config.modelsDir, 'lib/models');
      expect(config.classPrefix, isEmpty);
      expect(config.copyWith, isTrue);
      expect(config.restPrefix, isEmpty);
    });

    test('reads the version, and stands in for a package that has none', () {
      expect(loadFrom('name: acme\nversion: 2.1.0\n').packageVersion, '2.1.0');
      expect(loadFrom('name: acme\n').packageVersion, '0.0.0');
    });

    test('reads every declared entry', () {
      final config = loadFrom('''
name: acme
graphql_openapi_codegen:
  schema: lib/v1/schema.graphql
  class_prefix: Bmc
  copy_with: false
  api_name: Acme Shop
  api_servers:
    - https://one.example
    - https://two.example
  routes:
    graphql: /api/graphql
    rest: /rest
    graphql_doc: /docs/playground
    rest_doc: /docs/swagger
    openapi: /static/openapi.yaml
  output:
    models: lib/v1/models
    routes: lib/v1/routes
''');

      expect(config.schemaPath, 'lib/v1/schema.graphql');
      expect(config.classPrefix, 'Bmc');
      expect(config.copyWith, isFalse);
      expect(config.apiName, 'Acme Shop');
      expect(config.apiServers, ['https://one.example', 'https://two.example']);
      expect(config.graphqlPath, '/api/graphql');
      expect(config.restPrefix, '/rest');
      expect(config.graphqlDocPath, '/docs/playground');
      expect(config.restDocPath, '/docs/swagger');
      expect(config.openApiUrl, '/static/openapi.yaml');
      expect(config.modelsDir, 'lib/v1/models');
      expect(config.routesDir, 'lib/v1/routes');
      // Not declared, so still the fallback.
      expect(config.validatorsDir, 'lib/validators');
    });

    test('an empty documentation path turns the page off', () {
      final config = loadFrom('''
name: acme
graphql_openapi_codegen:
  routes:
    graphql_doc: ''
    rest_doc: ''
''');

      expect(config.graphqlDocPath, isEmpty);
      expect(config.restDocPath, isEmpty);
      // An absent key still falls back.
      expect(loadFrom('name: acme\n').graphqlDocPath, '/graphql-doc');
    });

    test('refuses a pubspec it cannot identify', () {
      expect(() => loadFrom('description: no name here\n'), throwsStateError);
      expect(
        () => ImporterConfig.load('does/not/exist/pubspec.yaml'),
        throwsStateError,
      );
    });
  });

  group('package URIs', () {
    setUp(() => importerConfig = const ImporterConfig(packageName: 'acme'));

    test('accepts a path from the package root or from lib', () {
      expect(
        packageUriFor('lib/v1/models/enums.dart'),
        'package:acme/v1/models/enums.dart',
      );
      expect(
        packageUriFor('v1/models/enums.dart'),
        'package:acme/v1/models/enums.dart',
      );
    });

    test('normalises the separator Windows hands it', () {
      expect(
        packageUriFor(r'lib\models\product.dart'),
        'package:acme/models/product.dart',
      );
    });

    test('resolves a path relative to the file being written', () {
      final imports = ImportBlock()
        ..addRelative('lib/rest/endpoints', '../../models/product.dart');

      expect(imports.render(), "import 'package:acme/models/product.dart';\n");
    });
  });

  group('import block', () {
    setUp(() => importerConfig = const ImporterConfig(packageName: 'acme'));

    test('groups dart before package, sorts, and de-duplicates', () {
      final imports = ImportBlock()
        ..add('package:shelf/shelf.dart')
        ..add('dart:convert')
        ..add('package:collection/collection.dart')
        ..add('dart:async')
        ..add('package:shelf/shelf.dart');

      expect(imports.render(), '''
import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:shelf/shelf.dart';
''');
    });

    test('renders nothing when it holds nothing', () {
      expect(ImportBlock().render(), isEmpty);
      expect(ImportBlock().isEmpty, isTrue);
    });
  });

  group('string literals', () {
    test('picks the quote that needs no escaping', () {
      expect(
        dartStringLiteral("unité d'établissement"),
        '"unité d\'établissement"',
      );
      expect(dartStringLiteral('a "quoted" word'), "'a \"quoted\" word'");
    });

    test('escapes what would change the meaning of the source', () {
      expect(dartStringLiteral(r'C:\Users\raphx'), r"'C:\\Users\\raphx'");
      expect(dartStringLiteral(r'costs $5'), r"'costs \$5'");
    });

    test('keeps the literal on one line', () {
      expect(dartStringLiteral('one\ntwo'), r"'one\ntwo'");
      expect(dartStringLiteral('one\r\ntwo'), r"'one\ntwo'");
    });

    test('falls back to single quotes when both appear', () {
      expect(dartStringLiteral('''it's "both"'''), '\'it\\\'s "both"\'');
    });
  });

  group('async detection', () {
    test('sees a real await', () {
      expect(awaitsSomething('  final x = await load();'), isTrue);
    });

    test('is not fooled by a word that contains it', () {
      expect(awaitsSomething('  return awaited;'), isFalse);
      expect(awaitsSomething('  var awaitCount = 0;'), isFalse);
    });

    test('says no for a body that only throws', () {
      expect(awaitsSomething('  throw UnimplementedError();'), isFalse);
    });
  });

  group('library rendering', () {
    setUp(() => importerConfig = const ImporterConfig(packageName: 'acme'));

    test('sits the doc comment against a library directive', () {
      final rendered = renderGeneratedLibrary(
        description: 'A product on sale.',
        extra: const ['Auto generated.'],
        imports: ImportBlock()..add('package:shelf/shelf.dart'),
        partFile: 'product.g.dart',
        body: 'class Product {}',
      );

      expect(rendered, '''
/// A product on sale.
/// Auto generated.
library;

import 'package:shelf/shelf.dart';

part 'product.g.dart';

class Product {}
''');
    });

    test('ends with exactly one newline', () {
      final rendered = renderGeneratedLibrary(body: 'class A {}\n\n\n');

      expect(rendered, 'class A {}\n');
    });

    test('puts the ignores above everything, sorted', () {
      final rendered = renderGeneratedLibrary(
        ignoreForFile: const ['unused_import', 'constant_identifier_names'],
        description: 'The enums.',
        body: 'enum A { B }',
      );

      expect(
        rendered,
        startsWith('''
// ignore_for_file: constant_identifier_names, unused_import
/// The enums.
library;
'''),
      );
    });

    test('omits the header when there is nothing to document', () {
      expect(renderGeneratedLibrary(body: 'class A {}'), 'class A {}\n');
    });
  });

  group('build.yaml', () {
    /// A throwaway path in a directory that cleans itself up.
    String tempPath() {
      final dir = Directory.systemTemp.createTempSync('goc_build');
      addTearDown(() => dir.deleteSync(recursive: true));
      return '${dir.path}/build.yaml';
    }

    test('names the builders that only run for a package declaring them', () {
      importerConfig = const ImporterConfig(packageName: 'acme');
      final path = tempPath();

      ensureBuildYaml(path: path);

      final written = File(path).readAsStringSync();
      expect(written, contains('json_serializable:'));
      expect(written, contains('copy_with_extension_gen:'));
      expect(written, contains(r'$default'));
      // graphql_generator3 is auto_apply: root_package, so it needs no entry.
      expect(written, isNot(contains('graphql_generator3')));
    });

    test('leaves copy_with_extension_gen out when copy_with is off', () {
      importerConfig = const ImporterConfig(
        packageName: 'acme',
        copyWith: false,
      );
      final path = tempPath();

      ensureBuildYaml(path: path);

      final written = File(path).readAsStringSync();
      expect(written, contains('json_serializable:'));
      expect(written, isNot(contains('copy_with_extension_gen')));
    });

    test('never overwrites one that is already there', () {
      importerConfig = const ImporterConfig(packageName: 'acme');
      final path = tempPath();
      const mine =
          'targets:\n  \$default:\n    builders:\n'
          '      json_serializable:\n        enabled: true\n'
          '      copy_with_extension_gen:\n        enabled: true\n';
      File(path).writeAsStringSync(mine);

      ensureBuildYaml(path: path);

      expect(File(path).readAsStringSync(), mine);
    });
  });

  group('validator naming', () {
    test('prefixes valid and drops the leading underscore', () {
      expect(validatorNameFor('_vatNo'), 'validVatNo');
      expect(validatorNameFor('_skuFormat'), 'validSkuFormat');
    });

    test('a directive already named valid says it twice', () {
      // Not a bug to route around: the rule is one rule, and the README says
      // to name the directive after the field rather than after the check.
      expect(validatorNameFor('_validVat'), 'validValidVat');
    });
  });

  group('created once files', () {
    test('records what it wrote, so the run formats it exactly once', () {
      final dir = Directory.systemTemp.createTempSync('goc_once');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/nested/stub.dart');

      createdOnceFiles.clear();
      writeCreatedOnceFile(file, 'void main() {}\n');

      expect(file.readAsStringSync(), 'void main() {}\n');
      expect(createdOnceFiles, [file.path]);
    });
  });

  group('html escaping', () {
    test('escapes the markup characters and the interpolation sign', () {
      expect(htmlEscaped('a & b'), 'a &amp; b');
      expect(htmlEscaped('<tag>'), '&lt;tag&gt;');
      expect(htmlEscaped(r'$name'), r'\$name');
    });
  });
}
