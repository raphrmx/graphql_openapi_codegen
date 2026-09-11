/// Generates a Dart server from a GraphQL schema.
///
/// The entry point is the `graphql_openapi_codegen` executable:
///
/// ```bash
/// dart run graphql_openapi_codegen
/// ```
///
/// It reads its settings from the `graphql_openapi_codegen:` section of the
/// package's `pubspec.yaml`. See [ImporterConfig] for what that section holds,
/// and [run] to drive the generation from Dart instead.
library;

export 'src/config.dart' show ImporterConfig, importerConfig;
export 'src/runner.dart' show run;
