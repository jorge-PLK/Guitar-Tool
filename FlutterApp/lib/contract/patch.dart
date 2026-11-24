import 'package:flutter/foundation.dart' show immutable;

import '../core/core_client.dart' show Json;

/// Campo de params con tres estados: ausente (no tocar), `null` explícito o valor.
@immutable
class Patch<T> {
  const Patch.absent()
      : isPresent = false,
        value = null;
  const Patch.nullValue()
      : isPresent = true,
        value = null;
  const Patch.of(T this.value)
      : isPresent = true;

  /// Lee [key]: ausente si no está en [j]; `null` explícito si vale `null`.
  factory Patch.fromMap(Json j, String key, T Function(Object? raw) read) {
    if (!j.containsKey(key)) return const Patch.absent();
    final raw = j[key];
    return raw == null ? const Patch.nullValue() : Patch.of(read(raw));
  }

  final bool isPresent;
  final T? value;

  /// Escribe [key] solo si está presente; con `null` explícito escribe `null`.
  void writeTo(Json j, String key) {
    if (isPresent) j[key] = value;
  }
}
