import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/montage.dart';
import 'package:toneforge/contract/montage_params.dart';
import 'package:toneforge/core/core_client.dart' show CoreError, Json;
import 'package:toneforge/core/mock_core.dart';

/// Decodifica con la clase del DTO y vuelve a codificar; el resultado debe igualar al fixture.
typedef _Codec = Json Function(Json j);

Json _snapshot(Json j) => MontageSnapshot.fromJson(j).toJson();
Json _addCut(Json j) => MontageAddCutResult.fromJson(j).toJson();
Json _framingFrame(Json j) => MontageFramingFrameResult.fromJson(j).toJson();
Json _reveal(Json j) => MontageRevealResult.fromJson(j).toJson();
Json _exportEvent(Json j) => MontageExportEvent.fromJson(j).toJson();
Json _framingEvent(Json j) => MontageFramingEvent.fromJson(j).toJson();
Json _position(Json j) => MontagePositionEvent.fromJson(j).toJson();
Json _empty(Json j) => MontageEmptyParams.fromJson(j).toJson();

/// `close` devuelve `{}`: no tiene tipo en la tabla; se comprueba que llega vacío.
Json _voidResult(Json j) {
  expect(j, isEmpty);
  return {};
}

Json _error(Json j) {
  final e = CoreError.fromJson(j);
  return {'code': e.code, 'message': e.message};
}

/// Resultados por método; el resto de `montage.*.result` es `MontageSnapshot`.
final Map<String, _Codec> _results = {
  'addCut': _addCut,
  'framingFrame': _framingFrame,
  'reveal': _reveal,
  'close': _voidResult,
};

/// Eventos: `montage.state` es un snapshot.
final Map<String, _Codec> _events = {
  'state': _snapshot,
  'export': _exportEvent,
  'framing': _framingEvent,
  'position': _position,
};

/// Params por método (`montage.<método>[.<variante>].params`).
final Map<String, _Codec> _params = {
  'open': (j) => MontageOpenParams.fromJson(j).toJson(),
  'setLayout': (j) => MontageLayoutParams.fromJson(j).toJson(),
  'setSingleRhythm': (j) => MontagePartParams.fromJson(j).toJson(),
  'setShowPartLabels': (j) => MontageBoolParams.fromJson(j).toJson(),
  'setKeepVideoAspect': (j) => MontageBoolParams.fromJson(j).toJson(),
  'setCutGaps': (j) => MontageBoolParams.fromJson(j).toJson(),
  'setCaption': (j) => MontageBoolParams.fromJson(j).toJson(),
  'moveLane': (j) => MontageMoveLaneParams.fromJson(j).toJson(),
  'setPartOrder': (j) => MontageOrderParams.fromJson(j).toJson(),
  'addCut': (j) => MontageAddCutParams.fromJson(j).toJson(),
  'moveCut': (j) => MontageCutMoveParams.fromJson(j).toJson(),
  'setCutPart': (j) => MontageCutPartParams.fromJson(j).toJson(),
  'removeCut': (j) => MontageIDParams.fromJson(j).toJson(),
  'setExport': (j) => MontageSetExportParams.fromJson(j).toJson(),
  'rotateTake': (j) => MontageTakeParams.fromJson(j).toJson(),
  'reanalyze': (j) => MontageTakeParams.fromJson(j).toJson(),
  'resetFraming': (j) => MontageTakeParams.fromJson(j).toJson(),
  'setFraming': (j) => MontageSetFramingParams.fromJson(j).toJson(),
  'framingFrame': (j) => MontageFramingFrameParams.fromJson(j).toJson(),
  'seek': (j) => MontageSeekParams.fromJson(j).toJson(),
  'setPreviewFps': (j) => MontageFPSParams.fromJson(j).toJson(),
  'play': _empty,
  'pause': _empty,
  'close': _empty,
  'reveal': _empty,
  'snapshot': _empty,
  'startExport': _empty,
  'cancelExport': _empty,
  'dismissExport': _empty,
  'clearCuts': _empty,
};

/// `montage.setFraming.follow.params.json` → `params` del método `setFraming`.
/// `montage.state.event.json` → `event` de `state`.
_Codec? _codecOf(String path) {
  final name = path.split('/').last.replaceFirst(RegExp(r'\.json$'), '');
  final parts = name.split('.');
  if (parts.length < 3 || parts.first != 'montage') return null;
  final method = parts[1];
  switch (parts.last) {
    case 'error':
      return _error;
    case 'event':
      return _events[method];
    case 'result':
      return _results[method] ?? _snapshot;
    case 'params':
      return _params[method];
    default:
      return null;
  }
}

bool _same(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_same(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_same(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

Future<Json> _load(String name) async {
  final source = await DirectoryFixtureSource.find();
  if (source == null) fail('No se encuentra Contract/fixtures');
  return jsonDecode(await source.read('montage/$name')) as Json;
}

void main() {
  test('cada fixture de montage tiene decodificador y reproduce sus campos', () async {
    final source = await DirectoryFixtureSource.find();
    if (source == null) fail('No se encuentra Contract/fixtures');
    final files = (await source.list()).where((p) => p.startsWith('montage/')).toList()..sort();
    expect(files, isNotEmpty);

    final missing = <String>[];
    final lost = <String>[];
    for (final path in files) {
      final codec = _codecOf(path);
      if (codec == null) {
        missing.add(path);
        continue;
      }
      final original = jsonDecode(await source.read(path)) as Json;
      if (!_same(original, codec(original))) lost.add(path);
    }
    expect(missing, isEmpty, reason: 'Fixtures sin decodificador asignado');
    expect(lost, isEmpty, reason: 'Campos perdidos al volver a codificar');
  });

  test('autoPartId solo aparece en layout single', () async {
    final single = MontageSnapshot.fromJson(await _load('montage.snapshot.single.result.json'));
    expect(single.layout, 'single');
    expect(single.autoPartId, '00000000-0000-0000-0000-000000000001');
    final normal = MontageSnapshot.fromJson(await _load('montage.snapshot.result.json'));
    expect(normal.autoPartId, isNull);
  });

  test('export running expone fase, progreso y stage', () async {
    final e = MontageExportEvent.fromJson(await _load('montage.export.running.event.json'));
    expect(e.phase, MontageExportPhase.running);
    expect(e.progress, 0.4);
    expect(e.stage, 'Codificando el vídeo');
    expect(e.result, isNull);
  });

  test('export done expone resultado con ruta absoluta', () async {
    final e = MontageExportEvent.fromJson(await _load('montage.export.done.event.json'));
    expect(e.phase, MontageExportPhase.done);
    expect(e.result?.path, startsWith('/'));
    expect(e.result?.codec, 'hevc');
  });

  test('framing ready y failed exponen status', () async {
    final ready = MontageFramingEvent.fromJson(await _load('montage.framing.ready.event.json'));
    expect(ready.status, MontageFramingStatus.ready);
    expect(ready.detected, 18);
    final failed = MontageFramingEvent.fromJson(await _load('montage.framing.failed.event.json'));
    expect(failed.status, MontageFramingStatus.failed);
    expect(failed.error, isNotNull);
  });

  test('position playing expone playing y tiempos', () async {
    final p = MontagePositionEvent.fromJson(await _load('montage.position.playing.event.json'));
    expect(p.playing, isTrue);
    expect(p.seconds, 4.5);
    expect(p.videoSeconds, 2);
  });

  test('preview videos: con y sin progress, vuelta sin pérdida', () {
    final Json json = {
      'phase': 'preparing',
      'audio': {'phase': 'none', 'progress': 0},
      'fps': 30,
      'maxDimension': 720,
      'width': 1280,
      'height': 720,
      'delivered': 0,
      'skipped': 0,
      'lastFrameMillis': 0,
      'frameP50Ms': 0,
      'frameP95Ms': 0,
      'videos': [
        {'code': 'video-converting', 'takeId': 'take-1', 'jobId': 'job-1', 'progress': 0.5, 'message': 'Convirtiendo'},
        {'code': 'video-failed', 'takeId': 'take-2', 'jobId': 'job-2', 'message': 'Error al convertir'},
      ],
    };
    final preview = MontagePreviewInfo.fromJson(json);
    expect(preview.videos, hasLength(2));
    expect(preview.videos[0].progress, 0.5);
    expect(preview.videos[1].progress, isNull);
    expect(_same(json, preview.toJson()), isTrue);
  });
}
