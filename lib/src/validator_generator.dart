import 'dart:io';

import 'package:graphql_openapi_codegen/src/helpers.dart';
import 'package:path/path.dart' as path;
import 'package:recase/recase.dart';

/// The main function for generating validator files.
///
/// This function orchestrates the entire validation generation process. It calls
/// a private helper to create a central "facade" file that exports all individual
/// validators, then calls another helper to generate the stub files for each validator
/// if they don't already exist.
///
/// Parameters:
/// - [validatorsDir]: The directory where the validator files will be generated.
/// - [directives]: A map where keys are GraphQL directive names and values are their descriptions.
///
/// Returns:
/// - The number of individual validator files processed.
int generateValidators(
  Directory validatorsDir,
  Map<String, String?> directives,
) {
  _generateValidatorsFacade(validatorsDir, directives.keys.toSet());
  return _generateIndividualValidators(validatorsDir, directives);
}

/// Generates the `validators.dart` facade file.
///
/// This file serves as a **single point of truth** for all validation functions.
/// It is automatically overwritten on every run to ensure it always reflects the
/// current set of directives in the GraphQL schema. This prevents manual
/// maintenance of import statements.
///
/// Parameters:
/// - [validatorsDir]: The directory where the facade file is created.
/// - [directives]: A set of unique GraphQL directive names to be exported.
void _generateValidatorsFacade(
  Directory validatorsDir,
  Set<String> directives,
) {
  final facadeFile = File(path.join(validatorsDir.path, 'validators.dart'));
  final buffer = StringBuffer();

  // Generates an `export` statement for each validator file. The file name is
  // derived from the directive name using a snake_case convention. They are
  // sorted so the directives come out in the order the linter expects.
  final exports =
      directives
          .map((d) => toSnakeCase('valid${ReCase(d.substring(1)).pascalCase}'))
          .toList()
        ..sort();
  for (final validatorFileName in exports) {
    buffer.writeln("export '$validatorFileName.dart';");
  }

  writeGeneratedLibrary(
    facadeFile,
    extra: const [
      'This is a facade for all validation functions.',
      'It is generated on every run to ensure it is up to date.',
    ],
    body: buffer.toString(),
  );
}

/// Generates the individual validator stub files.
///
/// This is the "stubbing" part of the process. It creates a placeholder file for
/// each validation function. Crucially, it **only creates the file if it doesn't
/// already exist**, protecting any custom implementation logic added by the developer
/// from being overwritten. The generated stubs include a `TODO` comment to
/// guide developers on where to add their logic.
///
/// Parameters:
/// - [validatorsDir]: The directory for the validator files.
/// - [directives]: A map of directive names and their descriptions.
///
/// Returns:
/// - An `int` representing the number of validator files that were processed.
int _generateIndividualValidators(
  Directory validatorsDir,
  Map<String, String?> directives,
) {
  int validatorCount = 0;
  for (final entry in directives.entries) {
    final directiveName = entry.key;
    final description = entry.value;
    final validatorName =
        'valid${ReCase(directiveName.substring(1)).pascalCase}';
    final validatorFileName = toSnakeCase(validatorName);
    final validatorFile = File(
      path.join(validatorsDir.path, '$validatorFileName.dart'),
    );

    // This is the core logic of the stubbing mechanism. If the file exists, it is
    // skipped to preserve the developer's work.
    if (!validatorFile.existsSync()) {
      final exampleCode =
          '''
class ClassConstructor {
  final String property;
  const ClassConstructor(this.property) : assert($validatorName(property));
}
''';

      // Writes the placeholder function with a `TODO` and a default `return true`.
      final body = StringBuffer();
      body.writeln('bool $validatorName(dynamic value) {');
      body.writeln('  // TODO: Implement logic for $directiveName');
      body.writeln('  return true;');
      body.writeln('}');

      /// The doc comment carries the GraphQL description, a warning about
      /// editing, and an example of how the function is called from the
      /// generated models.
      writeGeneratedLibrary(
        validatorFile,
        description:
            'This file contains a validation function for the `$directiveName` GraphQL directive.',
        extra: [
          'It is a placeholder that is generated once to allow custom validation logic.',
          if (description != null && description.isNotEmpty)
            'GraphQL Description: $description',
          'To implement the validation, replace the `throw` statement with your own logic.',
          'The function should return `true` if the value is valid and `false` otherwise.',
          'The function is called automatically in the constructor of the generated models.',
          'Example:',
          '```dart',
          exampleCode,
          '```',
        ],
        body: body.toString(),
      );
    }

    validatorCount++;
  }

  return validatorCount;
}
