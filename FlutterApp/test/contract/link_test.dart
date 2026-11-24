import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/link.dart';
import 'package:toneforge/core/core_client.dart' show Json;
import 'package:toneforge/core/mock_core.dart';

Future<Json> _fixture(String name) async {
  final source = await DirectoryFixtureSource.find();
  if (source == null) {
    fail('No encuentro Contract/fixtures subiendo desde el cwd');
  }
  return jsonDecode(await source.read('link/$name')) as Json;
}

void _roundTrip<T>(
  String name,
  T Function(Json) fromJson,
  Json Function(T) toJson,
) {
  test('$name: decodifica y codifica sin perder campos', () async {
    final json = await _fixture(name);
    expect(toJson(fromJson(json)), equals(json));
  });
}

void main() {
  group('contract link', () {
    _roundTrip(
      'link.classify.playlist.params.json',
      LinkURLParams.fromJson,
      (p) => p.toJson(),
    );
    _roundTrip(
      'link.classify.playlist.result.json',
      LinkClassifyResult.fromJson,
      (r) => r.toJson(),
    );
    _roundTrip(
      'link.classify.track.params.json',
      LinkURLParams.fromJson,
      (p) => p.toJson(),
    );
    _roundTrip(
      'link.classify.track.result.json',
      LinkClassifyResult.fromJson,
      (r) => r.toJson(),
    );
    _roundTrip(
      'link.classify.unsupported.params.json',
      LinkURLParams.fromJson,
      (p) => p.toJson(),
    );
    _roundTrip(
      'link.classify.unsupported.result.json',
      LinkClassifyResult.fromJson,
      (r) => r.toJson(),
    );
    _roundTrip(
      'link.resolve.params.json',
      LinkURLParams.fromJson,
      (p) => p.toJson(),
    );
    _roundTrip(
      'link.resolve.result.json',
      LinkResolveResult.fromJson,
      (r) => r.toJson(),
    );
    _roundTrip(
      'link.resolve.youtube.params.json',
      LinkURLParams.fromJson,
      (p) => p.toJson(),
    );
    _roundTrip(
      'link.resolve.youtube.result.json',
      LinkResolveResult.fromJson,
      (r) => r.toJson(),
    );
    _roundTrip(
      'link.resolve.playlist.params.json',
      LinkURLParams.fromJson,
      (p) => p.toJson(),
    );
    _roundTrip(
      'link.resolve.playlist.result.json',
      LinkResolveResult.fromJson,
      (r) => r.toJson(),
    );
    _roundTrip(
      'link.search.params.json',
      LinkSearchParams.fromJson,
      (p) => p.toJson(),
    );
    _roundTrip(
      'link.search.result.json',
      LinkSearchResult.fromJson,
      (r) => r.toJson(),
    );
    _roundTrip(
      'link.addManual.params.json',
      LinkAddManualParams.fromJson,
      (p) => p.toJson(),
    );
    _roundTrip(
      'link.addManual.result.json',
      LinkAddManualResult.fromJson,
      (r) => r.toJson(),
    );
    _roundTrip(
      'link.cancel.params.json',
      LinkCancelParams.fromJson,
      (p) => p.toJson(),
    );
    _roundTrip(
      'link.cancel.result.json',
      CancelledResult.fromJson,
      (r) => r.toJson(),
    );
    _roundTrip(
      'link.cancel.noJob.params.json',
      LinkCancelParams.fromJson,
      (p) => p.toJson(),
    );
    _roundTrip(
      'link.cancel.noJob.result.json',
      CancelledResult.fromJson,
      (r) => r.toJson(),
    );
    _roundTrip(
      'link.import.params.json',
      LinkImportParams.fromJson,
      (p) => p.toJson(),
    );
    _roundTrip(
      'link.import.result.json',
      LinkJobResult.fromJson,
      (r) => r.toJson(),
    );
    _roundTrip(
      'link.finished.ok.event.json',
      LinkFinished.fromJson,
      (e) => e.toJson(),
    );
    _roundTrip(
      'link.finished.duplicate.event.json',
      LinkFinished.fromJson,
      (e) => e.toJson(),
    );
    _roundTrip(
      'link.finished.error.event.json',
      LinkFinished.fromJson,
      (e) => e.toJson(),
    );

    test('link.cancel.noJob.params: {} da jobId nulo y sale vacío', () async {
      final json = await _fixture('link.cancel.noJob.params.json');
      final params = LinkCancelParams.fromJson(json);
      expect(params.jobId, isNull);
      expect(params.toJson(), isEmpty);
    });

    test('link.resolve.playlist: playlist se conserva como Json crudo', () async {
      final json = await _fixture('link.resolve.playlist.result.json');
      final result = LinkResolveResult.fromJson(json);
      expect(result.link, LinkResolveKind.playlist);
      expect(result.candidates, isEmpty);
      expect(result.playlist?['kind'], 'playlist');
    });

    test('link.resolve.result: inLibrary y difference llegan tipados', () async {
      final json = await _fixture('link.resolve.result.json');
      final first = LinkResolveResult.fromJson(json).candidates.first;
      expect(first.isClose, isTrue);
      expect(first.inLibrary?.title, 'Versión en directo');
      expect(first.difference, closeTo(-0.8, 1e-9));
    });

    test('link.finished.error: error.code y sin id', () async {
      final json = await _fixture('link.finished.error.event.json');
      final event = LinkFinished.fromJson(json);
      expect(event.id, isNull);
      expect(event.error?.code, 'private-video');
    });

    test('valores no previstos caen en unknown', () {
      expect(
        LinkClassifyResult.fromJson(const {'kind': 'x', 'source': 'y'}).kind,
        LinkKind.unknown,
      );
      expect(
        LinkClassifyResult.fromJson(const {'kind': 'x', 'source': 'y'}).source,
        LinkSource.unknown,
      );
      expect(
        LinkResolveResult.fromJson(const {
          'link': 'vimeo',
          'pastedURL': '',
          'title': '',
          'noCloseCandidate': false,
          'candidates': <Object?>[],
        }).link,
        LinkResolveKind.unknown,
      );
    });
  });
}
