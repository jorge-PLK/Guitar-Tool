import 'package:flutter/foundation.dart' show immutable;

import '../core/core_client.dart' show Json;

/// `CoreMessage`: `{code, message, args?}`. `args` ausente o vacío = omitido al codificar.
@immutable
class CoreMessage {
  const CoreMessage({
    required this.code,
    required this.message,
    this.args = const {},
  });

  factory CoreMessage.fromJson(Json j) => CoreMessage(
        code: j['code'] as String,
        message: j['message'] as String,
        args: j['args'] == null ? const {} : Map<String, Object?>.from(j['args'] as Json),
      );

  final String code;
  final String message;
  final Map<String, Object?> args;

  Json toJson() => {
        'code': code,
        'message': message,
        if (args.isNotEmpty) 'args': args,
      };
}
