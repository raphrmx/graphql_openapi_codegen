import 'dart:io';

import 'package:graphql_openapi_codegen/src/enums.dart';

/// Prints a message to the console, coloured by its type.
///
/// Uses ANSI escape codes, so the colours degrade to noise-free plain text on a
/// terminal that ignores them. An empty message prints nothing at all, which
/// lets a caller pass a value it has not checked.
///
/// Parameters:
/// - [message]: the text to display.
/// - [type]: what the message is, which decides its colour.
void logMessage(String message, {MessageType type = MessageType.normal}) {
  if (message.trim().isEmpty) return;

  final color = switch (type) {
    MessageType.normal => '\x1B[0m',
    MessageType.info => '\x1B[34m',
    MessageType.warning => '\x1B[33m',
    MessageType.error => '\x1B[31m',
    MessageType.success => '\x1B[32m',
  };

  // A normal message needs no reset: it already uses the default colour. Every
  // other one is closed so the next line of output is not tinted too.
  stdout.writeln(
    type == MessageType.normal ? '$color$message' : '$color$message\x1B[0m',
  );
}
