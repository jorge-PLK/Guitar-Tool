import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/host_pickers.dart';
import 'package:toneforge/core/core_client.dart' show Json;
import 'package:toneforge/core/mock_core.dart';

Future<Json> _fixture(String name) async {
  final source = await DirectoryFixtureSource.find();
  if (source == null) {
    fail('No encuentro Contract/fixtures subiendo desde el cwd');
  }
  return jsonDecode(await source.read('host/$name')) as Json;
}

void main() {
  group('contract host pickers', () {
    test(
      'host.pickAudioFiles.result: decodifica y codifica sin perder campos',
      () async {
        final json = await _fixture('host.pickAudioFiles.result.json');
        expect(PickedFilesResult.fromJson(json).paths, hasLength(2));
        expect(PickedFilesResult.fromJson(json).toJson(), equals(json));
      },
    );

    test(
      'host.openURL.params: decodifica y codifica sin perder campos',
      () async {
        final json = await _fixture('host.openURL.params.json');
        expect(OpenURLParams.fromJson(json).toJson(), equals(json));
      },
    );

    test(
      'host.openURL.result: decodifica y codifica sin perder campos',
      () async {
        final json = await _fixture('host.openURL.result.json');
        expect(OpenURLResult.fromJson(json).toJson(), equals(json));
      },
    );

    test('OpenURLResult sin opened: omite la clave', () {
      expect(const OpenURLResult().toJson(), isEmpty);
    });
  });
}
