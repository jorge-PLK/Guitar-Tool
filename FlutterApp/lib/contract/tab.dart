// DTO del área `tab` (Tablatura) y `tab.songsterr`. A mano, sin generación de código.
// Nombres de campo JSON = los de Swift y los fixtures de Contract/fixtures/tab.
// Ficha: docs/flutter/contrato-tipos-b.md §«tab y tab.songsterr».
// Respuestas y eventos: solo fromJson. Parámetros: fromJson y toJson.
// Las partes comparten los helpers privados de esta librería.

import 'package:toneforge/core/core_client.dart' show Json;

part 'tab_params.dart';
part 'tab_songsterr.dart';
part 'tab_types.dart';

/// Enum con su valor crudo del JSON en [wire]. Lo no previsto cae en `unknown`.
mixin TabWire on Enum {
  String get wire;
}

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

List<int> _ints(Object? v) => [for (final e in v! as List<Object?>) _i(e)];

List<String> _strs(Object? v) => [for (final e in v! as List<Object?>) e! as String];

/// Valor desconocido → [unknown]; nunca lanza.
T _enumOr<T extends TabWire>(List<T> values, Object? raw, T unknown) {
  for (final v in values) {
    if (v.wire == raw) return v;
  }
  return unknown;
}

T? _enumN<T extends TabWire>(List<T> values, Object? raw, T unknown) =>
    raw == null ? null : _enumOr(values, raw, unknown);

/// Valor crudo de un enum para enviar. `unknown` no se envía nunca.
String _wire(TabWire e) => e.wire == 'unknown'
    ? throw StateError('valor de enum no enviable: $e')
    : e.wire;

String? _wireOpt(TabWire? e) => e == null ? null : _wire(e);

/// Quita las claves nulas (ausente = null en el JSON del núcleo).
Json _compact(Json m) {
  m.removeWhere((_, v) => v == null);
  return m;
}

// Respuestas y eventos (solo fromJson).

final class TabScoreResult {
  const TabScoreResult({
    required this.json,
    required this.trackIndex,
    required this.trackIDs,
    required this.revision,
  });

  factory TabScoreResult.fromJson(Json j) => TabScoreResult(
        json: _s(j['json']),
        trackIndex: _i(j['trackIndex']),
        trackIDs: _strs(j['trackIDs']),
        revision: _i(j['revision']),
      );

  /// Partitura `tf-score` v1 como cadena JSON, sin modelar (la consume alphaTab).
  final String json;
  final int trackIndex;
  final List<String> trackIDs;
  final int revision;
}

final class TabQueuedResult {
  const TabQueuedResult({required this.queued});

  factory TabQueuedResult.fromJson(Json j) =>
      TabQueuedResult(queued: _strs(j['queued']));

  final List<String> queued;
}

final class TabCancelResult {
  const TabCancelResult({required this.cancelled});

  factory TabCancelResult.fromJson(Json j) =>
      TabCancelResult(cancelled: _b(j['cancelled']));

  final bool cancelled;
}

final class TabExportNameResult {
  const TabExportNameResult({required this.fileName});

  factory TabExportNameResult.fromJson(Json j) =>
      TabExportNameResult(fileName: _s(j['fileName']));

  final String fileName;
}

/// `saved:false` sin `path` = diálogo cancelado.
final class TabExportResult {
  const TabExportResult({required this.saved, this.path});

  factory TabExportResult.fromJson(Json j) =>
      TabExportResult(saved: _b(j['saved']), path: _sn(j['path']));

  final bool saved;
  final String? path;
}

final class TabProgressEvent {
  const TabProgressEvent({
    required this.state,
    required this.track,
    required this.fraction,
    this.error,
  });

  factory TabProgressEvent.fromJson(Json j) => TabProgressEvent(
        state: _enumOr(TabProgressState.values, j['state'], TabProgressState.unknown),
        track: _s(j['track']),
        fraction: _d(j['fraction']),
        error: _sn(j['error']),
      );

  final TabProgressState state;
  final String track;
  final double fraction;
  final String? error;
}

final class TabSelectionEvent {
  const TabSelectionEvent({required this.bar, required this.fraction});

  factory TabSelectionEvent.fromJson(Json j) =>
      TabSelectionEvent(bar: _i(j['bar']), fraction: _d(j['fraction']));

  /// `bar:-1` = sin selección.
  final int bar;
  final double fraction;
}

final class TabRangeEvent {
  const TabRangeEvent({
    required this.startBar,
    required this.startFraction,
    required this.endBar,
    required this.endFraction,
  });

  factory TabRangeEvent.fromJson(Json j) => TabRangeEvent(
        startBar: _i(j['startBar']),
        startFraction: _d(j['startFraction']),
        endBar: _i(j['endBar']),
        endFraction: _d(j['endFraction']),
      );

  /// Todo `-1`/0 = sin tramo.
  final int startBar;
  final double startFraction;
  final int endBar;
  final double endFraction;
}
