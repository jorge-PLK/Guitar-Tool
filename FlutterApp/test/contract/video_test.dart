import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/video.dart';
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
    final json = await _load('video/$name.json');
    expect(_strip(roundTrip(json)), equals(_strip(json)));
  });
}

void _params(String name, Json Function(Json) roundTrip) {
  test('$name recodifica igual (params exactos)', () async {
    final json = await _load('video/$name.json');
    expect(roundTrip(json), equals(json));
  });
}

void main() {
  group('VideoCameras', () {
    for (final n in [
      'video.cameras.result',
      'video.cameras.nocamera.result',
      'video.cameras.disconnected.result',
    ]) {
      _result(n, (j) => VideoCameras.fromJson(j).toJson());
    }
  });

  group('VideoSettings', () {
    for (final n in [
      'video.settings.result',
      'video.settings.nocamera.result',
      'video.settings.disconnected.result',
      'video.setSettings.result',
      'video.setSettings.camera.result',
      'video.setSettings.cameraabsent.result',
      'video.setSettings.cameranull.result',
      'video.setSettings.export.result',
    ]) {
      _result(n, (j) => VideoSettings.fromJson(j).toJson());
    }
  });

  group('CameraPreviewResult', () {
    for (final n in [
      'video.preview.start.live.result',
      'video.preview.start.idle.result',
      'video.preview.start.denied.result',
      'video.preview.start.failed.result',
      'video.preview.start.nocamera.result',
      'video.preview.start.simulated.result',
      'video.preview.start.stopfirst.result',
      'video.preview.stop.result',
    ]) {
      _result(n, (j) => CameraPreviewResult.fromJson(j).toJson());
    }
  });

  group('VideoSetSettingsParams', () {
    for (final n in [
      'video.setSettings.params',
      'video.setSettings.camera.params',
      'video.setSettings.cameraabsent.params',
      'video.setSettings.cameranull.params',
      'video.setSettings.export.params',
      'video.setSettings.badresolution.params',
    ]) {
      _params(n, (j) => VideoSetSettingsParams.fromJson(j).toJson());
    }
  });

  group('VideoOpenCameraPrivacyResult', () {
    _result(
      'video.openCameraPrivacy.result',
      (j) => VideoOpenCameraPrivacyResult.fromJson(j).toJson(),
    );
  });
}
