import 'dart:io';

import 'package:graphql_openapi_codegen/src/config.dart';
import 'package:graphql_openapi_codegen/src/enums.dart';
import 'package:graphql_openapi_codegen/src/log.dart';

/// The builders this tool needs that `build_runner` will not start on its own.
///
/// A builder declares who it runs for. `graphql_generator3` says
/// `auto_apply: root_package`, so it runs for whoever invokes `build_runner`
/// and needs nothing here. `json_serializable` and `copy_with_extension_gen`
/// say `auto_apply: dependents`, which means they run only for a package that
/// declares them **itself** — a transitive dependency is not enough.
///
/// Naming them in the target package's `build.yaml` is what lifts that, and is
/// why the package you generate into does not have to carry these in its own
/// `dev_dependencies`.
const _jsonSerializable = 'json_serializable';
const _copyWithExtensionGen = 'copy_with_extension_gen';

/// Writes `build.yaml` next to the target package's `pubspec.yaml`.
///
/// Created once. A `build.yaml` is a file whose owner configures their whole
/// build in it, so overwriting one would throw away work that has nothing to
/// do with this tool. When one is already there, [ensureBuildYaml] checks it
/// names what the generated code needs and says what to add if it does not.
void ensureBuildYaml({String path = 'build.yaml'}) {
  final file = File(path);
  final required = <String>[
    _jsonSerializable,
    if (importerConfig.copyWith) _copyWithExtensionGen,
  ];

  if (file.existsSync()) {
    final content = file.readAsStringSync();
    final missing = required.where((b) => !content.contains(b)).toList();
    if (missing.isNotEmpty) {
      logMessage(
        '\n⚠️  build.yaml does not enable ${missing.join(' or ')}. '
        'Without it the `.g.dart` parts are not written.\n'
        'Add under `targets: \$default: builders:`:\n'
        '${missing.map((b) => '  $b:\n    enabled: true').join('\n')}',
        type: MessageType.warning,
      );
    }
    return;
  }

  final b = StringBuffer()
    ..writeln('# Written once by graphql_openapi_codegen. Edit freely.')
    ..writeln('#')
    ..writeln(
      '# These builders only run for a package that names them, which is what',
    )
    ..writeln(
      '# this does. Without it they are skipped and the models lose their',
    )
    ..writeln('# `fromJson`, `toJson` and `copyWith`.')
    ..writeln('targets:')
    ..writeln(r'  $default:')
    ..writeln('    builders:');
  for (final builder in required) {
    b
      ..writeln('      $builder:')
      ..writeln('        enabled: true');
  }

  file.writeAsStringSync(b.toString());
}
