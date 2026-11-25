part of 'tab.dart';

// Emparejado de pistas de Songsterr con las del proyecto.

final class SongsterrPairingInfo {
  const SongsterrPairingInfo({
    required this.intro,
    required this.slots,
    required this.extraNames,
    required this.warnings,
    this.extraText,
  });

  factory SongsterrPairingInfo.fromJson(Json j) => SongsterrPairingInfo(
        intro: _s(j['intro']),
        slots: _items(j['slots'], SongsterrSlotInfo.fromJson),
        extraNames: _strs(j['extraNames']),
        extraText: _sn(j['extraText']),
        warnings: _strs(j['warnings']),
      );

  final String intro;
  final List<SongsterrSlotInfo> slots;
  final List<String> extraNames;
  final String? extraText;
  final List<String> warnings;
}

/// `stemId` = `TabSource.id` (con guion); no coincide con los raw de `role`.
final class SongsterrSlotInfo {
  const SongsterrSlotInfo({
    required this.stemId,
    required this.name,
    required this.kind,
    required this.role,
    required this.choices,
    required this.solos,
    this.track,
    this.confidence,
    this.confidenceText,
  });

  factory SongsterrSlotInfo.fromJson(Json j) => SongsterrSlotInfo(
        stemId: _s(j['stemId']),
        name: _s(j['name']),
        kind: _enumOr(TabTrackKind.values, j['kind'], TabTrackKind.unknown),
        role: _enumOr(TabSongsterrRole.values, j['role'], TabSongsterrRole.unknown),
        track: _in(j['track']),
        confidence: _dn(j['confidence']),
        confidenceText: _sn(j['confidenceText']),
        choices: _items(j['choices'], SongsterrChoiceInfo.fromJson),
        solos: _items(j['solos'], SongsterrSoloRowInfo.fromJson),
      );

  final String stemId;
  final String name;
  final TabTrackKind kind;
  final TabSongsterrRole role;
  final int? track;
  final double? confidence;
  final String? confidenceText;
  final List<SongsterrChoiceInfo> choices;
  /// Solo se rellena en el slot `lead`.
  final List<SongsterrSoloRowInfo> solos;
}

final class SongsterrSoloRowInfo {
  const SongsterrSoloRowInfo({
    required this.index,
    required this.start,
    required this.end,
    required this.clock,
    required this.choices,
    this.track,
    this.confidence,
    this.confidenceText,
  });

  factory SongsterrSoloRowInfo.fromJson(Json j) => SongsterrSoloRowInfo(
        index: _i(j['index']),
        start: _d(j['start']),
        end: _d(j['end']),
        clock: _s(j['clock']),
        track: _in(j['track']),
        confidence: _dn(j['confidence']),
        confidenceText: _sn(j['confidenceText']),
        choices: _items(j['choices'], SongsterrChoiceInfo.fromJson),
      );

  final int index;
  final double start;
  final double end;
  final String clock;
  final int? track;
  final double? confidence;
  final String? confidenceText;
  final List<SongsterrChoiceInfo> choices;
}

final class SongsterrChoiceInfo {
  const SongsterrChoiceInfo({
    required this.track,
    required this.name,
    required this.label,
    this.similarity,
  });

  factory SongsterrChoiceInfo.fromJson(Json j) => SongsterrChoiceInfo(
        track: _i(j['track']),
        name: _s(j['name']),
        label: _s(j['label']),
        similarity: _dn(j['similarity']),
      );

  final int track;
  final String name;
  final String label;
  final double? similarity;
}
