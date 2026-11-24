// DTO del área `study` (Backing). A mano, sin generación de código.
// Nombres de campo JSON = los de Swift y los fixtures de Contract/fixtures/study.
// Ficha: docs/flutter/pantallas/backing-contrato.md §5 «Tipos».
// Respuestas y eventos: solo fromJson. Parámetros: fromJson y toJson.
// Las partes comparten los helpers privados de esta librería.

import 'package:toneforge/core/core_client.dart' show Json;

part 'study_analysis.dart';
part 'study_events.dart';
part 'study_params.dart';
part 'study_types.dart';

Json _map(Object? v) => (v! as Map).cast<String, Object?>();

List<T> _items<T>(Object? v, T Function(Json) fromJson) => [
      for (final e in v! as List<Object?>) fromJson(_map(e)),
    ];

T? _opt<T>(Object? v, T Function(Json) fromJson) =>
    v == null ? null : fromJson(_map(v));

double _d(Object? v) => (v! as num).toDouble();

double? _dn(Object? v) => v == null ? null : _d(v);

int _i(Object? v) => (v! as num).toInt();

int? _in(Object? v) => v == null ? null : _i(v);

bool _b(Object? v) => v! as bool;

bool? _bn(Object? v) => v as bool?;

String _s(Object? v) => v! as String;

String? _sn(Object? v) => v as String?;

List<double> _ds(Object? v) => [for (final e in v! as List<Object?>) _d(e)];

Map<String, String> _strs(Object? v) => {
      for (final e in _map(v).entries) e.key: e.value! as String,
    };

/// Valor desconocido → [unknown]; nunca lanza.
T _enumOr<T extends Enum>(List<T> values, Object? raw, T unknown) {
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return unknown;
}

/// Quita las claves nulas (ausente = null en el JSON del núcleo).
Json _compact(Json m) {
  m.removeWhere((_, v) => v == null);
  return m;
}

/// Valor crudo de un enum para enviar. `unknown` no se envía nunca.
String _wire(Enum e) => e.name == 'unknown'
    ? throw StateError('valor de enum no enviable: $e')
    : e.name;

String? _wireOpt(Enum? e) => e == null ? null : _wire(e);
