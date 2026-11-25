import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/host_folders.dart';
import 'package:toneforge/core/core_client.dart' show Json;
import 'package:toneforge/core/mock_core.dart';

// `host.chooseFolder` lee su fixture de Contract/fixtures/host/; el resto, JSON en línea según
// ImportMethods.swift (la clave `path` siempre sale, `null` si se cancela).
void main() {
  group('contract host folders', () {
    test('host.pickProjectsFolder: con carpeta, codifica sin perder campos', () {
      const json = {'path': '/Users/x/Projects', 'restartRequired': true};
      final result = PickedFolderResult.fromJson(json);
      expect(result.path, '/Users/x/Projects');
      expect(result.restartRequired, isTrue);
      expect(result.toJson(), equals(json));
    });

    test('host.pickProjectsFolder: cancelado, path null explícito', () {
      const json = {'path': null, 'restartRequired': false};
      final result = PickedFolderResult.fromJson(json);
      expect(result.path, isNull);
      expect(result.toJson(), equals(json));
    });

    test('host.chooseFolder: con carpeta, codifica sin perder campos', () {
      const json = {'path': '/Volumes/Discos/Biblioteca'};
      final result = ChosenFolderResult.fromJson(json);
      expect(result.path, '/Volumes/Discos/Biblioteca');
      expect(result.toJson(), equals(json));
    });

    test('host.chooseFolder: fixture result.json', () async {
      final source = await DirectoryFixtureSource.find();
      if (source == null) {
        fail('No encuentro Contract/fixtures subiendo desde el cwd');
      }
      final json =
          jsonDecode(await source.read('host/host.chooseFolder.result.json'))
              as Json;
      final result = ChosenFolderResult.fromJson(json);
      expect(result.path, '/Users/example/Music/ToneForge');
      expect(result.toJson(), equals(json));
    });

    test('host.chooseFolder: cancelado, path null explícito', () {
      const json = {'path': null};
      final result = ChosenFolderResult.fromJson(json);
      expect(result.path, isNull);
      expect(result.toJson(), equals(json));
    });
  });
}
