import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/core/core_client.dart' show Json;
import 'package:toneforge/core/mock_core.dart';

Future<Json> _fixture(String name) async {
  final source = await DirectoryFixtureSource.find();
  if (source == null) {
    fail('No encuentro Contract/fixtures subiendo desde el cwd');
  }
  return jsonDecode(await source.read('library/$name')) as Json;
}

void main() {
  group('contract library detail', () {
    test(
      'library.project.result: decodifica y codifica sin perder campos',
      () async {
        final json = await _fixture('library.project.result.json');
        final result = ProjectDetailResult.fromJson(json);
        expect(result.stems.first.kind, StemKind.bass);
        expect(result.parts, hasLength(2));
        expect(result.parts.first.takes[1].isBest, isTrue);
        expect(result.parts.first.takes[1].punches.single.videoOffsetMs, 50);
        expect(result.parts.last.isLead, isTrue);
        expect(result.videoCount, 0);
        expect(result.toJson(), equals(json));
      },
    );

    test(
      'library.deleteTake.params: decodifica y codifica sin perder campos',
      () async {
        final json = await _fixture('library.deleteTake.params.json');
        expect(DeleteTakeParams.fromJson(json).toJson(), equals(json));
      },
    );

    test(
      'library.markBest.params: decodifica y codifica sin perder campos',
      () async {
        final json = await _fixture('library.markBest.params.json');
        expect(MarkBestParams.fromJson(json).toJson(), equals(json));
      },
    );
  });
}
