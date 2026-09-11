import 'dart:io';

import 'package:yaml/yaml.dart';

/// Everything the importer needs to know about the package it generates into.
///
/// Read from the `graphql_openapi_codegen:` section of `pubspec.yaml`, next to
/// the package name it already has to read. Every entry is optional; the fallbacks
/// describe a plain package with no versioned layout and no class prefix, so a
/// project that departs from that says so rather than the tool assuming it.
///
/// ```yaml
/// graphql_openapi_codegen:
///   schema: lib/v1/schema.graphql
///   class_prefix: Bmc
///   copy_with: true
///   api_name: Middleware
///   git_add: false
///   api_servers:
///     - https://example.com/api
///   output:
///     models: lib/v1/models
///     fields: lib/v1/graphql/fields
///     validators: lib/v1/validators
///     resolvers: lib/v1/resolvers
///     graphql: lib/v1/graphql
///     rest: lib/v1/rest
///     endpoints: lib/v1/rest/endpoints
///     openapi: assets
///     routes: lib/routes
///   doc_routes:
///     graphql: /graphql-doc      # '' disables the page
///     rest: /rest-doc
///     graphql_endpoint: /graphql
///     openapi_url: /openapi.yaml
/// ```
class ImporterConfig {
  /// The name of the package, from `pubspec.yaml`. Used to write `package:`
  /// imports into the generated files.
  final String packageName;

  /// The GraphQL SDL the whole generation reads.
  final String schemaPath;

  /// Prefix given to the Dart class of an SDL type whose name starts with `_`.
  /// The SDL marks a type as belonging to the host with a leading underscore,
  /// which is not a legal start for a public Dart identifier.
  ///
  /// Empty means no prefix, and the leading underscore is simply dropped.
  final String classPrefix;

  /// Whether the generated model classes carry `@CopyWith()`. Turning it off
  /// drops the `copy_with_extension` dependency from the consuming package.
  final bool copyWith;

  /// The name that titles the generated OpenAPI document.
  final String apiName;

  /// The version the generated OpenAPI document carries. Taken from the
  /// package version, which a package that is never published may not declare.
  final String packageVersion;

  /// The base URLs listed under `servers:` in the generated OpenAPI document.
  final List<String> apiServers;

  /// Route of the generated GraphQL documentation page, a GraphQL Playground
  /// pointed at [docGraphQLEndpoint]. Empty disables the page.
  final String docGraphQLPath;

  /// Route of the generated REST documentation page, a Swagger UI pointed at
  /// [docOpenApiUrl]. Empty disables the page.
  final String docRestPath;

  /// Where the documentation page sends its GraphQL queries.
  final String docGraphQLEndpoint;

  /// Where the documentation page fetches the OpenAPI document.
  final String docOpenApiUrl;

  /// Directory the route files are written to.
  final String routesDir;

  /// Whether a successful generation stages its result with `git add`.
  /// Off by default: a tool has no business touching the index uninvited.
  final bool gitAdd;

  final String modelsDir;
  final String fieldsDir;
  final String validatorsDir;
  final String resolversDir;
  final String graphqlDir;
  final String restDir;
  final String endpointsDir;
  final String openApiDir;

  const ImporterConfig({
    required this.packageName,
    this.packageVersion = '0.0.0',
    this.schemaPath = 'lib/schema.graphql',
    this.classPrefix = '',
    this.copyWith = true,
    this.apiName = '',
    this.apiServers = const [],
    this.docGraphQLPath = '/graphql-doc',
    this.docRestPath = '/rest-doc',
    this.docGraphQLEndpoint = '/graphql',
    this.docOpenApiUrl = '/openapi.yaml',
    this.routesDir = 'lib/routes',
    this.gitAdd = false,
    this.modelsDir = 'lib/models',
    this.fieldsDir = 'lib/graphql/fields',
    this.validatorsDir = 'lib/validators',
    this.resolversDir = 'lib/resolvers',
    this.graphqlDir = 'lib/graphql',
    this.restDir = 'lib/rest',
    this.endpointsDir = 'lib/rest/endpoints',
    this.openApiDir = 'assets',
  });

  /// Reads the configuration from [pubspecPath].
  ///
  /// Throws if the package name cannot be read: the importer writes `package:`
  /// imports, so it has to be run from the root of the package it generates
  /// into, and failing loudly beats emitting a file that will not resolve.
  factory ImporterConfig.load([String pubspecPath = 'pubspec.yaml']) {
    final file = File(pubspecPath);
    if (!file.existsSync()) {
      throw StateError(
        'No $pubspecPath here. The importer must be run from the root of the '
        'package it generates into.',
      );
    }

    final pubspec = loadYaml(file.readAsStringSync());
    final name = pubspec is YamlMap ? pubspec['name'] : null;
    if (name is! String || name.isEmpty) {
      throw StateError('$pubspecPath declares no package name.');
    }

    final declaredVersion = pubspec is YamlMap ? pubspec['version'] : null;
    final version = declaredVersion == null
        ? '0.0.0'
        : declaredVersion.toString();

    final section = pubspec is YamlMap
        ? pubspec['graphql_openapi_codegen']
        : null;
    if (section is! YamlMap) {
      return ImporterConfig(packageName: name, packageVersion: version);
    }

    final docs = section['doc_routes'];
    final Map<dynamic, dynamic> doc = docs is YamlMap
        ? docs
        : const <dynamic, dynamic>{};

    final output = section['output'];
    final Map<dynamic, dynamic> out = output is YamlMap
        ? output
        : const <dynamic, dynamic>{};

    const fallback = ImporterConfig(packageName: '');
    String str(Map<dynamic, dynamic> from, String key, String orElse) {
      final value = from[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : orElse;
    }

    return ImporterConfig(
      packageName: name,
      packageVersion: version,
      schemaPath: str(section, 'schema', fallback.schemaPath),
      classPrefix: section['class_prefix'] is String
          ? (section['class_prefix'] as String).trim()
          : fallback.classPrefix,
      copyWith: section['copy_with'] is bool
          ? section['copy_with'] as bool
          : fallback.copyWith,
      apiName: str(section, 'api_name', fallback.apiName),
      apiServers: section['api_servers'] is YamlList
          ? (section['api_servers'] as YamlList).whereType<String>().toList()
          : fallback.apiServers,
      modelsDir: str(out, 'models', fallback.modelsDir),
      fieldsDir: str(out, 'fields', fallback.fieldsDir),
      validatorsDir: str(out, 'validators', fallback.validatorsDir),
      resolversDir: str(out, 'resolvers', fallback.resolversDir),
      graphqlDir: str(out, 'graphql', fallback.graphqlDir),
      restDir: str(out, 'rest', fallback.restDir),
      endpointsDir: str(out, 'endpoints', fallback.endpointsDir),
      openApiDir: str(out, 'openapi', fallback.openApiDir),
      routesDir: str(out, 'routes', fallback.routesDir),
      gitAdd: section['git_add'] is bool
          ? section['git_add'] as bool
          : fallback.gitAdd,
      docGraphQLPath: str(doc, 'graphql', fallback.docGraphQLPath),
      docRestPath: str(doc, 'rest', fallback.docRestPath),
      docGraphQLEndpoint: str(
        doc,
        'graphql_endpoint',
        fallback.docGraphQLEndpoint,
      ),
      docOpenApiUrl: str(doc, 'openapi_url', fallback.docOpenApiUrl),
    );
  }
}

ImporterConfig? _config;

/// The configuration of the run, loaded from `pubspec.yaml` on first use.
///
/// Resolved lazily so no generator has to care whether `main` got to it first.
ImporterConfig get importerConfig => _config ??= ImporterConfig.load();

/// Replaces the configuration, for a caller that wants to generate somewhere
/// other than the current directory.
set importerConfig(ImporterConfig value) => _config = value;
