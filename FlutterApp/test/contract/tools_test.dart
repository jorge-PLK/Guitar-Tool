import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/tools.dart';
import 'package:toneforge/core/core_client.dart' show Json;
import 'package:toneforge/core/mock_core.dart';

Future<Json> _fixture(String name) async {
  final source = await DirectoryFixtureSource.find();
  if (source == null) {
    fail('No encuentro Contract/fixtures subiendo desde el cwd');
  }
  return jsonDecode(await source.read('tools/$name')) as Json;
}

void main() {
  group('contract tools', () {
    test('tools.info.params: Empty, sale {}', () async {
      expect(await _fixture('tools.info.params.json'), isEmpty);
    });

    test('tools.info.result: decodifica y codifica sin perder campos', () async {
      final json = await _fixture('tools.info.result.json');
      final result = ToolsInfoResult.fromJson(json);
      expect(result.ytDlpOrigin, YtDlpOrigin.embedded);
      expect(result.toJson(), equals(json));
    });

    test('tools.info.updated.params: Empty, sale {}', () async {
      expect(await _fixture('tools.info.updated.params.json'), isEmpty);
    });

    test(
      'tools.info.updated.result: decodifica y codifica sin perder campos',
      () async {
        final json = await _fixture('tools.info.updated.result.json');
        final result = ToolsInfoResult.fromJson(json);
        expect(result.ytDlpOrigin, YtDlpOrigin.updated);
        expect(result.ytDlpVersion, '2026.11.01');
        expect(result.toJson(), equals(json));
      },
    );

    test('tools.updateYtDlp.params: Empty, sale {}', () async {
      expect(await _fixture('tools.updateYtDlp.params.json'), isEmpty);
    });

    test(
      'tools.updateYtDlp.result: decodifica y codifica sin perder campos',
      () async {
        final json = await _fixture('tools.updateYtDlp.result.json');
        final result = UpdateYtDlpResult.fromJson(json);
        expect(result.alreadyLatest, isFalse);
        expect(result.origin, YtDlpOrigin.updated);
        expect(result.toJson(), equals(json));
      },
    );

    test('tools.revertYtDlp.params: Empty, sale {}', () async {
      expect(await _fixture('tools.revertYtDlp.params.json'), isEmpty);
    });

    test(
      'tools.revertYtDlp.result: decodifica y codifica sin perder campos',
      () async {
        final json = await _fixture('tools.revertYtDlp.result.json');
        expect(RevertedResult.fromJson(json).reverted, isTrue);
        expect(RevertedResult.fromJson(json).toJson(), equals(json));
      },
    );

    test('origen de yt-dlp no previsto cae en unknown', () {
      final info = ToolsInfoResult.fromJson(const {'ytDlpOrigin': 'pip'});
      expect(info.ytDlpOrigin, YtDlpOrigin.unknown);
      expect(info.toJson(), const {'ytDlpOrigin': 'unknown'});
    });
  });
}
