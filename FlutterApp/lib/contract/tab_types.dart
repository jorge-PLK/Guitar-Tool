part of 'tab.dart';

/// Afinación de una pista. `strings`: MIDI de la cuerda 1 (la más aguda) a la última.
final class TabTuningInfo {
  const TabTuningInfo({
    required this.preset,
    required this.name,
    required this.strings,
  });

  factory TabTuningInfo.fromJson(Json j) => TabTuningInfo(
        preset: _enumOr(TabTuningPreset.values, j['preset'], TabTuningPreset.unknown),
        name: _s(j['name']),
        strings: _ints(j['strings']),
      );

  final TabTuningPreset preset;
  final String name;
  final List<int> strings;
}

/// Origen del archivo fuente de una pista (TabKit).
final class TrackSourceFingerprint {
  const TrackSourceFingerprint({
    required this.path,
    required this.size,
    required this.modifiedMillis,
    required this.modelVersion,
    required this.parametersVersion,
  });

  factory TrackSourceFingerprint.fromJson(Json j) => TrackSourceFingerprint(
        path: _s(j['path']),
        size: _i(j['size']),
        modifiedMillis: _i(j['modifiedMillis']),
        modelVersion: _s(j['modelVersion']),
        parametersVersion: _i(j['parametersVersion']),
      );

  final String path;
  final int size;
  final int modifiedMillis;
  final String modelVersion;
  final int parametersVersion;
}

final class TabTrackInfo {
  const TabTrackInfo({
    required this.id,
    required this.name,
    required this.kind,
    required this.origin,
    required this.transcription,
    required this.noteCount,
    required this.muted,
    required this.solo,
    required this.dimmed,
    required this.listening,
    this.tuning,
    this.customTuning,
    this.playerTrack,
    this.progress,
    this.error,
    this.fingerprint,
    this.synth,
  });

  factory TabTrackInfo.fromJson(Json j) => TabTrackInfo(
        id: _s(j['id']),
        name: _s(j['name']),
        kind: _enumOr(TabTrackKind.values, j['kind'], TabTrackKind.unknown),
        origin: _enumOr(TabOrigin.values, j['origin'], TabOrigin.unknown),
        transcription: _enumOr(
          TabTranscription.values,
          j['transcription'],
          TabTranscription.unknown,
        ),
        noteCount: _i(j['noteCount']),
        muted: _b(j['muted']),
        solo: _b(j['solo']),
        dimmed: _b(j['dimmed']),
        listening: _b(j['listening']),
        tuning: _opt(j['tuning'], TabTuningInfo.fromJson),
        customTuning: _opt(j['customTuning'], TabTuningInfo.fromJson),
        playerTrack: _sn(j['playerTrack']),
        progress: _dn(j['progress']),
        error: _sn(j['error']),
        fingerprint: _opt(j['fingerprint'], TrackSourceFingerprint.fromJson),
        synth: _enumN(TabSynth.values, j['synth'], TabSynth.unknown),
      );

  final String id;
  final String name;
  final TabTrackKind kind;
  final TabOrigin origin;
  final TabTranscription transcription;
  final int noteCount;
  final bool muted;
  final bool solo;
  final bool dimmed;
  final bool listening;
  final TabTuningInfo? tuning;
  final TabTuningInfo? customTuning;
  final String? playerTrack;
  final double? progress;
  final String? error;
  final TrackSourceFingerprint? fingerprint;
  final TabSynth? synth;
}

final class TabBarRange {
  const TabBarRange({required this.bar, required this.start, required this.end});

  factory TabBarRange.fromJson(Json j) => TabBarRange(
        bar: _i(j['bar']),
        start: _d(j['start']),
        end: _d(j['end']),
      );

  Json toJson() => <String, Object?>{'bar': bar, 'start': start, 'end': end};

  /// 0-based.
  final int bar;
  final double start;
  final double end;
}

final class TabSelectionInfo {
  const TabSelectionInfo({
    required this.track,
    required this.beat,
    required this.tick,
    required this.hasNote,
    this.string,
    this.summary,
    this.barRange,
  });

  factory TabSelectionInfo.fromJson(Json j) => TabSelectionInfo(
        track: _s(j['track']),
        beat: _i(j['beat']),
        tick: _i(j['tick']),
        hasNote: _b(j['hasNote']),
        string: _in(j['string']),
        summary: _sn(j['summary']),
        barRange: _opt(j['barRange'], TabBarRange.fromJson),
      );

  Json toJson() => <String, Object?>{
        'track': track,
        'beat': beat,
        'tick': tick,
        'hasNote': hasNote,
        if (string != null) 'string': string,
        if (summary != null) 'summary': summary,
        if (barRange != null) 'barRange': barRange!.toJson(),
      };

  final String track;
  final int beat;
  final int tick;

  /// Hay una nota bajo la selección (`sin nota` en el resumen cuando es `false`).
  final bool hasNote;
  final int? string;
  final String? summary;
  final TabBarRange? barRange;
}

final class TabSpanInfo {
  const TabSpanInfo({required this.startTick, required this.endTick});

  factory TabSpanInfo.fromJson(Json j) =>
      TabSpanInfo(startTick: _i(j['startTick']), endTick: _i(j['endTick']));

  final int startTick;
  final int endTick;
}

/// Estado de `tab`. `TabState.phase` = `not-open` no existe: sin tablatura es RPC `not-open`.
final class TabState {
  const TabState({
    required this.projectId,
    required this.phase,
    required this.tracks,
    required this.notices,
    required this.canUndo,
    required this.canRedo,
    required this.editMode,
    required this.graceMode,
    required this.listenMode,
    required this.anySolo,
    required this.revision,
    this.error,
    this.header,
    this.source,
    this.selectedTrack,
    this.selection,
    this.span,
    this.flash,
    this.handled,
  });

  factory TabState.fromJson(Json j) => TabState(
        projectId: _s(j['projectId']),
        phase: _enumOr(TabPhase.values, j['phase'], TabPhase.unknown),
        error: _sn(j['error']),
        header: _sn(j['header']),
        source: _enumN(TabSource.values, j['source'], TabSource.unknown),
        tracks: _items(j['tracks'], TabTrackInfo.fromJson),
        selectedTrack: _sn(j['selectedTrack']),
        notices: _strs(j['notices']),
        canUndo: _b(j['canUndo']),
        canRedo: _b(j['canRedo']),
        editMode: _b(j['editMode']),
        graceMode: _b(j['graceMode']),
        listenMode: _enumOr(
          TabListenMode.values,
          j['listenMode'],
          TabListenMode.unknown,
        ),
        anySolo: _b(j['anySolo']),
        selection: _opt(j['selection'], TabSelectionInfo.fromJson),
        span: _opt(j['span'], TabSpanInfo.fromJson),
        revision: _i(j['revision']),
        flash: _sn(j['flash']),
        handled: _bn(j['handled']),
      );

  final String projectId;
  final TabPhase phase;
  /// Solo con `failed`.
  final String? error;
  /// Ej. «4/4 · 120 BPM».
  final String? header;
  /// Ausente = sin elegir.
  final TabSource? source;
  final List<TabTrackInfo> tracks;
  final String? selectedTrack;
  final List<String> notices;
  final bool canUndo;
  final bool canRedo;
  final bool editMode;
  final bool graceMode;
  final TabListenMode listenMode;
  final bool anySolo;
  final TabSelectionInfo? selection;
  final TabSpanInfo? span;
  final int revision;
  final String? flash;
  /// Solo en `tab.edit` con `op:"key"`.
  final bool? handled;
}
