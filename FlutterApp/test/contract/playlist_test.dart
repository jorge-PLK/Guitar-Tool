import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/link_resolve.dart';
import 'package:toneforge/contract/playlist.dart';
import 'package:toneforge/core/core_client.dart' show CoreError, Json;
import 'package:toneforge/core/mock_core.dart';

Future<Json> _fixtureAt(String path) async {
  final source = await DirectoryFixtureSource.find();
  if (source == null) {
    fail('No encuentro Contract/fixtures subiendo desde el cwd');
  }
  return jsonDecode(await source.read(path)) as Json;
}

Future<Json> _fixture(String name) => _fixtureAt('playlist/$name');

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

void _coreError(String name) {
  test('$name: CoreError lee code y message', () async {
    final json = await _fixture(name);
    final error = CoreError.fromJson(json);
    expect(error.code, json['code']);
    expect(error.message, json['message']);
  });
}

void main() {
  group('contract playlist', () {
    // Resultados que son PlaylistSnapshot (también AppInfo.playlist).
    for (final name in const [
      'playlist.state.result.json',
      'playlist.select.result.json',
      'playlist.select.a.result.json',
      'playlist.select.b.result.json',
      'playlist.selectAll.result.json',
      'playlist.selectNone.result.json',
      'playlist.choose.result.json',
      'playlist.choose.b.result.json',
      'playlist.skip.result.json',
      'playlist.continue.result.json',
      'playlist.search.result.json',
      'playlist.start.result.json',
      'playlist.cancel.result.json',
      'playlist.resume.result.json',
      'playlist.updateAndRetry.result.json',
      'playlist.retryFailed.result.json',
    ]) {
      _roundTrip(name, PlaylistSnapshot.fromJson, (s) => s.toJson());
    }

    // Eventos playlist.changed: un fichero por step.
    for (final name in const [
      'playlist.changed.loading.event.json',
      'playlist.changed.tracks.event.json',
      'playlist.changed.searching.event.json',
      'playlist.changed.review.event.json',
      'playlist.changed.running.event.json',
      'playlist.changed.stopped.event.json',
      'playlist.changed.summary.event.json',
      'playlist.changed.error.event.json',
    ]) {
      _roundTrip(name, PlaylistSnapshot.fromJson, (s) => s.toJson());
    }

    // playlist.close devuelve PlaylistCloseResult, no PlaylistSnapshot.
    for (final name in const [
      'playlist.close.force.result.json',
      'playlist.close.live.result.json',
      'playlist.close.none.result.json',
    ]) {
      _roundTrip(name, PlaylistCloseResult.fromJson, (r) => r.toJson());
    }

    // Params (Empty no tiene DTO: sus ficheros son {}).
    for (final name in const [
      'playlist.select.params.json',
      'playlist.select.a.params.json',
      'playlist.select.b.params.json',
    ]) {
      _roundTrip(name, PlaylistSelectParams.fromJson, (p) => p.toJson());
    }
    for (final name in const [
      'playlist.choose.params.json',
      'playlist.choose.b.params.json',
      'playlist.choose.error.params.json',
    ]) {
      _roundTrip(name, PlaylistChooseParams.fromJson, (p) => p.toJson());
    }
    _roundTrip(
      'playlist.skip.params.json',
      PlaylistItemParams.fromJson,
      (p) => p.toJson(),
    );
    _roundTrip(
      'playlist.skip.error.params.json',
      PlaylistItemParams.fromJson,
      (p) => p.toJson(),
    );
    for (final name in const [
      'playlist.close.force.params.json',
      'playlist.close.live.params.json',
      'playlist.close.none.params.json',
    ]) {
      _roundTrip(name, PlaylistCloseParams.fromJson, (p) => p.toJson());
    }

    // Errores del núcleo {code, message}: se decodifican con CoreError.
    for (final name in const [
      'playlist.choose.error.error.json',
      'playlist.skip.error.error.json',
      'playlist.start.noPlaylist.error.json',
      'playlist.state.noPlaylist.error.json',
    ]) {
      _coreError(name);
    }

    test('link.resolve.playlist: playlistSnapshot decodifica el campo crudo',
        () async {
      final json = await _fixtureAt('link/link.resolve.playlist.result.json');
      final snapshot = LinkResolveResult.fromJson(json).playlistSnapshot;
      expect(snapshot, isNotNull);
      expect(snapshot!.step, PlaylistStep.tracks);
      expect(snapshot.items, hasLength(3));
      expect(snapshot.toJson(), equals(json['playlist']));
    });

    test('link.resolve sin playlist: playlistSnapshot es nulo', () async {
      final json = await _fixtureAt('link/link.resolve.youtube.result.json');
      expect(LinkResolveResult.fromJson(json).playlistSnapshot, isNull);
    });

    test('valores no previstos caen en unknown', () {
      expect(PlaylistStep.fromRaw('x'), PlaylistStep.unknown);
      expect(PlaylistSource.fromRaw('x'), PlaylistSource.unknown);
      expect(PlaylistKind.fromRaw('x'), PlaylistKind.unknown);
      expect(PlaylistItemStatus.fromRaw('x'), PlaylistItemStatus.unknown);
      expect(PlaylistItemStage.fromRaw('x'), PlaylistItemStage.unknown);
    });
  });
}
