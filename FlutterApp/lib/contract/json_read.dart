import '../core/core_client.dart' show Json;

/// Decodificadores compartidos por los ficheros de `contract/`.
double jsonDouble(Object? v) => (v as num).toDouble();
double? jsonOptDouble(Object? v) => (v as num?)?.toDouble();
List<T> jsonList<T>(Object? raw, T Function(Json) decode) => List.unmodifiable([
  for (final e in raw as List<Object?>) decode(e as Json),
]);
