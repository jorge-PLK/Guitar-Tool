part of 'study.dart';

// Enums: el nombre del enum es el valor crudo del JSON. Lo no previsto cae en `unknown`.

enum StudyStemKind { vocals, drums, bass, guitar, piano, other, unknown }

enum StudyGuitarRole { rhythm, left, right, lead, unknown }

enum StudyAnalysisState { missing, analyzing, ready, failed, unknown }

enum StudyGuitarProcess { idle, processing, failed, unknown }

enum StudyAudioMode { simulated, device, unknown }

final class StudyMetronome {
  const StudyMetronome({required this.on, required this.gainDB, required this.available});

  factory StudyMetronome.fromJson(Json j) => StudyMetronome(
        on: _b(j['on']),
        gainDB: _d(j['gainDB']),
        available: _b(j['available']),
      );

  final bool on;
  final double gainDB;
  final bool available;
}

/// Bucle activo del transporte (no se guarda en el proyecto).
final class StudyLoop {
  const StudyLoop({required this.start, required this.end, this.name});

  factory StudyLoop.fromJson(Json j) =>
      StudyLoop(start: _d(j['start']), end: _d(j['end']), name: _sn(j['name']));

  final double start;
  final double end;
  final String? name;
}

/// Bucle guardado en el proyecto.
final class StudySavedLoop {
  const StudySavedLoop({required this.id, required this.name, required this.start, required this.end});

  factory StudySavedLoop.fromJson(Json j) => StudySavedLoop(
        id: _s(j['id']),
        name: _s(j['name']),
        start: _d(j['start']),
        end: _d(j['end']),
      );

  final String id;
  final String name;
  final double start;
  final double end;
}

final class StudyChannel {
  const StudyChannel({
    required this.id,
    required this.kind,
    required this.guitarRole,
    required this.name,
    required this.gainDB,
    required this.muted,
    required this.solo,
  });

  factory StudyChannel.fromJson(Json j) => StudyChannel(
        id: _s(j['id']),
        kind: _enumOr(StudyStemKind.values, j['kind'], StudyStemKind.unknown),
        guitarRole: j['guitarRole'] == null
            ? null
            : _enumOr(StudyGuitarRole.values, j['guitarRole'], StudyGuitarRole.unknown),
        name: _s(j['name']),
        gainDB: _d(j['gainDB']),
        muted: _b(j['muted']),
        solo: _b(j['solo']),
      );

  final String id;
  final StudyStemKind kind;
  final StudyGuitarRole? guitarRole;
  final String name;
  final double gainDB;
  final bool muted;
  final bool solo;
}

final class StudyTransport {
  const StudyTransport({
    required this.playing,
    required this.position,
    required this.duration,
    required this.rate,
    required this.transpose,
    required this.fineCents,
    required this.capo,
    required this.metronome,
    required this.loop,
    required this.masterGainDB,
    required this.channels,
    required this.anySolo,
    required this.audioError,
    required this.outputName,
  });

  factory StudyTransport.fromJson(Json j) => StudyTransport(
        playing: _b(j['playing']),
        position: _d(j['position']),
        duration: _d(j['duration']),
        rate: _d(j['rate']),
        transpose: _i(j['transpose']),
        fineCents: _d(j['fineCents']),
        capo: _i(j['capo']),
        metronome: StudyMetronome.fromJson(_map(j['metronome'])),
        loop: _opt(j['loop'], StudyLoop.fromJson),
        masterGainDB: _d(j['masterGainDB']),
        channels: _items(j['channels'], StudyChannel.fromJson),
        anySolo: _b(j['anySolo']),
        audioError: _sn(j['audioError']),
        outputName: _s(j['outputName']),
      );

  final bool playing;
  final double position;
  final double duration;
  final double rate;
  final int transpose;
  final double fineCents;
  final int capo;
  final StudyMetronome metronome;
  final StudyLoop? loop;
  final double masterGainDB;
  final List<StudyChannel> channels;
  final bool anySolo;
  final String? audioError;
  final String outputName;
}

final class StudyAudioInfo {
  const StudyAudioInfo({required this.mode, required this.outputName});

  factory StudyAudioInfo.fromJson(Json j) => StudyAudioInfo(
        mode: _enumOr(StudyAudioMode.values, j['mode'], StudyAudioMode.unknown),
        outputName: _s(j['outputName']),
      );

  final StudyAudioMode mode;
  final String outputName;
}

final class StudyEmptyStem {
  const StudyEmptyStem({required this.kind, required this.name});

  factory StudyEmptyStem.fromJson(Json j) => StudyEmptyStem(
        kind: _enumOr(StudyStemKind.values, j['kind'], StudyStemKind.unknown),
        name: _s(j['name']),
      );

  final StudyStemKind kind;
  final String name;
}


/// Respuesta de `study.open` y `study.snapshot`.
final class StudyOpenResult {
  const StudyOpenResult({
    required this.projectId,
    required this.title,
    required this.artist,
    required this.duration,
    required this.sampleRate,
    required this.loadError,
    required this.audio,
    required this.transport,
    required this.emptyStems,
    required this.usesSeparatedGuitars,
    required this.analysis,
    required this.chordOverrides,
    required this.sections,
    required this.unappliedSections,
    required this.loops,
    required this.guitars,
  });

  factory StudyOpenResult.fromJson(Json j) => StudyOpenResult(
        projectId: _s(j['projectId']),
        title: _s(j['title']),
        artist: _sn(j['artist']),
        duration: _d(j['duration']),
        sampleRate: _d(j['sampleRate']),
        loadError: _sn(j['loadError']),
        audio: StudyAudioInfo.fromJson(_map(j['audio'])),
        transport: StudyTransport.fromJson(_map(j['transport'])),
        emptyStems: _items(j['emptyStems'], StudyEmptyStem.fromJson),
        usesSeparatedGuitars: _b(j['usesSeparatedGuitars']),
        analysis: StudyAnalysisInfo.fromJson(_map(j['analysis'])),
        chordOverrides: _items(j['chordOverrides'], StudyOverrideInfo.fromJson),
        sections: _items(j['sections'], StudySectionInfo.fromJson),
        unappliedSections: _b(j['unappliedSections']),
        loops: _items(j['loops'], StudySavedLoop.fromJson),
        guitars: StudyGuitarsInfo.fromJson(_map(j['guitars'])),
      );

  final String projectId;
  final String title;
  final String? artist;
  final double duration;
  final double sampleRate;
  final String? loadError;
  final StudyAudioInfo audio;
  final StudyTransport transport;
  final List<StudyEmptyStem> emptyStems;
  final bool usesSeparatedGuitars;
  final StudyAnalysisInfo analysis;
  final List<StudyOverrideInfo> chordOverrides;
  final List<StudySectionInfo> sections;
  final bool unappliedSections;
  final List<StudySavedLoop> loops;
  final StudyGuitarsInfo guitars;
}

/// Respuesta de todas las ediciones (sin `title`, `emptyStems` ni `audio`).
final class StudyEditState {
  const StudyEditState({
    required this.analysis,
    required this.chordOverrides,
    required this.sections,
    required this.unappliedSections,
    required this.loops,
    required this.guitars,
    required this.added,
    required this.transport,
  });

  factory StudyEditState.fromJson(Json j) => StudyEditState(
        analysis: StudyAnalysisInfo.fromJson(_map(j['analysis'])),
        chordOverrides: _items(j['chordOverrides'], StudyOverrideInfo.fromJson),
        sections: _items(j['sections'], StudySectionInfo.fromJson),
        unappliedSections: _b(j['unappliedSections']),
        loops: _items(j['loops'], StudySavedLoop.fromJson),
        guitars: StudyGuitarsInfo.fromJson(_map(j['guitars'])),
        added: _sn(j['added']),
        transport: StudyTransport.fromJson(_map(j['transport'])),
      );

  final StudyAnalysisInfo analysis;
  final List<StudyOverrideInfo> chordOverrides;
  final List<StudySectionInfo> sections;
  final bool unappliedSections;
  final List<StudySavedLoop> loops;
  final StudyGuitarsInfo guitars;
  final String? added;
  final StudyTransport transport;
}

final class StudyPreviewSections {
  const StudyPreviewSections({required this.sections});

  factory StudyPreviewSections.fromJson(Json j) =>
      StudyPreviewSections(sections: _items(j['sections'], StudySectionInfo.fromJson));

  final List<StudySectionInfo> sections;
}
