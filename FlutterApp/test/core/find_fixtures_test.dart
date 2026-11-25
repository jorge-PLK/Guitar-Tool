import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_providers.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('tf_fixtures'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('prueba los directorios de partida en orden y sube hasta Contract/fixtures', () async {
    final repo = Directory('${tmp.path}/repo')..createSync();
    Directory('${repo.path}/Contract/fixtures').createSync(recursive: true);
    final exeDir = Directory('${repo.path}/FlutterApp/build/x')..createSync(recursive: true);
    final empty = Directory('${tmp.path}/otro')..createSync();

    final found = await findRepoFixtures([empty, exeDir]);
    expect(found, isNotNull);
    expect(found!.root.path, '${repo.path}/Contract/fixtures');
  });

  test('null si ninguno lo contiene', () async {
    final empty = Directory('${tmp.path}/otro')..createSync();
    // Subiendo desde tmp puede haber un Contract/fixtures ajeno solo si el repo lo contiene: no es el caso.
    expect(await findRepoFixtures([]), isNull);
    expect(empty.existsSync(), isTrue);
  });
}
