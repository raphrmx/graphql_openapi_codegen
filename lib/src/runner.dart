/// The generation pipeline.
///
/// Reads the SDL named by the configuration, writes the Dart sources, runs
/// `build_runner` for the `.g.dart` parts, then `dart format` on what it
/// overwrites.
library;

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:graphql_openapi_codegen/src/build_yaml_generator.dart';
import 'package:graphql_openapi_codegen/src/class_generator.dart';
import 'package:graphql_openapi_codegen/src/consts.dart';
import 'package:graphql_openapi_codegen/src/doc_routes_generator.dart';
import 'package:graphql_openapi_codegen/src/enum_generator.dart';
import 'package:graphql_openapi_codegen/src/enums.dart';
import 'package:graphql_openapi_codegen/src/extends.dart';
import 'package:graphql_openapi_codegen/src/generated_endpoint.dart';
import 'package:graphql_openapi_codegen/src/helpers.dart';
import 'package:graphql_openapi_codegen/src/input_generator.dart';
import 'package:graphql_openapi_codegen/src/interface_generator.dart';
import 'package:graphql_openapi_codegen/src/log.dart';
import 'package:graphql_openapi_codegen/src/openapi_yaml_generator.dart';
import 'package:graphql_openapi_codegen/src/operation_fields_generator.dart';
import 'package:graphql_openapi_codegen/src/post_process.dart';
import 'package:graphql_openapi_codegen/src/resolver_generator.dart';
import 'package:graphql_openapi_codegen/src/rest_endpoints_generator.dart';
import 'package:graphql_openapi_codegen/src/union_generator.dart';
import 'package:graphql_openapi_codegen/src/validator_generator.dart';
import 'package:path/path.dart' as path;

/// Main function that orchestrates the entire GraphQL code generation process.
///
/// This script automates the creation of Dart models, resolvers, and validators
/// from a GraphQL schema file. It handles parsing, file generation, and
/// integrates with `build_runner` to ensure a complete and type-safe output.
Future<void> run(List<String> args) async {
  // Define file and directory paths for input and output.
  final schemaFile = File(schemaFilePath);
  final modelsOutputDir = Directory(modelsOutputDirPath);
  final fieldsOutputDir = Directory(fieldsOutputDirPath);
  final validatorsDir = Directory(validatorsDirPath);
  final resolversDir = Directory(resolversDirPath);
  final graphqlDir = Directory(graphqlDirPath);
  final restDir = Directory(restDirPath);
  final openApiYamlDir = Directory(openApiYamlDirPath);
  final endpointsDir = Directory(endpointsDirPath);

  if (!restDir.existsSync()) restDir.createSync(recursive: true);
  if (!endpointsDir.existsSync()) endpointsDir.createSync(recursive: true);
  if (!modelsOutputDir.existsSync()) {
    modelsOutputDir.createSync(recursive: true);
  }
  if (!openApiYamlDir.existsSync()) openApiYamlDir.createSync(recursive: true);

  // --- Step 1: Initialization and Setup ---

  // Cleanup step: Deletes the contents of the models and fields directories.
  // This ensures that any old files from a previous generation run are removed.
  logMessage('\nCleaning up old generated files...');
  if (modelsOutputDir.existsSync()) {
    modelsOutputDir.deleteSync(recursive: true);
  }
  if (fieldsOutputDir.existsSync()) {
    fieldsOutputDir.deleteSync(recursive: true);
  }

  // Check for the existence of the schema file and exit with an error if not found.
  if (!schemaFile.existsSync()) {
    logMessage(
      '❌ Error: schema file not found at ${schemaFile.path}',
      type: MessageType.error,
    );
    logMessage(' ');
    exit(1);
  }

  logMessage('\nRunning GraphQL parser...');

  // Ensure all necessary output directories exist before proceeding.
  if (!graphqlDir.existsSync()) {
    graphqlDir.createSync(recursive: true);
  }
  if (!modelsOutputDir.existsSync()) {
    modelsOutputDir.createSync(recursive: true);
  }
  if (!fieldsOutputDir.existsSync()) {
    fieldsOutputDir.createSync(recursive: true);
  }
  if (!validatorsDir.existsSync()) {
    validatorsDir.createSync(recursive: true);
  }
  if (!resolversDir.existsSync()) {
    resolversDir.createSync(recursive: true);
  }

  try {
    // --- Step 2: Schema Processing ---

    // Parse the schema string into a `DocumentNode` (AST).
    var document = gql_lang.parseString(schemaFile.readAsStringSync());

    // Merge any `extend type` directives into their base definitions.
    document = mergeExtensions(document);

    // --- Step 3: Code Generation Logic ---

    // Initialize counters for a final summary report.
    int inputCount = 0;
    int typeCount = 0;
    int enumCount = 0;
    int validatorCount = 0;
    int interfaceCount = 0;
    int unionCount = 0;
    int resolverCount = 0;
    int queryCount = 0;
    int mutationCount = 0;
    int subscriptionCount = 0;

    // Generate resolver stubs based on the document. This is done early to ensure
    // that the `register_all` file includes all resolvers.
    resolverCount = generateResolversFromDocument(
      rootDir: Directory.current.path,
      document: document,
      includeOperations:
          false, // ou false si tu ne veux pas Query/Mutation/Subscription
    );

    // Collect custom directives that require a validator to be generated.
    final directivesToGenerate = <String, String?>{};
    for (final definition in document.definitions) {
      if (definition is InputObjectTypeDefinitionNode) {
        for (final field in definition.fields) {
          for (final directive in field.directives) {
            if (directive.name.value.startsWith('_')) {
              final directiveDef =
                  document.definitions.firstWhereOrNull(
                        (d) =>
                            d is DirectiveDefinitionNode &&
                            d.name.value == directive.name.value,
                      )
                      as DirectiveDefinitionNode?;
              directivesToGenerate[directive.name.value] =
                  directiveDef?.description?.value;
            }
          }
        }
      }
    }

    // Generate individual validator files based on the collected directives.
    validatorCount = generateValidators(validatorsDir, directivesToGenerate);

    final queryFiles = <GeneratedEndpoint>[];
    final mutationFiles = <GeneratedEndpoint>[];
    final subscriptionFiles = <GeneratedEndpoint>[];

    // Iterate through all definitions to generate the corresponding Dart files.
    for (final definition in document.definitions) {
      if (definition is InputObjectTypeDefinitionNode) {
        final fields = getFieldsForType(definition as TypeDefinitionNode);
        if (fields.isNotEmpty) {
          generateInputClassFile(modelsOutputDir, document, definition);
          inputCount++;
        }
      } else if (definition is ObjectTypeDefinitionNode) {
        final fields = getFieldsForType(definition as TypeDefinitionNode);
        // Special handling for built-in operations (Query, Mutation, Subscription).
        if (fields.isNotEmpty) {
          if (definition.name.value == 'Query') {
            generateOperationFieldsFile(
              fieldsOutputDir,
              document,
              definition,
              'Query',
            );
            for (final f in definition.fields) {
              final generatedQuery = generateQueryEndpointFile(
                restDir,
                document,
                f,
              );
              if (generatedQuery != null) {
                queryFiles.add(generatedQuery);
              }
              queryCount++;
            }
          } else if (definition.name.value == 'Mutation') {
            generateOperationFieldsFile(
              fieldsOutputDir,
              document,
              definition,
              'Mutation',
            );
            for (final f in definition.fields) {
              final generatedMutation = generateMutationEndpointFile(
                restDir,
                document,
                f,
              );
              if (generatedMutation != null) {
                mutationFiles.add(generatedMutation);
              }
              mutationCount++;
            }
          } else if (definition.name.value == 'Subscription') {
            generateOperationFieldsFile(
              fieldsOutputDir,
              document,
              definition,
              'Subscription',
            );
            for (final f in definition.fields) {
              writeSubscriptionResolverStub(
                Directory.current.path,
                document,
                f,
              );
              final generatedSubscription = generateSubscriptionEndpointFile(
                restDir,
                document,
                f,
              );
              if (generatedSubscription != null) {
                subscriptionFiles.add(generatedSubscription);
              }
              subscriptionCount++;
            }
          } else {
            // General object type generation.
            generateClassFile(modelsOutputDir, document, definition);
            typeCount++;
          }
        }
      } else if (definition is EnumTypeDefinitionNode) {
        generateEnumClass(modelsOutputDir, document, definition);
        enumCount++;
      } else if (definition is UnionTypeDefinitionNode) {
        generateUnionClass(modelsOutputDir, document, definition);
        unionCount++;
      } else if (definition is InterfaceTypeDefinitionNode) {
        generateInterfaceClass(modelsOutputDir, definition);
        interfaceCount++;
      }
    }

    // Ensure central files (e.g., a shared `enums` file) exist.
    ensureEnumsFile(modelsOutputDir);
    ensureResolverRegistryFile(graphqlDir);
    generateRestRoutesFile(
      restDir,
      queryFiles: queryFiles,
      mutationFiles: mutationFiles,
      subscriptionFiles: subscriptionFiles,
    );
    generateDocRoutes(Directory(routesDirPath));
    generateOpenApiYaml(
      openApiYamlDir,
      document,
      queryFiles: queryFiles,
      mutationFiles: mutationFiles,
      subscriptionFiles: subscriptionFiles,
    );
    // --- Step 4: Finalization and Build ---

    // `json_serializable` and `copy_with_extension_gen` only run for a
    // package that names them, and naming them there is what spares the
    // target package from carrying them in its own `dev_dependencies`.
    ensureBuildYaml();

    logMessage('\nRunning build_runner...\n');

    // Run the `build_runner` command to generate part files for packages
    // like `json_annotation` and `copy_with_extension`.
    final process = await Process.run('dart', [
      'run',
      'build_runner',
      'build',
    ], runInShell: true);

    // Log the output and check the exit code.
    // logMessage(process.stdout.toString());
    logMessage(process.stderr.toString(), type: MessageType.error);

    if (process.exitCode == 0) {
      // logMessage('\nbuild_runner finished successfully.', type: MessageType.success);
      // Post-process generated files to fix any remaining issues.
      postProcessGeneratedFiles(modelsOutputDir);

      /// Canonical formatting, last. The generators emit readable code; only
      /// the formatter guarantees the single trailing newline the linter asks
      /// for. Pointed at what this tool overwrites on every run, plus the stubs
      /// this particular run created: never at the directories holding them,
      /// because a stub that already existed belongs to whoever edits it.
      final formatted = await formatGeneratedSources([
        modelsOutputDirPath,
        fieldsOutputDirPath,
        path.join(resolversDirPath, 'register_all.dart'),
        path.join(restDirPath, 'rest_routes.dart'),
        path.join(validatorsDirPath, 'validators.dart'),
        path.join(routesDirPath, 'doc_routes.dart'),
        ...createdOnceFiles,
      ]);
      if (formatted.exitCode != 0) {
        logMessage(
          '\n❌ Error: dart format failed: ${formatted.stderr}',
          type: MessageType.error,
        );
        exit(formatted.exitCode);
      }
    } else {
      logMessage(
        '\n❌ Error: build_runner finished with a non-zero exit code: ${process.exitCode}',
        type: MessageType.error,
      );
      exit(process.exitCode);
    }

    // --- Step 5: Logging and Exit ---

    // Print a summary of the generated files.
    //
    // Laid out from the counts rather than by hand: half of these icons are two
    // code points, so a padding counted by eye lines up in one terminal and not
    // in the next, and one of them had lost its space altogether. Only the
    // label is padded, which every terminal measures the same way.
    final summary = <(String, String, int)>[
      ('\u{1F9E9}', 'interface', interfaceCount),
      ('\u{1F4E6}', 'type', typeCount),
      ('\u{1F33F}', 'union', unionCount),
      ('\u{2328}\u{FE0F}', 'input', inputCount),
      ('\u{1F53D}', 'enum', enumCount),
      ('\u{1F6E1}\u{FE0F}', 'validator', validatorCount),
      ('\u{26A1}\u{FE0F}', 'resolver', resolverCount),
      ('\u{1F50D}', 'query', queryCount),
      ('\u{270F}\u{FE0F}', 'mutation', mutationCount),
      ('\u{1F514}', 'subscription', subscriptionCount),
    ];
    final labelWidth = summary
        .map((row) => row.$2.length)
        .reduce((a, b) => a > b ? a : b);

    logMessage('===== Generated code from schema.graphql =====');
    for (final (icon, label, count) in summary) {
      logMessage(
        '$icon  Generated ${'$label:'.padRight(labelWidth + 2)}$count',
        type: MessageType.info,
      );
    }
    logMessage('==============================================');
    logMessage(' ');
    logMessage(
      '✅  GraphQL Code-Gen has been successfully finished!',
      type: MessageType.success,
    );
    logMessage(' ');

    exit(0);
  } catch (e) {
    logMessage(
      '❌ Error while parsing GraphQL schema: $e',
      type: MessageType.error,
    );
    logMessage(' ');
    exit(1);
  }
}
