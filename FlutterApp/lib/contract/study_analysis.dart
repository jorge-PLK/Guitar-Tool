part of 'study.dart';

/// Tonalidad tal como se muestra (transpuesta): tónica solo con sostenidos y modo `maj`|`min`.
final class StudyShownKey {
  const StudyShownKey({required this.tonic, required this.mode});

  factory StudyShownKey.fromJson(Json j) =>
      StudyShownKey(tonic: _s(j['tonic']), mode: _s(j['mode']));

  final String tonic;
  final String mode;

  Json toJson() => {'tonic': tonic, 'mode': mode};
}

final class StudyKey {
  const StudyKey({this.detected, this.override, this.effective, this.confidence, this.display});

  factory StudyKey.fromJson(Json j) => StudyKey(
        detected: _sn(j['detected']),
        override: _sn(j['override']),
        effective: _sn(j['effective']),
        confidence: _dn(j['confidence']),
        display: _opt(j['display'], StudyShownKey.fromJson),
      );

  final String? detected;
  final String? override;
  final String? effective;
  final double? confidence;
  final StudyShownKey? display;
}

/// Cejilla de una forma: cuerdas 6 = Mi grave … 1 = Mi agudo.
final class StudyBarre {
  const StudyBarre({required this.fret, required this.fromString, required this.toString_});

  factory StudyBarre.fromJson(Json j) => StudyBarre(
        fret: _i(j['fret']),
        fromString: _i(j['fromString']),
        toString_: _i(j['toString']),
      );

  final int fret;
  final int fromString;

  /// Campo JSON `toString` (no se puede llamar así en Dart).
  final int toString_;
}

/// Forma de acorde: `frets` de grave a aguda (null = muda, 0 = al aire).
final class StudyChordShape {
  const StudyChordShape({required this.frets, required this.baseFret, this.barre});

  factory StudyChordShape.fromJson(Json j) => StudyChordShape(
        frets: [for (final e in j['frets']! as List<Object?>) _in(e)],
        baseFret: _i(j['baseFret']),
        barre: _opt(j['barre'], StudyBarre.fromJson),
      );

  final List<int?> frets;
  final int baseFret;
  final StudyBarre? barre;
}

final class StudyChord {
  const StudyChord({
    required this.start,
    required this.end,
    required this.index,
    required this.name,
    required this.overridden,
    this.display,
    this.shape,
  });

  factory StudyChord.fromJson(Json j) => StudyChord(
        start: _d(j['start']),
        end: _d(j['end']),
        index: _i(j['index']),
        name: _s(j['name']),
        overridden: _b(j['overridden']),
        display: _sn(j['display']),
        shape: _opt(j['shape'], StudyChordShape.fromJson),
      );

  final double start;
  final double end;
  final int index;
  final String name;
  final bool overridden;

  /// Nombre transpuesto; ausente en núcleos antiguos.
  final String? display;

  /// Ausente para «?» y «N».
  final StudyChordShape? shape;
}

/// Params de `study.chordShape`; `capo` ausente = el del transporte.
final class StudyChordShapeParams {
  const StudyChordShapeParams({required this.index, this.capo});

  factory StudyChordShapeParams.fromJson(Json j) =>
      StudyChordShapeParams(index: _i(j['index']), capo: _in(j['capo']));

  final int index;
  final int? capo;

  Json toJson() => _compact({'index': index, 'capo': capo});
}

/// Respuesta de `study.chordShape`.
final class StudyChordShapeResult {
  const StudyChordShapeResult({
    required this.index,
    required this.display,
    required this.capo,
    this.shape,
  });

  factory StudyChordShapeResult.fromJson(Json j) => StudyChordShapeResult(
        index: _i(j['index']),
        display: _s(j['display']),
        capo: _i(j['capo']),
        shape: _opt(j['shape'], StudyChordShape.fromJson),
      );

  final int index;
  final String display;
  final int capo;
  final StudyChordShape? shape;
}

/// Corrección de acorde por rango (`chordOverrides`).
final class StudyOverrideInfo {
  const StudyOverrideInfo({required this.start, required this.end, required this.index});

  factory StudyOverrideInfo.fromJson(Json j) => StudyOverrideInfo(
        start: _d(j['start']),
        end: _d(j['end']),
        index: _i(j['index']),
      );

  final double start;
  final double end;
  final int index;
}

final class StudyAnalysisInfo {
  const StudyAnalysisInfo({
    required this.state,
    required this.error,
    required this.beats,
    required this.downbeats,
    required this.bpm,
    required this.beatsPerBar,
    required this.chords,
    required this.key,
  });

  factory StudyAnalysisInfo.fromJson(Json j) => StudyAnalysisInfo(
        state: _enumOr(StudyAnalysisState.values, j['state'], StudyAnalysisState.unknown),
        error: _sn(j['error']),
        beats: _ds(j['beats']),
        downbeats: _ds(j['downbeats']),
        bpm: _dn(j['bpm']),
        beatsPerBar: _in(j['beatsPerBar']),
        chords: _items(j['chords'], StudyChord.fromJson),
        key: StudyKey.fromJson(_map(j['key'])),
      );

  final StudyAnalysisState state;
  final String? error;
  final List<double> beats;
  final List<double> downbeats;
  final double? bpm;
  final int? beatsPerBar;
  final List<StudyChord> chords;
  final StudyKey key;
}

final class StudySectionInfo {
  const StudySectionInfo({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
    required this.solo,
    required this.color,
    required this.paletteIndex,
  });

  factory StudySectionInfo.fromJson(Json j) => StudySectionInfo(
        id: _s(j['id']),
        name: _s(j['name']),
        start: _d(j['start']),
        end: _d(j['end']),
        solo: _b(j['solo']),
        color: _in(j['color']),
        paletteIndex: _in(j['paletteIndex']),
      );

  final String id;
  final String name;
  final double start;
  final double end;
  final bool solo;
  final int? color;
  final int? paletteIndex;
}

final class StudyGuitarsInfo {
  const StudyGuitarsInfo({
    required this.stereoSplit,
    required this.usesSeparatedGuitars,
    required this.names,
    required this.process,
    required this.error,
    required this.saveError,
  });

  factory StudyGuitarsInfo.fromJson(Json j) => StudyGuitarsInfo(
        stereoSplit: _b(j['stereoSplit']),
        usesSeparatedGuitars: _b(j['usesSeparatedGuitars']),
        names: _strs(j['names']),
        process: _enumOr(StudyGuitarProcess.values, j['process'], StudyGuitarProcess.unknown),
        error: _sn(j['error']),
        saveError: _sn(j['saveError']),
      );

  final bool stereoSplit;
  final bool usesSeparatedGuitars;
  final Map<String, String> names;
  final StudyGuitarProcess process;
  final String? error;
  final String? saveError;
}
