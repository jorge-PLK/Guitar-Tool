import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/core/core_client.dart' show Json;
import 'package:toneforge/core/mock_core.dart';

late Directory _dir;

Json _load(String stem) {
  final text = File('${_dir.path}/$stem.json').readAsStringSync();
  return (jsonDecode(text) as Map).cast<String, Object?>();
}

/// Nombre `<método>.<kind>[.<variante>].json` → método, tipo y variante.
class _Name {
  _Name(this.method, this.kind, this.variant);

  final String method;
  final String kind;
  final String? variant;
}

const _kinds = {'result', 'event', 'params', 'error'};

_Name? _parse(String file) {
  final stem = file.substring(0, file.length - '.json'.length);
  final parts = stem.split('.');
  for (var i = 1; i < parts.length; i++) {
    if (_kinds.contains(parts[i])) {
      final variant = i + 1 < parts.length ? parts.sublist(i + 1).join('.') : null;
      return _Name(parts.sublist(0, i).join('.'), parts[i], variant);
    }
  }
  return null;
}

// Vacío = `{}`.
Json _empty(Json j) {
  expect(j, isEmpty);
  return j;
}

// Respuestas por método (`tab.<m>.result[.<variante>]`).
final _results = <String, Object? Function(Json)>{
  'tab.open': TabState.fromJson,
  'tab.state': TabState.fromJson,
  'tab.close': _empty,
  'tab.setSource': TabState.fromJson,
  'tab.score': TabScoreResult.fromJson,
  'tab.selectTrack': TabState.fromJson,
  'tab.transcribe': TabQueuedResult.fromJson,
  'tab.cancel': TabCancelResult.fromJson,
  'tab.beatClick': TabState.fromJson,
  'tab.beatDrag': TabState.fromJson,
  'tab.noteClick': TabState.fromJson,
  'tab.select': TabState.fromJson,
  'tab.span': TabState.fromJson,
  'tab.dismissNotices': TabState.fromJson,
  'tab.toggleMute': TabState.fromJson,
  'tab.toggleSolo': TabState.fromJson,
  'tab.setListening': TabState.fromJson,
  'tab.setAllListening': TabState.fromJson,
  'tab.edit': TabState.fromJson,
  'tab.exportName': TabExportNameResult.fromJson,
  'tab.keyMap': TabKeyMapResult.fromJson,
  'tab.export': TabExportResult.fromJson,
  'tab.songsterr.open': SongsterrSheetState.fromJson,
  'tab.songsterr.state': SongsterrSheetState.fromJson,
  'tab.songsterr.close': SongsterrSheetState.fromJson,
  'tab.songsterr.search': SongsterrSheetState.fromJson,
  'tab.songsterr.select': SongsterrSheetState.fromJson,
  'tab.songsterr.link': SongsterrSheetState.fromJson,
  'tab.songsterr.use': SongsterrSheetState.fromJson,
  'tab.songsterr.review': SongsterrSheetState.fromJson,
  'tab.songsterr.retry': SongsterrSheetState.fromJson,
  'tab.songsterr.retryImport': SongsterrSheetState.fromJson,
  'tab.songsterr.back': SongsterrSheetState.fromJson,
  'tab.songsterr.assign': SongsterrSheetState.fromJson,
  'tab.songsterr.allAutomatic': SongsterrSheetState.fromJson,
  'tab.songsterr.accept': TabState.fromJson,
  'tab.songsterr.automatic': TabState.fromJson,
};

// Eventos por nombre (`tab.<e>.event[.<variante>]`).
final _events = <String, Object? Function(Json)>{
  'tab.state': TabState.fromJson,
  'tab.progress': TabProgressEvent.fromJson,
  'tab.selection': TabSelectionEvent.fromJson,
  'tab.range': TabRangeEvent.fromJson,
  'tab.songsterr.state': SongsterrSheetState.fromJson,
};

// Params: ida y vuelta. Vacíos = `{}`.
final _params = <String, Json Function(Json)>{
  'tab.open': (j) => TabOpenParams.fromJson(j).toJson(),
  'tab.state': _empty,
  'tab.close': _empty,
  'tab.setSource': (j) => TabSourceParams.fromJson(j).toJson(),
  'tab.score': (j) => TabTrackParams.fromJson(j).toJson(),
  'tab.selectTrack': (j) => TabTrackParams.fromJson(j).toJson(),
  'tab.transcribe': (j) => TabTrackParams.fromJson(j).toJson(),
  'tab.cancel': _empty,
  'tab.beatClick': (j) => TabClickParams.fromJson(j).toJson(),
  'tab.beatDrag': (j) => TabClickParams.fromJson(j).toJson(),
  'tab.noteClick': (j) => TabClickParams.fromJson(j).toJson(),
  'tab.select': (j) => TabSelectParams.fromJson(j).toJson(),
  'tab.span': (j) => TabSpanParams.fromJson(j).toJson(),
  'tab.dismissNotices': _empty,
  'tab.toggleMute': (j) => TabTrackParams.fromJson(j).toJson(),
  'tab.toggleSolo': (j) => TabTrackParams.fromJson(j).toJson(),
  'tab.setListening': (j) => TabListeningParams.fromJson(j).toJson(),
  'tab.setAllListening': (j) => TabListeningParams.fromJson(j).toJson(),
  'tab.edit': (j) => TabEditParams.fromJson(j).toJson(),
  'tab.exportName': _empty,
  'tab.keyMap': _empty,
  'tab.export': (j) => TabExportParams.fromJson(j).toJson(),
  'tab.songsterr.open': _empty,
  'tab.songsterr.state': _empty,
  'tab.songsterr.close': _empty,
  'tab.songsterr.search': _empty,
  'tab.songsterr.select': (j) => SongsterrSelectParams.fromJson(j).toJson(),
  'tab.songsterr.link': (j) => SongsterrLinkParams.fromJson(j).toJson(),
  'tab.songsterr.use': _empty,
  'tab.songsterr.review': _empty,
  'tab.songsterr.retry': _empty,
  'tab.songsterr.retryImport': _empty,
  'tab.songsterr.back': _empty,
  'tab.songsterr.assign': (j) => SongsterrAssignParams.fromJson(j).toJson(),
  'tab.songsterr.allAutomatic': _empty,
  'tab.songsterr.accept': _empty,
  'tab.songsterr.automatic': _empty,
};

/// Devuelve `null` si el fichero se decodifica; si no, el motivo.
String? _decode(String file, Json j) {
  final name = _parse(file);
  if (name == null) return 'nombre no reconocido';
  if (name.kind == 'error') {
    if (j['code'] is! String || j['message'] is! String) return 'error sin code/message';
    return null;
  }
  final Map<String, Object? Function(Json)>? resultLike = switch (name.kind) {
    'result' => _results,
    'event' => _events,
    _ => null,
  };
  if (resultLike != null) {
    final fn = resultLike[name.method];
    if (fn == null) return 'sin decoder de ${name.kind} para ${name.method}';
    fn(j);
    return null;
  }
  if (name.kind == 'params') {
    final fn = _params[name.method];
    if (fn == null) return 'sin decoder de params para ${name.method}';
    final back = fn(j);
    expect(back, equals(j), reason: file);
    return null;
  }
  return 'tipo desconocido ${name.kind}';
}

List<String> _files() => [
      for (final f in _dir.listSync().whereType<File>())
        if (f.path.endsWith('.json')) f.uri.pathSegments.last,
    ]..sort();

void main() => group('contract · tab', () {
  setUpAll(() async {
    final src = await DirectoryFixtureSource.find();
    if (src == null) {
      fail('No se encuentra Contract/fixtures');
    }
    _dir = Directory('${src.root.path}/tab');
  });

  test('la carpeta de fixtures de tab tiene 130 ficheros', () {
    expect(_files(), hasLength(130));
  });

  test('tab.keyMap: reglas con shift nulo, when conocido y desconocido', () {
    final m = TabKeyMapResult.fromJson(_load('tab.keyMap.result'));
    expect(m.rules, hasLength(54));
    expect(m.rules.first.key, 'Escape');
    expect(m.rules.first.when, TabKeyWhen.span);
    expect(m.rules.first.shift, isFalse);
    final z = m.rules[1];
    expect([z.key, z.ctrl, z.alt, z.shift, z.when], ['z', true, false, null, TabKeyWhen.edit]);
    expect(m.rules.every((r) => r.when != TabKeyWhen.unknown), isTrue);
    final u = TabKeyRule.fromJson({'key': 'q', 'shift': null, 'ctrl': false, 'alt': false, 'when': 'x'});
    expect(u.when, TabKeyWhen.unknown);
  });

  test('cada fixture de tab tiene decoder', () {
    final sinDecoder = <String>[];
    for (final f in _files()) {
      final name = _parse(f);
      if (name == null) {
        sinDecoder.add(f);
        continue;
      }
      final known = name.kind == 'error' ||
          (name.kind == 'result' && _results.containsKey(name.method)) ||
          (name.kind == 'event' && _events.containsKey(name.method)) ||
          (name.kind == 'params' && _params.containsKey(name.method));
      if (!known) sinDecoder.add(f);
    }
    expect(sinDecoder, isEmpty);
  });

  test('decodifica todos los fixtures de tab (respuestas, eventos, errores, params)', () {
    final fallos = <String>[];
    for (final f in _files()) {
      final motivo = _decode(f, _load(f.substring(0, f.length - '.json'.length)));
      if (motivo != null) fallos.add('$f: $motivo');
    }
    expect(fallos, isEmpty);
  });

  test('tab.select: summary noNote y drumsNoHits; header meterBpm', () {
    final s = TabState.fromJson(_load('tab.select.result'));
    expect(s.header?.code, TabHeaderCode.meterBpm);
    expect(s.header?.bar, '4/4');
    expect(s.header?.bpm, 120);
    final sum = s.selection!.summary!;
    expect((sum.code, sum.bar, sum.beat, sum.string), (TabSummaryCode.noNote, 3, 1, 2));
    final d = TabState.fromJson(_load('tab.select.result.drums'));
    expect(d.selection!.summary!.code, TabSummaryCode.drumsNoHits);
    expect(d.selection!.summary!.pieces, isEmpty);
  });

  test('summary: note, drums con piezas, header meter y codes desconocidos', () {
    final n = TabSelectionSummary.fromJson(<String, Object?>{'code': 'note', 'bar': 2, 'beat': 3, 'string': 4, 'fret': 7});
    expect((n.code, n.string, n.fret), (TabSummaryCode.note, 4, 7));
    final d = TabSelectionSummary.fromJson(<String, Object?>{
      'code': 'drums', 'bar': 1, 'beat': 1, 'pieces': <Object?>['kick', 'openHiHat', 'zzz'],
    });
    expect(d.code, TabSummaryCode.drums);
    expect(d.pieces, <TabDrumPiece>[TabDrumPiece.kick, TabDrumPiece.openHiHat, TabDrumPiece.unknown]);
    expect(d.toJson()['pieces'], <Object?>['kick', 'openHiHat', 'unknown']);
    final m = TabHeaderSummary.fromJson(<String, Object?>{'code': 'meter', 'bar': '3/4'});
    expect((m.code, m.bar, m.bpm), (TabHeaderCode.meter, '3/4', null));
    expect(TabHeaderSummary.fromJson(<String, Object?>{'code': 'x', 'bar': ''}).code, TabHeaderCode.unknown);
    expect(TabSelectionSummary.fromJson(<String, Object?>{'code': 'x', 'bar': 1, 'beat': 1}).code, TabSummaryCode.unknown);
  });

  test('tab.edit: cada factoría produce exactamente su fixture', () {
    final casos = <String, TabEditParams>{
      'tab.edit.params.digit': TabEditParams.digit(5),
      'tab.edit.params.moveString': TabEditParams.moveString(up: false),
      'tab.edit.params.duration': TabEditParams.duration(sign: 1),
      'tab.edit.params.hit': TabEditParams.hit(piece: 'kick'),
      'tab.edit.params.ornament': TabEditParams.ornament(name: 'vibrato'),
      'tab.edit.params.key': TabEditParams.key(key: 'ArrowRight'),
      'tab.edit.params.move': TabEditParams.move(forward: true),
      'tab.edit.params.tuning': TabEditParams.tuning(track: 'bass', preset: 'dropD'),
      'tab.edit.params.addNote': TabEditParams.addNote(),
      'tab.edit.params.delete': TabEditParams.delete(),
      'tab.edit.params.deselect': TabEditParams.deselect(),
      'tab.edit.params.undo': TabEditParams.undo(),
      'tab.edit.params.redo': TabEditParams.redo(),
      'tab.edit.params': TabEditParams.editMode(on: true),
    };
    for (final e in casos.entries) {
      expect(e.value.toJson(), equals(_load(e.key)), reason: e.key);
    }
  });

  test('tab.open ready: fase, pistas, afinación y ausencia de customTuning', () {
    final s = TabState.fromJson(_load('tab.open.result.ready'));
    expect(s.phase, TabPhase.ready);
    expect(s.source, TabSource.automatic);
    expect(s.selectedTrack, 'bass');
    expect(s.revision, 3);
    expect(s.tracks.map((t) => t.id), ['bass', 'drums']);
    expect(s.tracks.first.kind, TabTrackKind.bass);
    expect(s.tracks.first.tuning!.strings, [43, 38, 33, 28]);
    expect(s.tracks.first.tuning!.preset, TabTuningPreset.standard);
    expect(s.tracks.first.customTuning, isNull);
    expect(s.tracks.last.tuning, isNull);
    expect(s.tracks.first.fingerprint!.parametersVersion, 3);
    expect(s.tracks.first.transcription, TabTranscription.ready);
  });

  test('tab.open working: pistas en cola', () {
    final s = TabState.fromJson(_load('tab.open.result.working'));
    expect(s.tracks.every((t) => t.transcription == TabTranscription.queued), isTrue);
  });

  test('tab.score: track ids y partitura como cadena', () {
    final r = TabScoreResult.fromJson(_load('tab.score.result'));
    expect(r.trackIDs, ['bass', 'drums']);
    expect(r.trackIndex, 0);
    expect(r.revision, 3);
    final score = jsonDecode(r.json) as Map<String, Object?>;
    expect(score['version'], 1);
    expect(r.timing!.beats.length, 17);
    expect(r.timing!.beatsPerBar, [1, 4, 4, 4, 4]);
    expect(r.timing!.end, 8.5);
    expect(TabScoreResult.fromJson({..._load('tab.score.result'), 'timing': null}).timing, isNull);
  });

  test('tab.progress: estado y fracción', () {
    final e = TabProgressEvent.fromJson(_load('tab.progress.event'));
    expect(e.state, TabProgressState.transcribing);
    expect(e.track, 'bass');
    expect(e.fraction, closeTo(0.4, 1e-9));
    expect(e.error, isNull);
  });

  test('tab.songsterr.state pairingSolos: slot lead con solos', () {
    final s = SongsterrSheetState.fromJson(
      _load('tab.songsterr.state.result.pairingSolos'),
    );
    expect(s.stage, TabSongsterrStage.pairing);
    expect(s.canUse, isTrue);
    final slots = s.pairing!.slots;
    expect(slots.first.role, TabSongsterrRole.lead);
    expect(slots.first.solos.first.clock, '0:12');
    expect(slots.first.solos.last.choices, isNotEmpty);
    expect(s.pairing!.extraNames, ['Rítmica']);
    expect(slots.last.role, TabSongsterrRole.bass);
    expect(slots.last.confidence, closeTo(0.8, 1e-9));
  });

  test('valores no previstos caen en unknown y no lanzan', () {
    final j = _load('tab.open.result.ready')..['phase'] = 'futuro';
    expect(TabState.fromJson(j).phase, TabPhase.unknown);
  });
});
