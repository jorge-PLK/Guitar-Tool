import 'package:flutter/foundation.dart';

import '../core/core_client.dart' show Json;
import 'record_state.dart';

export 'record_state.dart';

// Eventos `record.position` y `record.levels`.

/// Payload de `record.position`: posición del reproductor de Grabar.
@immutable
class RecordPositionEvent {
  const RecordPositionEvent({required this.phase, required this.playing, required this.seconds});
  factory RecordPositionEvent.fromJson(Json j) => RecordPositionEvent(
        phase: enumOf(RecordPhase.values, RecordPhase.unknown, j['phase']),
        playing: j['playing'] as bool,
        seconds: j['seconds'] as num,
      );
  final RecordPhase phase;
  final bool playing;
  final num seconds;
  Json toJson() => {'phase': phase.name, 'playing': playing, 'seconds': seconds};
}

/// Nivel de un canal: pico y RMS en dB.
@immutable
class RecordLevel {
  const RecordLevel({required this.peakDB, required this.rmsDB});
  factory RecordLevel.fromJson(Json j) => RecordLevel(peakDB: j['peakDB'] as num, rmsDB: j['rmsDB'] as num);
  final num peakDB;
  final num rmsDB;
  Json toJson() => {'peakDB': peakDB, 'rmsDB': rmsDB};
}

/// Payload de `record.levels`: niveles por id de canal.
@immutable
class RecordLevelsEvent {
  const RecordLevelsEvent({required this.channels});
  factory RecordLevelsEvent.fromJson(Json j) => RecordLevelsEvent(
        channels: {
          for (final e in (j['channels'] as Map).entries) e.key as String: RecordLevel.fromJson(e.value as Json),
        },
      );
  final Map<String, RecordLevel> channels;
  Json toJson() => {
        'channels': {for (final e in channels.entries) e.key: e.value.toJson()},
      };
}

// Params de los métodos `record.*`. Un fixture `{}` decodifica a [RecordEmptyParams].

/// Params vacíos (`{}`).
@immutable
class RecordEmptyParams {
  const RecordEmptyParams();
  factory RecordEmptyParams.fromJson(Json j) => const RecordEmptyParams();
  Json toJson() => {};
}

/// `record.addPart`.
@immutable
class RecordAddPartParams {
  const RecordAddPartParams({required this.name, this.replaces});
  factory RecordAddPartParams.fromJson(Json j) => RecordAddPartParams(
        name: j['name'] as String,
        replaces: j['replaces'] as String?,
      );
  final String name;
  final String? replaces;
  Json toJson() => {'name': name, if (replaces != null) 'replaces': replaces};
}

/// `record.adjustOffset`, `record.deleteTake`, `record.markBest`, `record.selectTake`.
/// `takeId` ausente en `record.selectTake.none`.
@immutable
class RecordTakeParams {
  const RecordTakeParams({this.takeId});
  factory RecordTakeParams.fromJson(Json j) => RecordTakeParams(takeId: j['takeId'] as String?);
  final String? takeId;
  Json toJson() => {if (takeId != null) 'takeId': takeId};
}

/// `record.finishOffset`.
@immutable
class RecordFinishOffsetParams {
  const RecordFinishOffsetParams({required this.save, this.makeDefault});
  factory RecordFinishOffsetParams.fromJson(Json j) => RecordFinishOffsetParams(
        save: j['save'] as bool,
        makeDefault: j['makeDefault'] as bool?,
      );
  final bool save;
  final bool? makeDefault;
  Json toJson() => {'save': save, if (makeDefault != null) 'makeDefault': makeDefault};
}

/// `record.open`.
@immutable
class RecordOpenParams {
  const RecordOpenParams({this.projectId});
  factory RecordOpenParams.fromJson(Json j) => RecordOpenParams(projectId: j['projectId'] as String?);
  final String? projectId;
  Json toJson() => {if (projectId != null) 'projectId': projectId};
}

/// `record.selectPart`.
@immutable
class RecordPartParams {
  const RecordPartParams({required this.partId});
  factory RecordPartParams.fromJson(Json j) => RecordPartParams(partId: j['partId'] as String);
  final String partId;
  Json toJson() => {'partId': partId};
}

/// `record.setCamera`. `cameraId` ausente en el fixture.
@immutable
class RecordCameraParams {
  const RecordCameraParams({this.cameraId});
  factory RecordCameraParams.fromJson(Json j) => RecordCameraParams(cameraId: j['cameraId'] as String?);
  final String? cameraId;
  Json toJson() => {if (cameraId != null) 'cameraId': cameraId};
}

/// `record.setCountIn`.
@immutable
class RecordOnParams {
  const RecordOnParams({required this.on});
  factory RecordOnParams.fromJson(Json j) => RecordOnParams(on: j['on'] as bool);
  final bool on;
  Json toJson() => {'on': on};
}

/// `record.setMaster`.
@immutable
class RecordMasterParams {
  const RecordMasterParams({required this.gainDB});
  factory RecordMasterParams.fromJson(Json j) => RecordMasterParams(gainDB: j['gainDB'] as num);
  final num gainDB;
  Json toJson() => {'gainDB': gainDB};
}

/// `record.setMix`.
@immutable
class RecordMixParams {
  const RecordMixParams({required this.channel, this.gainDB, this.mute, this.solo});
  factory RecordMixParams.fromJson(Json j) => RecordMixParams(
        channel: j['channel'] as String,
        gainDB: j['gainDB'] as num?,
        mute: j['mute'] as bool?,
        solo: j['solo'] as bool?,
      );
  final String channel;
  final num? gainDB;
  final bool? mute;
  final bool? solo;
  Json toJson() => {
        'channel': channel,
        if (gainDB != null) 'gainDB': gainDB,
        if (mute != null) 'mute': mute,
        if (solo != null) 'solo': solo,
      };
}

/// `record.setOffset`.
@immutable
class RecordOffsetParams {
  const RecordOffsetParams({this.valueMs, this.deltaMs, this.frames});
  factory RecordOffsetParams.fromJson(Json j) => RecordOffsetParams(
        valueMs: j['valueMs'] as num?,
        deltaMs: j['deltaMs'] as num?,
        frames: j['frames'] as num?,
      );
  final num? valueMs;
  final num? deltaMs;
  final num? frames;
  Json toJson() => {
        if (valueMs != null) 'valueMs': valueMs,
        if (deltaMs != null) 'deltaMs': deltaMs,
        if (frames != null) 'frames': frames,
      };
}

/// `record.setPreRoll`.
@immutable
class RecordBarsParams {
  const RecordBarsParams({required this.bars});
  factory RecordBarsParams.fromJson(Json j) => RecordBarsParams(bars: j['bars'] as int);
  final int bars;
  Json toJson() => {'bars': bars};
}

/// `record.setPunch`. `entry` y `exit` viajan como `in` y `out`.
@immutable
class RecordPunchParams {
  const RecordPunchParams({this.enabled, this.entry, this.exit, this.clearIn, this.clearOut, this.free});
  factory RecordPunchParams.fromJson(Json j) => RecordPunchParams(
        enabled: j['enabled'] as bool?,
        entry: j['in'] as num?,
        exit: j['out'] as num?,
        clearIn: j['clearIn'] as bool?,
        clearOut: j['clearOut'] as bool?,
        free: j['free'] as bool?,
      );
  final bool? enabled;
  final num? entry;
  final num? exit;
  final bool? clearIn;
  final bool? clearOut;
  final bool? free;
  Json toJson() => {
        if (enabled != null) 'enabled': enabled,
        if (entry != null) 'in': entry,
        if (exit != null) 'out': exit,
        if (clearIn != null) 'clearIn': clearIn,
        if (clearOut != null) 'clearOut': clearOut,
        if (free != null) 'free': free,
      };
}

/// `record.setStartSection`.
@immutable
class RecordSectionParams {
  const RecordSectionParams({this.sectionId});
  factory RecordSectionParams.fromJson(Json j) => RecordSectionParams(sectionId: j['sectionId'] as String?);
  final String? sectionId;
  Json toJson() => {if (sectionId != null) 'sectionId': sectionId};
}

// Result que no es snapshot.

/// `record.prepareViewTake`.
@immutable
class RecordAllowedResult {
  const RecordAllowedResult({required this.allowed});
  factory RecordAllowedResult.fromJson(Json j) => RecordAllowedResult(allowed: j['allowed'] as bool);
  final bool allowed;
  Json toJson() => {'allowed': allowed};
}
