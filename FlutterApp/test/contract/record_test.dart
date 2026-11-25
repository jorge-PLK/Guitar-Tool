import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/record.dart';
import 'package:toneforge/core/core_client.dart' show CoreError, Json;
import 'package:toneforge/core/mock_core.dart';

/// Decodifica con la clase del DTO y vuelve a codificar; el resultado debe igualar al fixture.
typedef _Codec = Json Function(Json j);

Json _snapshot(Json j) => RecordSnapshot.fromJson(j).toJson();
Json _position(Json j) => RecordPositionEvent.fromJson(j).toJson();
Json _levels(Json j) => RecordLevelsEvent.fromJson(j).toJson();
Json _allowed(Json j) => RecordAllowedResult.fromJson(j).toJson();
Json _empty(Json j) => RecordEmptyParams.fromJson(j).toJson();
Json _takeParams(Json j) => RecordTakeParams.fromJson(j).toJson();
Json _error(Json j) {
  final e = CoreError.fromJson(j);
  return {'code': e.code, 'message': e.message};
}

const _snapshotResults = [
  'record.addPart',
  'record.adjustOffset',
  'record.deleteTake',
  'record.finishOffset',
  'record.markBest',
  'record.open',
  'record.pollCamera',
  'record.rotate',
  'record.selectPart',
  'record.selectTake',
  'record.setCamera',
  'record.setCountIn',
  'record.setMaster',
  'record.setMix',
  'record.setOffset',
  'record.setPreRoll',
  'record.setPunch',
  'record.setStartSection',
  'record.state',
];

/// Clave `<método|evento>.<params|result|event|error>` → decodificador. Sin entrada = hueco.
final Map<String, _Codec> _codecs = {
  for (final m in _snapshotResults) '$m.result': _snapshot,
  'record.state.event': _snapshot,
  'record.position.event': _position,
  'record.levels.event': _levels,
  'record.prepareViewTake.result': _allowed,
  'record.adjustOffset.error': _error,
  'record.addPart.params': (j) => RecordAddPartParams.fromJson(j).toJson(),
  'record.adjustOffset.params': _takeParams,
  'record.deleteTake.params': _takeParams,
  'record.finishOffset.params': (j) => RecordFinishOffsetParams.fromJson(j).toJson(),
  'record.markBest.params': _takeParams,
  'record.open.params': (j) => RecordOpenParams.fromJson(j).toJson(),
  'record.pollCamera.params': _empty,
  'record.selectPart.params': (j) => RecordPartParams.fromJson(j).toJson(),
  'record.selectTake.params': _takeParams,
  'record.setCamera.params': (j) => RecordCameraParams.fromJson(j).toJson(),
  'record.setCountIn.params': (j) => RecordOnParams.fromJson(j).toJson(),
  'record.setMaster.params': (j) => RecordMasterParams.fromJson(j).toJson(),
  'record.setMix.params': (j) => RecordMixParams.fromJson(j).toJson(),
  'record.setOffset.params': (j) => RecordOffsetParams.fromJson(j).toJson(),
  'record.setPreRoll.params': (j) => RecordBarsParams.fromJson(j).toJson(),
  'record.setPunch.params': (j) => RecordPunchParams.fromJson(j).toJson(),
  'record.setStartSection.params': (j) => RecordSectionParams.fromJson(j).toJson(),
  'record.state.params': _empty,
  'record.prepareViewTake.params': _empty,
  'record.rotate.params': _empty,
  'record.start.params': _empty,
  'record.startPunch.params': _takeParams,
  'record.stop.params': _empty,
  'record.cancel.params': _empty,
  'record.close.params': _empty,
};

/// `record.setPunch.clear.params.json` → `record.setPunch.params`; `record.state.idle.event.json` → `record.state.event`.
String? _keyOf(String path) {
  final name = path.split('/').last.replaceFirst(RegExp(r'\.json$'), '');
  final parts = name.split('.');
  if (parts.length < 3) return null;
  return '${parts[0]}.${parts[1]}.${parts.last}';
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

void main() {
  test('cada fixture de record tiene decodificador y reproduce sus campos', () async {
    final source = await DirectoryFixtureSource.find();
    if (source == null) fail('No se encuentra Contract/fixtures');
    final files = (await source.list()).where((p) => p.startsWith('record/')).toList()..sort();
    expect(files, isNotEmpty);

    final missing = <String>[];
    final lost = <String>[];
    for (final path in files) {
      final key = _keyOf(path);
      final codec = key == null ? null : _codecs[key];
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

  test('block del snapshot expone el código del bloqueo', () async {
    final source = await DirectoryFixtureSource.find();
    if (source == null) fail('No se encuentra Contract/fixtures');
    final json = jsonDecode(await source.read('record/record.state.punch-armed-no-marks.event.json')) as Json;
    expect(RecordSnapshot.fromJson(json).block?.code, 'record-block-punch-no-marks');
  });

  test('record.state.adjusting expone offset no nulo', () async {
    final source = await DirectoryFixtureSource.find();
    if (source == null) fail('No se encuentra Contract/fixtures');
    final json = jsonDecode(await source.read('record/record.state.adjusting.event.json')) as Json;
    expect(RecordSnapshot.fromJson(json).offset, isNotNull);
  });
}
