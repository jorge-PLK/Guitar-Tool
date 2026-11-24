import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/host_folders.dart';

// Sin fixture de resultado en Contract/fixtures/host/: JSON en línea según
// ImportMethods.swift:91-107 (la clave `path` siempre sale, `null` si se cancela).
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

    test('host.chooseFolder: cancelado, path null explícito', () {
      const json = {'path': null};
      final result = ChosenFolderResult.fromJson(json);
      expect(result.path, isNull);
      expect(result.toJson(), equals(json));
    });
  });
}
