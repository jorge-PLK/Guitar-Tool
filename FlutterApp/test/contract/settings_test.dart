import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/settings.dart';
import 'package:toneforge/core/core_client.dart' show Json;
import 'package:toneforge/core/mock_core.dart';

Future<Json> _fixture(String name) async {
  final source = await DirectoryFixtureSource.find();
  if (source == null) {
    fail('No encuentro Contract/fixtures subiendo desde el cwd');
  }
  return jsonDecode(await source.read('settings/$name')) as Json;
}

void main() {
  group('contract settings', () {
    test('settings.get.params: Empty, sale {}', () async {
      expect(await _fixture('settings.get.params.json'), isEmpty);
    });

    test('settings.get.result: decodifica y codifica sin perder campos',
        () async {
      final json = await _fixture('settings.get.result.json');
      final result = SettingsGetResult.fromJson(json);
      expect(result.projectsFolder, isNull);
      expect(result.activeProjectsFolder, '/<dir>/Projects');
      expect(result.video['noCamera'], isTrue);
      expect(result.toJson(), equals(json));
    });
  });
}
