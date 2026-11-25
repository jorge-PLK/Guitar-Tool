part of 'study.dart';

// Eventos

final class StudyPositionEvent {
  const StudyPositionEvent({required this.seconds, required this.playing});

  factory StudyPositionEvent.fromJson(Json j) =>
      StudyPositionEvent(seconds: _d(j['seconds']), playing: _b(j['playing']));

  final double seconds;
  final bool playing;
}

final class StudyMeter {
  const StudyMeter({required this.rmsDB, required this.peakDB});

  factory StudyMeter.fromJson(Json j) =>
      StudyMeter(rmsDB: _d(j['rmsDB']), peakDB: _d(j['peakDB']));

  final double rmsDB;
  final double peakDB;
}

final class StudyLevelsEvent {
  const StudyLevelsEvent({required this.channels});

  factory StudyLevelsEvent.fromJson(Json j) => StudyLevelsEvent(
        channels: {for (final e in _map(j['channels']).entries) e.key: StudyMeter.fromJson(_map(e.value))},
      );

  final Map<String, StudyMeter> channels;
}

/// Payload de `study.analysis`.
final class StudyAnalysisEvent {
  const StudyAnalysisEvent({required this.state, required this.error, this.analysis});

  factory StudyAnalysisEvent.fromJson(Json j) => StudyAnalysisEvent(
        state: _enumOr(StudyAnalysisState.values, j['state'], StudyAnalysisState.unknown),
        error: _sn(j['error']),
        analysis: _opt(j['analysis'], StudyAnalysisInfo.fromJson),
      );

  final StudyAnalysisState state;
  final String? error;

  /// Análisis completo con los acordes recalculados (tras transpose/capo/key).
  final StudyAnalysisInfo? analysis;
}

/// Payload de `study.guitars`.
final class StudyGuitarsEvent {
  const StudyGuitarsEvent({required this.state, required this.error});

  factory StudyGuitarsEvent.fromJson(Json j) => StudyGuitarsEvent(
        state: _enumOr(StudyGuitarProcess.values, j['state'], StudyGuitarProcess.unknown),
        error: _sn(j['error']),
      );

  final StudyGuitarProcess state;
  final String? error;
}
