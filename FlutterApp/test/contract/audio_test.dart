import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/audio.dart';
import 'package:toneforge/core/core_client.dart' show Json;
import 'package:toneforge/core/mock_core.dart' show DirectoryFixtureSource;

Future<Json> _load(String rel) async {
  final src = await DirectoryFixtureSource.find();
  expect(src, isNotNull, reason: 'no encuentro Contract/fixtures');
  return jsonDecode(await src!.read(rel)) as Json;
}

/// En resultados, ausente y `null` son lo mismo: se quitan los `null` de ambos lados.
Object? _strip(Object? v) => switch (v) {
      Map() => {
          for (final e in v.entries)
            if (e.value != null) e.key: _strip(e.value),
        },
      List() => [for (final e in v) _strip(e)],
      _ => v,
    };

void _result(String name, Json Function(Json) roundTrip) {
  test('$name decodifica y recodifica sin perder campos', () async {
    final json = await _load('audio/$name.json');
    expect(_strip(roundTrip(json)), equals(_strip(json)));
  });
}

void _params(String name, Json Function(Json) roundTrip) {
  test('$name recodifica igual (params exactos)', () async {
    final json = await _load('audio/$name.json');
    expect(roundTrip(json), equals(json));
  });
}

void main() {
  group('AudioSettings', () {
    for (final n in [
      'audio.settings.result',
      'audio.settings.ratemismatch.result',
      'audio.settings.noinput.result',
      'audio.settings.calibrated.result',
      'audio.settings.disconnected.result',
      'audio.setSettings.result',
      'audio.setSettings.guitarabsent.result',
      'audio.setSettings.guitarnull.result',
      'audio.setSettings.outputnull.result',
    ]) {
      _result(n, (j) => AudioSettings.fromJson(j).toJson());
    }
  });

  group('AudioState', () {
    for (final n in [
      'audio.state.result',
      'audio.state.event',
      'audio.state.calibrated.result',
      'audio.state.disconnected.result',
      'audio.state.noinput.result',
      'audio.state.ratemismatch.result',
      'audio.setMeters.result',
      'audio.setMeters.hidden.result',
      'audio.setMeters.visibleforerror.result',
    ]) {
      _result(n, (j) => AudioState.fromJson(j).toJson());
    }
  });

  group('AudioDevices', () {
    for (final n in ['audio.devices.result', 'audio.devicesChanged.event']) {
      _result(n, (j) => AudioDevices.fromJson(j).toJson());
    }
  });

  group('AudioLevels', () {
    for (final n in ['audio.levels.event', 'audio.levels.nolevels.event']) {
      _result(n, (j) => AudioLevels.fromJson(j).toJson());
    }
  });

  group('AudioCalibrationState', () {
    for (final n in [
      'audio.calibrate.result',
      'audio.calibrate.failure.result',
      'audio.calibrate.error.result',
      'audio.calibration.idle.event',
      'audio.calibration.running.event',
      'audio.calibration.success.event',
      'audio.calibration.failure.event',
      'audio.calibration.error.event',
      'audio.cancelCalibration.result',
      'audio.dismissCalibration.result',
    ]) {
      _result(n, (j) => AudioCalibrationState.fromJson(j).toJson());
    }
  });

  group('AudioSetSettingsParams', () {
    for (final n in [
      'audio.setSettings.params',
      'audio.setSettings.guitarabsent.params',
      'audio.setSettings.guitarnull.params',
      'audio.setSettings.outputnull.params',
      'audio.setSettings.badchannels.params',
      'audio.setSettings.badrate.params',
    ]) {
      _params(n, (j) => AudioSetSettingsParams.fromJson(j).toJson());
    }
  });

  group('AudioSetMetersParams', () {
    for (final n in [
      'audio.setMeters.params',
      'audio.setMeters.hidden.params',
      'audio.setMeters.visibleforerror.params',
    ]) {
      _params(n, (j) => AudioSetMetersParams.fromJson(j).toJson());
    }
  });
}
