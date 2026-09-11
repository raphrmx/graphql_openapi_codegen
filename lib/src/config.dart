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
///   schema: lib/schema.graphql    # the SDL every generator reads
///   class_prefix: ''              # replaces the leading `_` of a host type
///   copy_with: true               # emit @CopyWith() on the models
///   api_name: ''                  # OpenAPI title, defaults to the package name
///   api_servers: []               # OpenAPI `servers:` entries
///   routes:                     # every entry here is an HTTP path
///     graphql: /graphql           # where the GraphQL API answers
///     rest: ''                    # prefix the REST endpoints are mounted under
///     graphql_doc: /graphql-doc   # the Playground page, '' disables it
///     rest_doc: /rest-doc         # the Swagger UI page, '' disables it
///     openapi: /openapi.yaml      # where Swagger fetches the document
///   output:                    # every entry here is a filesystem path
///     models: lib/models          # the model, input and enum classes
///     fields: lib/graphql/fields  # the Query/Mutation/Subscription field lists
///     validators: lib/validators  # one stub per custom `@_directive`
///     resolvers: lib/resolvers    # the resolver stubs and register_all.dart
///     graphql: lib/graphql        # graphql_resolvers_registry.dart
///     rest: lib/rest              # rest_routes.dart
///     endpoints: lib/rest/endpoints  # one handler per operation
///     openapi: assets             # openapi.yaml
///     routes: lib/routes          # the two documentation pages and doc_routes.dart
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

  /// Route the GraphQL API answers on. The Playground page sends its queries
  /// here.
  final String graphqlPath;

  /// Prefix the generated REST endpoints are mounted under. It becomes the
  /// default `prefix` of `registerRestRoutes` and prefixes the `paths:` of the
  /// OpenAPI document, so the two cannot drift apart.
  final String restPrefix;

  /// Route of the generated GraphQL Playground page. Empty disables it.
  final String graphqlDocPath;

  /// Route of the generated Swagger UI page. Empty disables it.
  final String restDocPath;

  /// Where the Swagger UI fetches the OpenAPI document. An HTTP path, not the
  /// place the file is written, which is [openApiDir].
  final String openApiUrl;

  /// Directory the route files are written to.
  final String routesDir;

  /// Directory the model, input and enum classes are written to.
  final String modelsDir;

  /// Directory the `Query`, `Mutation` and `Subscription` field lists are
  /// written to.
  final String fieldsDir;

  /// Directory the validator stubs and their facade are written to.
  final String validatorsDir;

  /// Directory the resolver stubs and `register_all.dart` are written to.
  final String resolversDir;

  /// Directory `graphql_resolvers_registry.dart` is written to.
  final String graphqlDir;

  /// Directory `rest_routes.dart` is written to.
  final String restDir;

  /// Directory the per-operation REST handlers are written to.
  final String endpointsDir;

  /// Directory `openapi.yaml` is written to. Where the file lands, not where it
  /// is served from, which is [openApiUrl].
  final String openApiDir;

  const ImporterConfig({
    required this.packageName,
    this.packageVersion = '0.0.0',
    this.schemaPath = 'lib/schema.graphql',
    this.classPrefix = '',
    this.copyWith = true,
    this.apiName = '',
    this.apiServers = const [],
    this.graphqlPath = '/graphql',
    this.restPrefix = '',
    this.graphqlDocPath = '/graphql-doc',
    this.restDocPath = '/rest-doc',
    this.openApiUrl = '/openapi.yaml',
    this.routesDir = 'lib/routes',
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

    final docs = section['routes'];
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
      graphqlPath: str(doc, 'graphql', fallback.graphqlPath),
      restPrefix: str(doc, 'rest', fallback.restPrefix),
      graphqlDocPath: str(doc, 'graphql_doc', fallback.graphqlDocPath),
      restDocPath: str(doc, 'rest_doc', fallback.restDocPath),
      openApiUrl: str(doc, 'openapi', fallback.openApiUrl),
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
