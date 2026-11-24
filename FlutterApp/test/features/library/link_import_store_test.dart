import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/library/link_import_store.dart';

Json cand(String id, {bool close = false, double? diff, String? lib}) => {
  'id': id,
  'title': 'Vídeo $id',
  'source': 'youtube',
  'url': 'https://youtu.be/$id',
  'isClose': close,
  'isLive': false,
  'difference': ?diff,
  if (lib != null) 'inLibrary': {'id': lib, 'title': 'Ya'},
};

Json resolved({List<Json>? candidates, Json? existing, String link = 'spotify'}) => {
  'link': link,
  'pastedURL': 'https://open.spotify.com/track/1',
  'title': 'Tema',
  'artist': 'Grupo',
  'noCloseCandidate': false,
  'candidates': candidates ?? [cand('a', close: true, diff: 0.4), cand('b', diff: 5)],
  'existing': ?existing,
};

const kTrackUrl = 'https://open.spotify.com/track/1';
const kUuid = '00000000-0000-0000-0000-000000000001';

Json spotifyTrack() => {
  'id': '1',
  'name': 'Tema',
  'artists': ['Grupo'],
  'album': 'Disco',
  'durationText': '3:00',
  'trackURL': kTrackUrl,
  'appURL': 'spotify:track:1',
};

Json finished({String jobId = 'link-1', bool dup = false, Json? error, List<String> notices = const []}) => {
  'jobId': jobId,
  'id': ?(error == null ? kUuid : null),
  'duplicate': dup,
  'notices': notices,
  'error': ?error,
};

Json job(String id, String stage, double? f, {String text = ''}) => {
  'id': id,
  'title': 't',
  'stage': stage,
  'state': 'running',
  'fraction': ?f,
  'text': text,
};

/// MockCore que retiene `link.resolve` hasta abrir la puerta.
class GatedCore implements CoreClient {
  GatedCore(this.inner, this.gate);
  final MockCore inner;
  final Completer<void> gate;

  @override
  Future<T> call<T>(String method, Object? params, T Function(Json) decode) async {
    if (method == 'link.resolve') await gate.future;
    return inner.call(method, params, decode);
  }

  @override
  Stream<T> on<T>(String event, T Function(Json) decode) => inner.on(event, decode);

  @override
  Future<void> shutdown() => inner.shutdown();
}

Future<(ProviderContainer, MockCore)> setup({String classify = 'track', Completer<void>? gate}) async {
  final core = await MockCore.load((await DirectoryFixtureSource.find())!);
  core.result('link.classify', {'kind': classify, 'source': classify == 'unsupported' ? null : 'spotify'});
  core.result('link.resolve', resolved());
  final c = ProviderContainer(overrides: [coreClientProvider.overrideWithValue(gate == null ? core : GatedCore(core, gate))],
  );
  addTearDown(c.dispose);
  c.listen(linkImportStoreProvider, (_, _) {});
  return (c, core);
}

LinkImportStore st(ProviderContainer c) => c.read(linkImportStoreProvider.notifier);
LinkImportState sv(ProviderContainer c) => c.read(linkImportStoreProvider);
int count(MockCore core, String m) => core.calls.where((x) => x.method == m).length;
Object? params(MockCore core, String m) => core.calls.lastWhere((x) => x.method == m).params;

Future<void> toCandidates(ProviderContainer c) async {
  st(c).setText(kTrackUrl);
  await st(c).submit();
  st(c).selectCandidate('a');
}

void main() {
  group('link_import_store', () {
    test('pista resuelta: classify, resolve y candidates con la confirmación elegida', () async {
      final (c, core) = await setup();
      st(c).setText('  $kTrackUrl ');
      await st(c).submit();
      final s = sv(c);
      expect(s.screen, LinkImportScreen.candidates);
      expect(s.title, 'Tema');
      expect(s.artist, 'Grupo');
      expect(s.selectedId, isNull); // lista sin confirmación: hay que elegir
      expect(s.confirmation, isNull);
      expect(s.canImport, isFalse);
      expect(params(core, 'link.classify'), {'url': kTrackUrl});
      st(c).swap();
      expect((sv(c).title, sv(c).artist), ('Grupo', 'Tema'));
      st(c).selectCandidate('b');
      expect(sv(c).selectedCandidate?.id, 'b');
      expect(sv(c).canImport, isTrue);
    });

    test('vídeo único: la confirmación manda y canImport exige título', () async {
      final (c, core) = await setup();
      core.result('link.resolve', resolved(link: 'youtube', candidates: [cand('v', close: true)]));
      await toCandidates(c);
      expect(sv(c).confirmation?.id, 'v');
      expect(sv(c).selectedCandidate?.id, 'v');
      expect(sv(c).canImport, isTrue);
      st(c).setTitle(' ');
      expect(sv(c).canImport, isFalse);
    });

    test('candidato en la biblioteca no es seleccionable; manual lo añade primero', () async {
      final (c, core) = await setup();
      core.result('link.resolve', resolved(candidates: [cand('a', diff: 1, lib: kUuid), cand('b', diff: 2)]));
      await toCandidates(c);
      expect(sv(c).selectedId, isNull);
      st(c).selectCandidate('a');
      expect(sv(c).selectedId, isNull);
      expect(sv(c).canImport, isFalse);
      core.result('link.addManual', {
        'added': 'm',
        'selectable': true,
        'resolution': resolved(candidates: [cand('m', diff: 0), cand('a', diff: 1, lib: kUuid)]),
      });
      await st(c).addManual(' https://youtu.be/m ');
      expect(sv(c).selectedId, 'm');
      expect(sv(c).title, 'Tema');
      core.failWith('link.addManual', const CoreError('bad-params', 'x'));
      await st(c).addManual('mal');
      expect(sv(c).manualError?.code, 'bad-params');
    });

    test('repetido: existing en la resolución', () async {
      final (c, core) = await setup();
      core.result('link.resolve', resolved(candidates: [], existing: {'id': kUuid, 'title': 'Ya'}));
      await toCandidates(c);
      expect(sv(c).screen, LinkImportScreen.repeated);
      expect(sv(c).existing?.id, kUuid);
    });

    test('unsupported busca en Spotify; elegir resuelve; error de búsqueda queda local', () async {
      final (c, core) = await setup(classify: 'unsupported');
      core.result('link.search', {'query': 'tema', 'tracks': [spotifyTrack()]});
      st(c).setText('tema');
      await st(c).submit();
      expect(count(core, 'link.resolve'), 0);
      expect(sv(c).screen, LinkImportScreen.empty);
      expect(sv(c).spotifyTracks?.single.name, 'Tema');
      await st(c).chooseSpotifyTrack(sv(c).spotifyTracks!.single);
      expect(sv(c).screen, LinkImportScreen.candidates);
      expect(sv(c).text, kTrackUrl);
      expect(params(core, 'link.resolve'), {'url': kTrackUrl});
      st(c).reset();
      core.failWith('link.search', const CoreError('spotify-offline', 'x'));
      st(c).setText('otra');
      await st(c).submit();
      expect(sv(c).spotifyError?.code, 'spotify-offline');
      expect(sv(c).searching, isFalse);
    });

    test('openSpotify llama host.openURL', () async {
      final (c, core) = await setup();
      core.result('host.openURL', {'opened': 'spotify:track:1'});
      await st(c).openSpotify('spotify:track:1', fallback: kTrackUrl);
      expect(params(core, 'host.openURL'), {'urls': ['spotify:track:1', kTrackUrl]});
    });

    test('import: working con progreso y link.finished ok con avisos', () async {
      final (c, core) = await setup();
      await toCandidates(c);
      core.result('link.import', {'jobId': 'link-1'});
      st(c).setArtist('');
      await st(c).importSelected();
      expect(sv(c).screen, LinkImportScreen.working);
      expect(sv(c).jobId, 'link-1');
      expect(params(core, 'link.import'), {'candidateId': 'a', 'title': 'Tema', 'artist': ''});
      core.emit('jobs.progress', job('link-9', 'download', 0.9));
      core.emit('jobs.progress', job('link-1', 'download', 0.3, text: 'Descargando audio… 30 %'));
      await pumpEventQueue();
      expect(sv(c).progress, 0.3);
      expect(sv(c).workPhase, LinkWorkPhase.downloading);
      expect(sv(c).canCancel, isTrue);
      core.emit('jobs.progress', job('link-1', 'download', null, text: 'Convirtiendo a WAV…'));
      await pumpEventQueue();
      expect(sv(c).workPhase, LinkWorkPhase.converting);
      core.emit('jobs.progress', job('link-1', 'import', 0.5));
      await pumpEventQueue();
      expect(sv(c).workPhase, LinkWorkPhase.importing);
      expect(sv(c).canCancel, isFalse);
      core.emit('link.finished', finished(notices: ['Aviso']));
      await pumpEventQueue();
      expect(sv(c).screen, LinkImportScreen.done);
      expect(sv(c).notices, ['Aviso']);
      expect(sv(c).importedId, kUuid);
    });

    test('link.finished duplicado expone duplicateOf; también tras reset()', () async {
      final (c, core) = await setup();
      await toCandidates(c);
      core.result('link.import', {'jobId': 'link-1'});
      await st(c).importSelected();
      core.emit('link.finished', finished(dup: true));
      await pumpEventQueue();
      expect(sv(c).duplicateOf, kUuid);
      expect(sv(c).screen, LinkImportScreen.empty);
      st(c).dismissDuplicate();
      expect(sv(c).duplicateOf, isNull);

      await toCandidates(c);
      core.result('link.import', {'jobId': 'link-2'});
      await st(c).importSelected();
      st(c).reset();
      core.emit('link.finished', finished(jobId: 'link-2', dup: true));
      await pumpEventQueue();
      expect(sv(c).duplicateOf, kUuid);
    });

    test('link.finished con error: pantalla de error o vuelta a candidatos', () async {
      final (c, core) = await setup();
      await toCandidates(c);
      core.result('link.import', {'jobId': 'link-1'});
      await st(c).importSelected();
      core.emit('link.finished', finished(error: {'code': 'extractor-broken', 'message': 'T\nD'}));
      await pumpEventQueue();
      expect(sv(c).screen, LinkImportScreen.error);
      expect(sv(c).error?.suggestsUpdate, isTrue);
      expect(sv(c).errorAction, LinkErrorAction.updateAndRetry);

      await st(c).cancel(); // vuelve a los candidatos
      expect(sv(c).screen, LinkImportScreen.candidates);
      await st(c).importSelected();
      core.emit('link.finished', finished(error: {'code': 'private-video', 'message': 'T'}));
      await pumpEventQueue();
      expect(sv(c).screen, LinkImportScreen.candidates);
      expect(sv(c).error?.code, 'private-video');
    });

    test('acción del error según el código', () async {
      final (c, core) = await setup();
      core.failWith('link.resolve', const CoreError('unsupported-link', 'x'));
      await toCandidates(c);
      expect(sv(c).errorAction, LinkErrorAction.tryOtherLink);
      core.failWith('link.resolve', const CoreError('spotify-unreadable', 'x'));
      await st(c).retry();
      expect(sv(c).errorAction, LinkErrorAction.pasteYoutube);
      core.failWith('link.resolve', const CoreError('offline', 'x'));
      await st(c).retry();
      expect(sv(c).errorAction, LinkErrorAction.retry);
      core.result('link.resolve', resolved());
      await st(c).retry();
      expect(sv(c).screen, LinkImportScreen.candidates);
    });

    test('cancel en resolving usa link.cancel sin jobId y descarta la respuesta', () async {
      final gate = Completer<void>();
      final (c, core) = await setup(gate: gate);
      core.result('link.cancel', {'cancelled': true});
      st(c).setText(kTrackUrl);
      final f = st(c).submit();
      await pumpEventQueue();
      await st(c).cancel();
      gate.complete();
      await f;
      expect(sv(c).screen, LinkImportScreen.empty);
      expect(params(core, 'link.cancel'), <String, Object?>{});
    });

    test('cancel en working usa link.cancel {jobId}; finished cancelled vuelve a candidatos', () async {
      final (c, core) = await setup();
      await toCandidates(c);
      core.result('link.import', {'jobId': 'link-1'});
      core.result('link.cancel', {'cancelled': true});
      await st(c).importSelected();
      await st(c).cancel();
      expect(params(core, 'link.cancel'), {'jobId': 'link-1'});
      core.emit('link.finished', finished(error: {'code': 'cancelled', 'message': 'Cancelado'}));
      await pumpEventQueue();
      expect(sv(c).screen, LinkImportScreen.candidates);
      expect(sv(c).error, isNull);
      expect(await st(c).cancelJob('link-7'), isNull);
      expect(params(core, 'link.cancel'), {'jobId': 'link-7'});
    });

    test('updateAndRetry actualiza, repite la resolución y conserva título y elección', () async {
      final (c, core) = await setup();
      await toCandidates(c);
      st(c).setTitle('Mi título');
      st(c).selectCandidate('b');
      core.failWith('link.resolve', const CoreError('extractor-broken', 'T\nD'));
      await st(c).retry();
      expect(sv(c).errorAction, LinkErrorAction.updateAndRetry);
      core.result('link.resolve', resolved());
      core.result('tools.updateYtDlp', {'version': '2', 'origin': 'updated', 'alreadyLatest': false});
      await st(c).updateAndRetry();
      expect(count(core, 'tools.updateYtDlp'), 1);
      expect(sv(c).screen, LinkImportScreen.candidates);
      expect(sv(c).title, 'Mi título');
      expect(sv(c).selectedId, 'b');
    });

    test('updateAndRetry con yt-dlp ya al día deja alreadyLatest y sin acción', () async {
      final (c, core) = await setup();
      core.failWith('link.resolve', const CoreError('extractor-broken', 'T\nD'));
      await toCandidates(c);
      core.result('tools.updateYtDlp', {'version': '1', 'origin': 'embedded', 'alreadyLatest': true});
      await st(c).updateAndRetry();
      expect(sv(c).screen, LinkImportScreen.error);
      expect(sv(c).alreadyLatest, isTrue);
      expect(sv(c).errorAction, isNull);
    });

    test('lista: screen playlist con el snapshot', () async {
      final (c, core) = await setup(classify: 'playlist');
      final root = (await DirectoryFixtureSource.find())!.root.path;
      final raw = jsonDecode(await File('$root/link/link.resolve.playlist.result.json').readAsString());
      core.result('link.resolve', raw);
      st(c).setText('https://open.spotify.com/playlist/x');
      await st(c).submit();
      expect(sv(c).screen, LinkImportScreen.playlist);
      expect(sv(c).playlist, isNotNull);
    });
  });
}
