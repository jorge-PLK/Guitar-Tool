import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/models.dart';
import 'package:toneforge/core/core_client.dart' show Json;
import 'package:toneforge/core/mock_core.dart';

Future<Json> _fixture(String name) async {
  final source = await DirectoryFixtureSource.find();
  if (source == null) {
    fail('No encuentro Contract/fixtures subiendo desde el cwd');
  }
  return jsonDecode(await source.read('models/$name')) as Json;
}

void main() {
  group('contract models', () {
    test('models.list.params: Empty, sale {}', () async {
      expect(await _fixture('models.list.params.json'), isEmpty);
    });

    test('models.list.result: decodifica y codifica sin perder campos',
        () async {
      final json = await _fixture('models.list.result.json');
      final result = ModelsListResult.fromJson(json);
      expect(result.models.single.state, ModelState.notInstalled);
      expect(result.models.single.source, isNull);
      expect(result.toJson(), equals(json));
    });

    test(
      'models.list.downloading.result: decodifica y codifica sin perder campos',
      () async {
        final json = await _fixture('models.list.downloading.result.json');
        final result = ModelsListResult.fromJson(json);
        expect(result.models.single.state, ModelState.downloading);
        expect(result.models.single.fraction, 0.25);
        expect(result.toJson(), equals(json));
      },
    );

    test(
      'models.list.failed.result: decodifica y codifica sin perder campos',
      () async {
        final json = await _fixture('models.list.failed.result.json');
        final result = ModelsListResult.fromJson(json);
        expect(result.models.single.state, ModelState.failed);
        expect(result.models.single.message, isNotNull);
        expect(result.toJson(), equals(json));
      },
    );

    test(
      'models.list.installed.result: decodifica y codifica sin perder campos',
      () async {
        final json = await _fixture('models.list.installed.result.json');
        final result = ModelsListResult.fromJson(json);
        expect(result.models.single.state, ModelState.installed);
        expect(result.models.single.source, ModelSource.store);
        expect(result.modelsBytes, 123456789);
        expect(result.toJson(), equals(json));
      },
    );

    test('models.download.params: sin id, sale {}', () async {
      final json = await _fixture('models.download.params.json');
      final params = ModelIDParams.fromJson(json);
      expect(params.id, isNull);
      expect(params.toJson(), equals(json));
    });

    test('models.download.result: decodifica y codifica sin perder campos',
        () async {
      final json = await _fixture('models.download.result.json');
      expect(ModelsDownloadResult.fromJson(json).started, isTrue);
      expect(ModelsDownloadResult.fromJson(json).toJson(), equals(json));
    });

    test('models.delete.params: decodifica y codifica sin perder campos',
        () async {
      final json = await _fixture('models.delete.params.json');
      final params = ModelIDParams.fromJson(json);
      expect(params.id, 'otro');
      expect(params.toJson(), equals(json));
    });

    test('models.delete.busy.params: sin id, sale {}', () async {
      final json = await _fixture('models.delete.busy.params.json');
      expect(ModelIDParams.fromJson(json).toJson(), equals(json));
    });

    test('models.delete.error: decodifica y codifica sin perder campos',
        () async {
      final json = await _fixture('models.delete.error.json');
      expect(ModelError.fromJson(json).code, 'not-found');
      expect(ModelError.fromJson(json).toJson(), equals(json));
    });

    test('models.delete.busy.error: decodifica y codifica sin perder campos',
        () async {
      final json = await _fixture('models.delete.busy.error.json');
      expect(ModelError.fromJson(json).code, 'busy');
      expect(ModelError.fromJson(json).toJson(), equals(json));
    });

    test('models.progress.event: decodifica y codifica sin perder campos',
        () async {
      final json = await _fixture('models.progress.event.json');
      final event = ModelProgress.fromJson(json);
      expect(event.fraction, 0.25);
      expect(event.toJson(), equals(json));
    });

    test('models.changed.event: decodifica y codifica sin perder campos',
        () async {
      final json = await _fixture('models.changed.event.json');
      final event = ModelsChanged.fromJson(json);
      expect(event.error?.code, 'model-failed');
      expect(event.toJson(), equals(json));
    });

    test('models.changed.ok.event: error null se conserva', () async {
      final json = await _fixture('models.changed.ok.event.json');
      final event = ModelsChanged.fromJson(json);
      expect(event.error, isNull);
      expect(event.toJson(), equals(json));
    });

    test('estado no previsto cae en unknown y conserva el crudo', () {
      const json = {
        'archiveBytes': 1,
        'bytes': null,
        'fraction': null,
        'id': 'x',
        'message': null,
        'name': 'X',
        'source': null,
        'state': 'pausado',
      };
      final entry = ModelEntry.fromJson(json);
      expect(entry.state, ModelState.unknown);
      expect(entry.toJson(), equals(json));
    });

    test('origen no previsto cae en unknown y conserva el crudo', () {
      const json = {
        'archiveBytes': 1,
        'bytes': null,
        'fraction': null,
        'id': 'x',
        'message': null,
        'name': 'X',
        'source': 'pirata',
        'state': 'installed',
      };
      final entry = ModelEntry.fromJson(json);
      expect(entry.source, ModelSource.unknown);
      expect(entry.toJson(), equals(json));
    });
  });
}
