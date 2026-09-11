import 'package:graphql_openapi_codegen/src/config.dart';

/// The paths the importer reads from and writes to.
///
/// They used to be constants spelling out one project's layout. They now
/// delegate to [importerConfig], which reads them from the `graphql_importer:`
/// section of `pubspec.yaml` and falls back to those same values, so the call
/// sites did not have to change.

/// The GraphQL SDL the generation reads.
String get schemaFilePath => importerConfig.schemaPath;

String get modelsOutputDirPath => importerConfig.modelsDir;
String get fieldsOutputDirPath => importerConfig.fieldsDir;
String get validatorsDirPath => importerConfig.validatorsDir;
String get resolversDirPath => importerConfig.resolversDir;
String get graphqlDirPath => importerConfig.graphqlDir;
String get restDirPath => importerConfig.restDir;
String get openApiYamlDirPath => importerConfig.openApiDir;
String get endpointsDirPath => importerConfig.endpointsDir;
String get routesDirPath => importerConfig.routesDir;
