import 'dart:io';

import 'package:graphql_openapi_codegen/src/config.dart';

/// Performs a post-processing step on all generated Dart files ending with `.g.dart`.
///
/// This function is designed to fix a known issue or apply a specific naming
/// convention to auto-generated files that cannot be handled by the initial
/// generation step. It works by reading each file line by line, performing a
/// targeted string replacement, and then writing the corrected content back to the file.
///
/// Parameters:
/// - [outputDir]: The root directory containing the generated files.
void postProcessGeneratedFiles(Directory outputDir) {
  /// Locates all files with the `.g.dart` extension in the output directory
  /// and its subdirectories. This ensures that the post-processing is applied
  /// to all relevant generated files.
  final files = outputDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.g.dart'));

  for (final file in files) {
    final originalContent = file.readAsStringSync();

    final lines = originalContent.split('\n');
    final newLines = <String>[];

    bool corrected = false;
    for (final line in lines) {
      /// Skips the line that was just processed in the previous iteration.
      if (corrected) {
        corrected = false;
        continue;
      }
      final correctedLine = line;

      // Finds the line that starts with `final GraphQLObjectType`. This is the
      // trigger for the specific correction logic.
      if (correctedLine.trim().startsWith('final GraphQLObjectType')) {
        // Finds the next line, which is assumed to contain the field definitions.
        final nextLineIndex = lines.indexOf(line) + 1;
        if (nextLineIndex < lines.length) {
          String nextLine = lines[nextLineIndex];
          newLines.add(correctedLine);
          // Puts the SDL spelling back: the Dart classes carry the configured
          // prefix where the schema had a leading underscore.
          if (importerConfig.classPrefix.isNotEmpty) {
            nextLine = nextLine.replaceAll(importerConfig.classPrefix, '_');
          }
          newLines.add(nextLine);

          /// Sets a flag to skip the next line in the loop, as it has already
          /// been processed and corrected.
          corrected = true;
          continue; // Skips the next line in the loop
        }
      }
      newLines.add(correctedLine);
    }

    /// Writes the corrected content back to the file, replacing the original.
    file.writeAsStringSync(newLines.join('\n'));
  }
}
