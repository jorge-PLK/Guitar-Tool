import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/core/core_client.dart' show Json;
import 'package:toneforge/core/mock_core.dart';

late DirectoryFixtureSource _src;
late List<String> _files;

/// Métodos cuyos params son `{}` (sin clase).
const _emptyParams = {
  'analyze',
  'applySections',
  'clearChordOverrides',
  'close',
  'discardSections',
  'pause',
  'play',
  'snapshot',
};

/// Params con clase: fromJson y toJson deben reproducir el fixture.
final Map<String, Json Function(Json)> _paramsRoundTrip = {
  'open': (j) => StudyOpenParams.fromJson(j).toJson(),
  'seek': (j) => StudySeekParams.fromJson(j).toJson(),
  'setRate': (j) => StudyRateParams.fromJson(j).toJson(),
  'setTranspose': (j) => StudyTransposeParams.fromJson(j).toJson(),
  'setCapo': (j) => StudyCapoParams.fromJson(j).toJson(),
  'setLoop': (j) => StudyLoopParams.fromJson(j).toJson(),
  'setMix': (j) => StudyMixParams.fromJson(j).toJson(),
  'setMaster': (j) => StudyMasterParams.fromJson(j).toJson(),
  'setMetronome': (j) => StudyMetronomeParams.fromJson(j).toJson(),
  'setKey': (j) => StudySetKeyParams.fromJson(j).toJson(),
  'chordShape': (j) => StudyChordShapeParams.fromJson(j).toJson(),
  'setChord': (j) => StudySetChordParams.fromJson(j).toJson(),
  'removeChordOverrides': (j) => StudyChordRangeParams.fromJson(j).toJson(),
  'splitChord': (j) => StudySplitChordParams.fromJson(j).toJson(),
  'markSection': (j) => StudyMarkSectionParams.fromJson(j).toJson(),
  'updateSection': (j) => StudyUpdateSectionParams.fromJson(j).toJson(),
  'previewSectionEdge': (j) => StudyPreviewSectionEdgeParams.fromJson(j).toJson(),
  'nudgeSectionEdge': (j) => StudyNudgeSectionParams.fromJson(j).toJson(),
  'deleteSection': (j) => StudyDeleteSectionParams.fromJson(j).toJson(),
  'renameGuitar': (j) => StudyRenameGuitarParams.fromJson(j).toJson(),
  'setGuitarStereo': (j) => StudyGuitarStereoParams.fromJson(j).toJson(),
};

Json _expectEmpty(Json j) {
  expect(j, isEmpty);
  return j;
}

/// Respuestas (`result`), eventos (`event`) y errores (`error`), por `método.tipo`.
final Map<String, Object Function(Json)> _decoders = {
  'open.result': StudyOpenResult.fromJson,
  'snapshot.result': StudyOpenResult.fromJson,
  'close.result': _expectEmpty,
  'analyze.result': StudyEditState.fromJson,
  'applySections.result': StudyEditState.fromJson,
  'discardSections.result': StudyEditState.fromJson,
  'clearChordOverrides.result': StudyEditState.fromJson,
  'removeChordOverrides.result': StudyEditState.fromJson,
  'setKey.result': StudyEditState.fromJson,
  'setChord.result': StudyEditState.fromJson,
  'splitChord.result': StudyEditState.fromJson,
  'markSection.result': StudyEditState.fromJson,
  'updateSection.result': StudyEditState.fromJson,
  'nudgeSectionEdge.result': StudyEditState.fromJson,
  'deleteSection.result': StudyEditState.fromJson,
  'renameGuitar.result': StudyEditState.fromJson,
  'setGuitarStereo.result': StudyEditState.fromJson,
  'previewSectionEdge.result': StudyPreviewSections.fromJson,
  'play.result': StudyTransport.fromJson,
  'pause.result': StudyTransport.fromJson,
  'seek.result': StudyTransport.fromJson,
  'setRate.result': StudyTransport.fromJson,
  'setTranspose.result': StudyTransport.fromJson,
  'setCapo.result': StudyTransport.fromJson,
  'setLoop.result': StudyTransport.fromJson,
  'setMetronome.result': StudyTransport.fromJson,
  'setMix.result': StudyTransport.fromJson,
  'setMaster.result': StudyTransport.fromJson,
  'state.event': StudyTransport.fromJson,
  'position.event': StudyPositionEvent.fromJson,
  'levels.event': StudyLevelsEvent.fromJson,
  'analysis.event': StudyAnalysisEvent.fromJson,
  'guitars.event': StudyGuitarsEvent.fromJson,
  'chordShape.result': StudyChordShapeResult.fromJson,
  'play.error': _expectCallError,
  'setMix.error': _expectCallError,
};

/// Error de llamada `{code, message}`: lo traduce el cliente, no hay DTO.
Json _expectCallError(Json j) {
  expect(j['code'], isA<String>());
  expect(j['message'], isA<String>());
  return j;
}

/// Clave `método.tipo` de un fichero `study.<método>.<tipo>[.<variante>].json`,
/// o null si no encaja con ningún tipo conocido.
String? _keyOf(String file) {
  final base = file.split('/').last;
  if (!base.startsWith('study.') || !base.endsWith('.json')) return null;
  final parts = base.substring('study.'.length, base.length - '.json'.length).split('.');
  final i = parts.lastIndexWhere((p) => p == 'params' || p == 'result' || p == 'event');
  if (i > 0) return '${parts.sublist(0, i).join('.')}.${parts[i]}';
  final e = parts.indexOf('error');
  if (e > 0) return '${parts.sublist(0, e).join('.')}.error';
  return null;
}

/// Sin decoder asignado: null o clave no registrada.
bool _tieneDecoder(String file) {
  final key = _keyOf(file);
  if (key == null) return false;
  if (key.endsWith('.params')) {
    final method = key.substring(0, key.length - '.params'.length);
    return _emptyParams.contains(method) || _paramsRoundTrip.containsKey(method);
  }
  return _decoders.containsKey(key);
}

Future<Json> _load(String name) async =>
    (jsonDecode(await _src.read('study/$name')) as Map).cast<String, Object?>();

Future<void> main() async {
  // Los grupos se declaran con la lista ya leída: main es asíncrono.
  final src = await DirectoryFixtureSource.find();
  if (src == null) {
    test('Contract/fixtures existe', () => fail('No se encuentra Contract/fixtures'));
    return;
  }
  _src = src;
  _files = (await _src.list()).where((f) => f.startsWith('study/')).toList()..sort();

  test('la carpeta de fixtures de study no está vacía', () {
    expect(_files, isNotEmpty);
  });

  test('todo fixture de study tiene decoder asignado', () {
    final sinDecoder = [
      for (final f in _files)
        if (!_tieneDecoder(f)) f,
    ];
    expect(sinDecoder, isEmpty, reason: 'Fixtures sin decoder en test/contract/study_test.dart');
  });

  group('decodifica cada fixture', () {
    for (final name in _files) {
      test(name, () async {
        final key = _keyOf(name);
        expect(key, isNotNull, reason: 'Nombre no reconocido: $name');
        final j = (jsonDecode(await _src.read(name)) as Map).cast<String, Object?>();
        if (key!.endsWith('.params')) {
          final method = key.substring(0, key.length - '.params'.length);
          if (_emptyParams.contains(method)) {
            expect(j, isEmpty);
          } else {
            expect(_paramsRoundTrip[method]!(j), equals(j));
          }
        } else {
          expect(_decoders[key]!(j), isNotNull);
        }
      });
    }
  });

  group('color tri-estado de StudyUpdateSectionParams', () {
    test('keep: ausente → sin clave color', () {
      final m = const StudyUpdateSectionParams(id: 's1').toJson();
      expect(m.containsKey('color'), isFalse);
    });

    test('auto: "color": null', () {
      final m = const StudyUpdateSectionParams(
        id: 's1',
        color: StudyColorAuto(),
      ).toJson();
      expect(m.containsKey('color'), isTrue);
      expect(m['color'], isNull);
    });

    test('palette n → "color": n', () {
      final m = const StudyUpdateSectionParams(
        id: 's1',
        color: StudyColorPalette(3),
      ).toJson();
      expect(m['color'], 3);
    });

    test('fromJson distingue los tres estados', () {
      expect(
        StudyUpdateSectionParams.fromJson({'id': 's1'}).color,
        isA<StudyColorKeep>(),
      );
      expect(
        StudyUpdateSectionParams.fromJson({'id': 's1', 'color': null}).color,
        isA<StudyColorAuto>(),
      );
      final palette = StudyUpdateSectionParams.fromJson({'id': 's1', 'color': 2}).color;
      expect(palette, isA<StudyColorPalette>());
      expect((palette as StudyColorPalette).index, 2);
    });
  });

  group('campos concretos', () {
    test('open.result: projectId y transporte', () async {
      final o = StudyOpenResult.fromJson(await _load('study.open.result.json'));
      expect(o.projectId, isNotEmpty);
      expect(o.transport.channels, isNotEmpty);
    });

    test('levels.event: canales con medidores', () async {
      final lv = StudyLevelsEvent.fromJson(await _load('study.levels.event.json'));
      expect(lv.channels, isNotEmpty);
      expect(lv.channels.values.first.peakDB, isA<double>());
    });

    test('chordShape.result: forma con cejilla y cuerda muda', () async {
      final r = StudyChordShapeResult.fromJson(await _load('study.chordShape.result.json'));
      expect(r.display, 'B');
      expect(r.shape!.frets, [4, 6, 6, 5, 4, 4]);
      expect(r.shape!.barre!.fromString, 6);
      expect(r.shape!.barre!.toString_, 1);
      final c0 =
          StudyChordShapeResult.fromJson(await _load('study.chordShape.result.capo0.json'));
      expect(c0.shape!.frets.first, isNull);
      expect(c0.capo, 0);
    });

    test('analysis.event.withChords: análisis completo con display y shape', () async {
      final e = StudyAnalysisEvent.fromJson(
        await _load('study.analysis.event.withChords.json'),
      );
      final a = e.analysis!;
      expect(a.key.display!.tonic, 'A#');
      expect(a.chords.first.display, 'A#m');
      expect(a.chords.first.shape!.baseFret, 3);
    });

    test('setKey shown: params ida y vuelta', () async {
      final j = await _load('study.setKey.params.shown.json');
      final p = StudySetKeyParams.fromJson(j);
      expect(p.shown!.tonic, 'G');
      expect(p.shown!.mode, 'min');
      expect(p.toJson(), equals(j));
    });

    test('setLoop.result: loop.span false cuando no es del tramo', () async {
      final t = StudyTransport.fromJson(await _load('study.setLoop.result.json'));
      expect(t.loop, isNotNull);
      expect(t.loop!.span, isFalse);
    });

    test('StudyLoop.fromJson: span true se lee', () {
      final l = StudyLoop.fromJson({'start': 1, 'end': 2, 'name': 'Selección', 'span': true});
      expect(l.span, isTrue);
      expect(l.name, 'Selección');
    });

    test('markSection.result: added', () async {
      final es = StudyEditState.fromJson(await _load('study.markSection.result.json'));
      expect(es.added, isNotNull);
      expect(es.added, isNotEmpty);
    });
  });
}
