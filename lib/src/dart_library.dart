import 'dart:io';

import 'package:graphql_openapi_codegen/src/config.dart';
import 'package:path/path.dart' as path;

/// Emission of the generated Dart libraries.
///
/// Every generator used to assemble its own preamble: a doc comment, then a
/// handful of `import` lines written in whatever order the code happened to
/// need them, some of them relative. That produced four lint families on every
/// generated file - a dangling library doc comment, unsorted directives,
/// relative imports inside `lib/`, and a missing final newline. The helpers
/// here are the single place that decides what a generated library looks like,
/// so the generators declare what they need and never spell a directive out.

/// The package the generated files belong to, from [ImporterConfig].
String get packageName => importerConfig.packageName;

/// Converts a path to a file of this package into the `package:` URI the
/// `always_use_package_imports` lint asks for.
///
/// Accepts a path from the package root (`lib/v1/models/enums.dart`) or from
/// `lib/` (`v1/models/enums.dart`), with either separator.
String packageUriFor(String filePath) {
  var normalised = filePath.replaceAll(r'\', '/');
  while (normalised.startsWith('./')) {
    normalised = normalised.substring(2);
  }
  if (normalised.startsWith('lib/')) {
    normalised = normalised.substring('lib/'.length);
  }
  return 'package:$packageName/$normalised';
}

/// The imports of one generated library.
///
/// Holds them as a set so a generator can declare the same import from two
/// branches without emitting it twice, and renders them in the order
/// `directives_ordering` expects: `dart:` first, then `package:`, each group
/// sorted.
class ImportBlock {
  final Set<String> _uris = <String>{};

  /// Adds an absolute import URI, `dart:async` or `package:foo/bar.dart`.
  void add(String uri) => _uris.add(uri);

  /// Adds several absolute import URIs.
  void addAll(Iterable<String> uris) => _uris.addAll(uris);

  /// Adds a file of this package, given its path from the package root or from
  /// `lib/`. Always emitted as a `package:` URI, never as a relative one.
  void addLibFile(String filePath) => _uris.add(packageUriFor(filePath));

  /// Adds a file named relative to [fromDir], the directory of the file being
  /// generated. Resolved against it, then emitted as a `package:` URI.
  void addRelative(String fromDir, String relativePath) => _uris.add(
    packageUriFor(path.normalize(path.join(fromDir, relativePath))),
  );

  bool get isEmpty => _uris.isEmpty;

  /// Renders the import directives, `dart:` group then `package:` group,
  /// sorted inside each group and separated by a blank line.
  String render() {
    if (_uris.isEmpty) return '';
    final dart = _uris.where((u) => u.startsWith('dart:')).toList()..sort();
    final pkg = _uris.where((u) => u.startsWith('package:')).toList()..sort();
    final other =
        _uris
            .where((u) => !u.startsWith('dart:') && !u.startsWith('package:'))
            .toList()
          ..sort();

    final buffer = StringBuffer();
    for (final group in [dart, pkg, other].where((g) => g.isNotEmpty)) {
      if (buffer.isNotEmpty) buffer.writeln();
      for (final uri in group) {
        buffer.writeln("import '$uri';");
      }
    }
    return buffer.toString();
  }
}

/// Renders [value] as a Dart string literal, quotes included.
///
/// Picks the quote character that needs no escaping inside the literal, which
/// is what `avoid_escaping_inner_quotes` asks for, and escapes the three
/// characters that would otherwise change the meaning of the generated source:
/// the backslash, the quote in use, and the dollar sign that would start an
/// interpolation. Newlines become `\n` so the literal stays on one line.
String dartStringLiteral(String value) {
  final quote = value.contains("'") && !value.contains('"') ? '"' : "'";
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll(r'$', r'\$')
      .replaceAll(quote, '\\$quote')
      .replaceAll('\r\n', r'\n')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\n');
  return '$quote$escaped$quote';
}

/// Runs `dart format` over the directories the importer writes into.
///
/// The generators emit readable code, not canonical code. Only the formatter
/// guarantees the single trailing newline `eol_at_end_of_file` asks for, and it
/// Only ever pointed at what the importer overwrites on every run: the stubs
/// it creates once belong to whoever edits them afterwards.
Future<ProcessResult> formatGeneratedSources(Iterable<String> paths) {
  final existing = paths
      .where((p) => Directory(p).existsSync() || File(p).existsSync())
      .toList();
  return Process.run('dart', ['format', ...existing], runInShell: true);
}

/// Whether [body] contains an `await`, and therefore needs its function to be
/// declared `async`.
///
/// A generated body that only forwards a future, or that just throws, never
/// awaits: declaring it `async` is what `unnecessary_async` and
/// `async_return_with_no_await` report. Whoever implements the stub adds the
/// modifier back at the same time as the first `await`.
bool awaitsSomething(String body) => RegExp(r'\bawait\b').hasMatch(body);

/// Escapes [value] for use inside HTML that is itself written into a Dart
/// string literal: the markup characters, and the dollar sign that would
/// otherwise start an interpolation in the generated source.
String htmlEscaped(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll(r'$', r'\$');

/// Writes one generated library to [file].
///
/// Assembles the preamble in the only order that satisfies the linter: the
/// `ignore_for_file` comment, then the library doc comment followed by the
/// `library;` directive it documents, then the imports, then the `part`
/// directive, then [body]. The file always ends with a newline.
///
/// Parameters:
/// - [description]: the documentation of the library, usually the GraphQL
///   description of the type it holds.
/// - [extra]: further documentation lines, appended under [description].
/// - [imports]: what the body needs; rendered sorted and de-duplicated.
/// - [partFile]: the name of the `part` file, if the library has one.
/// - [ignoreForFile]: lint rules to silence for the whole file.
/// - [body]: the generated declarations.
void writeGeneratedLibrary(
  File file, {
  String? description,
  List<String> extra = const [],
  ImportBlock? imports,
  String? partFile,
  List<String> ignoreForFile = const [],
  required String body,
}) {
  file.writeAsStringSync(
    renderGeneratedLibrary(
      description: description,
      extra: extra,
      imports: imports,
      partFile: partFile,
      ignoreForFile: ignoreForFile,
      body: body,
    ),
  );
}

/// The text [writeGeneratedLibrary] writes, exposed on its own so a generator
/// that assembles its file in memory can reuse the same preamble rules.
String renderGeneratedLibrary({
  String? description,
  List<String> extra = const [],
  ImportBlock? imports,
  String? partFile,
  List<String> ignoreForFile = const [],
  required String body,
}) {
  final buffer = StringBuffer();

  if (ignoreForFile.isNotEmpty) {
    final rules = ignoreForFile.toSet().toList()..sort();
    buffer.writeln('// ignore_for_file: ${rules.join(', ')}');
  }

  // The doc comment has to be followed by the `library;` directive it
  // documents, otherwise it dangles and the analyser says so.
  final header = StringBuffer();
  writeDocComments(header, description, extra: extra);
  if (header.isNotEmpty) {
    buffer.write(header);
    buffer.writeln('library;');
    buffer.writeln();
  }

  final rendered = imports?.render() ?? '';
  if (rendered.isNotEmpty) {
    buffer.write(rendered);
    buffer.writeln();
  }

  if (partFile != null) {
    buffer.writeln("part '$partFile';");
    buffer.writeln();
  }

  final trimmed = body.trimRight();
  if (trimmed.isNotEmpty) buffer.writeln(trimmed);

  return buffer.toString();
}

/// Writes formatted Dart documentation comments to a buffer.
///
/// This utility function is designed to generate clean and readable documentation
/// comments (`///`) for Dart code, a critical step in code generation. It handles
/// text wrapping to a specified width and correctly preserves the formatting of
/// markdown code blocks.
///
/// Parameters:
/// - [buffer]: The `StringBuffer` instance to which the documentation will be appended.
/// - [main]: The primary documentation text. Can be null if only extra information is provided.
/// - [extra]: A list of additional strings to be included in the documentation.
/// - [wrap]: The maximum line width for text wrapping. Defaults to 80 characters.
/// - [padding]: A string to prepend to each line for indentation, useful for
///   documenting class members. Defaults to an empty string.
void writeDocComments(
  StringBuffer buffer,
  String? main, {
  List<String> extra = const [],
  int wrap = 80,
  String padding = '',
}) {
  final lines = <String>[];
  final content = [
    if (main != null && main.trim().isNotEmpty) main.trim(),
    ...extra,
  ].join('\n');

  bool inCodeBlock = false;

  /// Iterates through each line of the combined content to apply formatting.
  for (final line in content.split('\n')) {
    /// Detects markdown code block fences (` ``` `). This is a crucial design choice
    /// to prevent the `wrapText` utility from corrupting code examples. The `inCodeBlock`
    /// flag acts as a state machine.
    if (line.trim().startsWith('```')) {
      inCodeBlock = !inCodeBlock;
      lines.add(line);
      continue;
    }

    /// Lines inside a code block are added directly without wrapping.
    if (inCodeBlock) {
      lines.add(line);
    } else {
      /// All other lines are wrapped to the specified width to ensure readability.
      /// The `wrapText` function (assumed to be defined elsewhere) handles the
      /// actual wrapping logic.
      lines.addAll(wrapText(line, width: wrap));
    }
  }

  /// Appends the formatted lines to the `StringBuffer`. Each line is prefixed with the
  /// specified `padding` and the standard `///` documentation syntax.
  for (final l in lines) {
    buffer.writeln('$padding/// $l');
  }
}

/// Wraps a single string of text into a list of lines, ensuring no line exceeds a given width.
///
/// This is a fundamental text formatting utility, essential for generating readable
/// output such as documentation, logs, or formatted console messages. It operates
/// on a word-by-word basis, which is a simple and efficient strategy.
///
/// Parameters:
/// - [text]: The input string to be wrapped. It is assumed to contain words separated by whitespace.
/// - [width]: The maximum number of characters allowed per line. Defaults to 80.
///
/// Returns:
/// - A `List<String>` where each element is a line of the wrapped text.
List<String> wrapText(String text, {int width = 80}) {
  final words = text.split(RegExp(r'\s+'));
  final lines = <String>[];
  final current = StringBuffer();
  for (final w in words) {
    if (current.isEmpty) {
      current.write(w);
      continue;
    }
    if (current.length + 1 + w.length > width) {
      lines.add(current.toString());
      current.clear();
      current.write(w);
    } else {
      current.write(' ');
      current.write(w);
    }
  }
  if (current.isNotEmpty) lines.add(current.toString());
  return lines;
}
