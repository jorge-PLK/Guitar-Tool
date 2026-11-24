import 'package:flutter/foundation.dart';

import '../core/core_client.dart' show Json;
import 'core_message.dart';

/// Valor crudo no previsto → [unknown]; nunca lanza.
T enumOf<T extends Enum>(Iterable<T> values, T unknown, Object? raw) =>
    values.asNameMap()[raw] ?? unknown;

enum RecordPhase { idle, counting, recording, finishing, adjusting, unknown }

enum CameraState { simulated, live, denied, failed, none, unknown }

enum PartStatus { done, pending, unknown }

@immutable
class RecordAudio {
  const RecordAudio({required this.hosting, required this.outputName, required this.recording, required this.sessionOpen});
  factory RecordAudio.fromJson(Json j) => RecordAudio(
        hosting: j['hosting'] as bool,
        outputName: j['outputName'] as String,
        recording: j['recording'] as bool,
        sessionOpen: j['sessionOpen'] as bool,
      );
  final bool hosting;
  final String outputName;
  final bool recording;
  final bool sessionOpen;
  Json toJson() => {'hosting': hosting, 'outputName': outputName, 'recording': recording, 'sessionOpen': sessionOpen};
}

@immutable
class RecordCamera {
  const RecordCamera({
    required this.cameras,
    required this.chosenId,
    required this.defaultOffsetMs,
    required this.name,
    required this.rotation,
    required this.state,
    this.width,
    this.height,
    this.fps,
    this.label,
    this.message,
  });
  factory RecordCamera.fromJson(Json j) => RecordCamera(
        cameras: [for (final c in j['cameras'] as List) RecordCameraOption.fromJson(c as Json)],
        chosenId: j['chosenId'] as String,
        defaultOffsetMs: j['defaultOffsetMs'] as int,
        name: j['name'] as String,
        rotation: j['rotation'] as int,
        state: enumOf(CameraState.values, CameraState.unknown, j['state']),
        width: j['width'] as int?,
        height: j['height'] as int?,
        fps: j['fps'] as int?,
        label: j['label'] as String?,
        message: j['message'] as String?,
      );
  final List<RecordCameraOption> cameras;
  final String chosenId;
  final int defaultOffsetMs;
  final String name;
  final int rotation;
  final CameraState state;
  // Ausentes en denied, failed y none (fixtures).
  final int? width;
  final int? height;
  final int? fps;
  final String? label;
  final String? message;
  Json toJson() => {
        'cameras': [for (final c in cameras) c.toJson()],
        'chosenId': chosenId,
        'defaultOffsetMs': defaultOffsetMs,
        'name': name,
        'rotation': rotation,
        'state': state.name,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (fps != null) 'fps': fps,
        if (label != null) 'label': label,
        if (message != null) 'message': message,
      };
}

@immutable
class RecordCameraOption {
  const RecordCameraOption({required this.id, required this.name});
  factory RecordCameraOption.fromJson(Json j) => RecordCameraOption(id: j['id'] as String, name: j['name'] as String);
  final String id;
  final String name;
  Json toJson() => {'id': id, 'name': name};
}

@immutable
class RecordGuitarRole {
  const RecordGuitarRole({required this.name, required this.role});
  factory RecordGuitarRole.fromJson(Json j) => RecordGuitarRole(name: j['name'] as String, role: j['role'] as String);
  final String name;
  final String role;
  Json toJson() => {'name': name, 'role': role};
}

@immutable
class RecordMixChannel {
  const RecordMixChannel({
    required this.id,
    required this.kind,
    required this.name,
    required this.gainDB,
    required this.muted,
    required this.solo,
    required this.forcedMuted,
  });
  factory RecordMixChannel.fromJson(Json j) => RecordMixChannel(
        id: j['id'] as String,
        kind: j['kind'] as String,
        name: j['name'] as String,
        gainDB: j['gainDB'] as num,
        muted: j['muted'] as bool,
        solo: j['solo'] as bool,
        forcedMuted: j['forcedMuted'] as bool,
      );
  final String id;
  final String kind;
  final String name;
  final num gainDB;
  final bool muted;
  final bool solo;
  final bool forcedMuted;
  Json toJson() => {
        'forcedMuted': forcedMuted,
        'gainDB': gainDB,
        'id': id,
        'kind': kind,
        'muted': muted,
        'name': name,
        'solo': solo,
      };
}

@immutable
class RecordTakeChannel {
  const RecordTakeChannel({
    required this.id,
    required this.partId,
    required this.name,
    required this.gainDB,
    required this.muted,
    required this.solo,
  });
  factory RecordTakeChannel.fromJson(Json j) => RecordTakeChannel(
        id: j['id'] as String,
        partId: j['partId'] as String,
        name: j['name'] as String,
        gainDB: j['gainDB'] as num,
        muted: j['muted'] as bool,
        solo: j['solo'] as bool,
      );
  final String id;
  final String partId;
  final String name;
  final num gainDB;
  final bool muted;
  final bool solo;
  Json toJson() => {'gainDB': gainDB, 'id': id, 'muted': muted, 'name': name, 'partId': partId, 'solo': solo};
}

@immutable
class RecordMix {
  const RecordMix({
    required this.anySolo,
    required this.channels,
    required this.masterGainDB,
    required this.outputName,
    required this.takeChannels,
  });
  factory RecordMix.fromJson(Json j) => RecordMix(
        anySolo: j['anySolo'] as bool,
        channels: [for (final c in j['channels'] as List) RecordMixChannel.fromJson(c as Json)],
        masterGainDB: j['masterGainDB'] as num,
        outputName: j['outputName'] as String,
        takeChannels: [for (final c in j['takeChannels'] as List) RecordTakeChannel.fromJson(c as Json)],
      );
  final bool anySolo;
  final List<RecordMixChannel> channels;
  final num masterGainDB;
  final String outputName;
  final List<RecordTakeChannel> takeChannels;
  Json toJson() => {
        'anySolo': anySolo,
        'channels': [for (final c in channels) c.toJson()],
        'masterGainDB': masterGainDB,
        'outputName': outputName,
        'takeChannels': [for (final c in takeChannels) c.toJson()],
      };
}

@immutable
class RecordVideoFormat {
  const RecordVideoFormat({required this.cameraId, required this.cameraName, required this.fps, required this.height, required this.width});
  factory RecordVideoFormat.fromJson(Json j) => RecordVideoFormat(
        cameraId: j['cameraId'] as String,
        cameraName: j['cameraName'] as String,
        fps: j['fps'] as int,
        height: j['height'] as int,
        width: j['width'] as int,
      );
  final String cameraId;
  final String cameraName;
  final int fps;
  final int height;
  final int width;
  Json toJson() => {'cameraId': cameraId, 'cameraName': cameraName, 'fps': fps, 'height': height, 'width': width};
}

@immutable
class RecordTake {
  const RecordTake({
    required this.best,
    required this.createdAt,
    required this.discarded,
    required this.hasVideo,
    required this.id,
    required this.number,
    required this.punches,
    required this.selected,
    required this.videoRotation,
    this.audioPath,
    this.durationSeconds,
    this.songStart,
    this.videoFormat,
    this.videoOffsetMs,
    this.videoPath,
  });
  factory RecordTake.fromJson(Json j) => RecordTake(
        best: j['best'] as bool,
        createdAt: j['createdAt'] as String,
        discarded: j['discarded'] as bool,
        hasVideo: j['hasVideo'] as bool,
        id: j['id'] as String,
        number: j['number'] as int,
        punches: [for (final p in j['punches'] as List) RecordPunchTake.fromJson(p as Json)],
        selected: j['selected'] as bool,
        videoRotation: j['videoRotation'] as int,
        audioPath: j['audioPath'] as String?,
        durationSeconds: (j['durationSeconds'] as num?)?.toDouble(),
        songStart: (j['songStart'] as num?)?.toDouble(),
        videoFormat: j['videoFormat'] == null ? null : RecordVideoFormat.fromJson(j['videoFormat'] as Json),
        videoOffsetMs: j['videoOffsetMs'] as int?,
        videoPath: j['videoPath'] as String?,
      );
  final bool best;
  final String createdAt;
  final bool discarded;
  final bool hasVideo;
  final String id;
  final int number;
  final List<RecordPunchTake> punches;
  final bool selected;
  final int videoRotation;
  final String? audioPath;
  final double? durationSeconds;
  final double? songStart;
  // Ausentes en tomas sin vídeo.
  final RecordVideoFormat? videoFormat;
  final int? videoOffsetMs;
  final String? videoPath;
  Json toJson() => {
        'best': best,
        'createdAt': createdAt,
        'discarded': discarded,
        'hasVideo': hasVideo,
        'id': id,
        'number': number,
        'punches': [for (final p in punches) p.toJson()],
        'selected': selected,
        'videoRotation': videoRotation,
        if (audioPath != null) 'audioPath': audioPath,
        if (durationSeconds != null) 'durationSeconds': durationSeconds,
        if (songStart != null) 'songStart': songStart,
        if (videoFormat != null) 'videoFormat': videoFormat!.toJson(),
        if (videoOffsetMs != null) 'videoOffsetMs': videoOffsetMs,
        if (videoPath != null) 'videoPath': videoPath,
      };
}

/// Toma de una pasada de punch (`punches` de RecordTake / RecordOffset).
@immutable
class RecordPunchTake {
  const RecordPunchTake({required this.start, required this.end, required this.hasVideo, this.videoPath, this.videoOffsetMs});
  factory RecordPunchTake.fromJson(Json j) => RecordPunchTake(
        start: j['start'] as num,
        end: j['end'] as num,
        hasVideo: j['hasVideo'] as bool,
        videoPath: j['videoPath'] as String?,
        videoOffsetMs: j['videoOffsetMs'] as num?,
      );
  final num start;
  final num end;
  final bool hasVideo;
  final String? videoPath;
  final num? videoOffsetMs;
  Json toJson() => {
        'start': start,
        'end': end,
        'hasVideo': hasVideo,
        if (videoPath != null) 'videoPath': videoPath,
        if (videoOffsetMs != null) 'videoOffsetMs': videoOffsetMs,
      };
}

@immutable
class RecordPart {
  const RecordPart({required this.id, required this.isLead, required this.name, required this.status, required this.takes, this.bestTakeId});
  factory RecordPart.fromJson(Json j) => RecordPart(
        id: j['id'] as String,
        isLead: j['isLead'] as bool,
        name: j['name'] as String,
        status: enumOf(PartStatus.values, PartStatus.unknown, j['status']),
        takes: [for (final t in j['takes'] as List) RecordTake.fromJson(t as Json)],
        bestTakeId: j['bestTakeId'] as String?,
      );
  final String id;
  final bool isLead;
  final String name;
  final PartStatus status;
  final List<RecordTake> takes;
  final String? bestTakeId;
  Json toJson() => {
        'id': id,
        'isLead': isLead,
        'name': name,
        'status': status.name,
        'takes': [for (final t in takes) t.toJson()],
        if (bestTakeId != null) 'bestTakeId': bestTakeId,
      };
}

@immutable
class RecordSection {
  const RecordSection({required this.id, required this.name, required this.paletteIndex, required this.solo, required this.start, required this.end});
  factory RecordSection.fromJson(Json j) => RecordSection(
        id: j['id'] as String,
        name: j['name'] as String,
        paletteIndex: j['paletteIndex'] as int,
        solo: j['solo'] as bool,
        start: j['start'] as num,
        end: j['end'] as num,
      );
  final String id;
  final String name;
  final int paletteIndex;
  final bool solo;
  final num start;
  final num end;
  Json toJson() => {'end': end, 'id': id, 'name': name, 'paletteIndex': paletteIndex, 'solo': solo, 'start': start};
}

@immutable
class RecordPunch {
  const RecordPunch({required this.enabled, required this.ready, this.inSeconds, this.outSeconds});
  factory RecordPunch.fromJson(Json j) => RecordPunch(
        enabled: j['enabled'] as bool,
        ready: j['ready'] as bool,
        inSeconds: j['in'] as num?,
        outSeconds: j['out'] as num?,
      );
  final bool enabled;
  final bool ready;
  final num? inSeconds;
  final num? outSeconds;
  Json toJson() => {
        'enabled': enabled,
        'ready': ready,
        if (inSeconds != null) 'in': inSeconds,
        if (outSeconds != null) 'out': outSeconds,
      };
}

/// `offset` del snapshot (solo en la hoja de desfase). Todos los campos presentes en los fixtures.
@immutable
class RecordOffset {
  const RecordOffset({
    required this.audioPath,
    required this.cameraId,
    required this.cameraName,
    required this.fps,
    required this.frameMs,
    required this.initialMs,
    required this.isNew,
    required this.maxMs,
    required this.minMs,
    required this.punches,
    required this.rotation,
    required this.songStart,
    required this.takeId,
    required this.valueMs,
    required this.videoPath,
  });
  factory RecordOffset.fromJson(Json j) => RecordOffset(
        audioPath: j['audioPath'] as String,
        cameraId: j['cameraId'] as String,
        cameraName: j['cameraName'] as String,
        fps: j['fps'] as int,
        frameMs: j['frameMs'] as num,
        initialMs: j['initialMs'] as int,
        isNew: j['isNew'] as bool,
        maxMs: j['maxMs'] as int,
        minMs: j['minMs'] as int,
        punches: [for (final p in j['punches'] as List) RecordPunchTake.fromJson(p as Json)],
        rotation: j['rotation'] as int,
        songStart: j['songStart'] as num,
        takeId: j['takeId'] as String,
        valueMs: j['valueMs'] as int,
        videoPath: j['videoPath'] as String,
      );
  final String audioPath;
  final String cameraId;
  final String cameraName;
  final int fps;
  final num frameMs;
  final int initialMs;
  final bool isNew;
  final int maxMs;
  final int minMs;
  final List<RecordPunchTake> punches;
  final int rotation;
  final num songStart;
  final String takeId;
  final int valueMs;
  final String videoPath;
  Json toJson() => {
        'audioPath': audioPath,
        'cameraId': cameraId,
        'cameraName': cameraName,
        'fps': fps,
        'frameMs': frameMs,
        'initialMs': initialMs,
        'isNew': isNew,
        'maxMs': maxMs,
        'minMs': minMs,
        'punches': [for (final p in punches) p.toJson()],
        'rotation': rotation,
        'songStart': songStart,
        'takeId': takeId,
        'valueMs': valueMs,
        'videoPath': videoPath,
      };
}

/// `RecordSnapshot`: resultado de casi todos los `record.*` y evento `record.state`.
@immutable
class RecordSnapshot {
  const RecordSnapshot({
    required this.activePartId,
    required this.audio,
    required this.barSeconds,
    required this.beatsPerBar,
    required this.bpm,
    required this.busy,
    required this.camera,
    required this.countIn,
    required this.downbeats,
    required this.duration,
    required this.guitarRoles,
    required this.messages,
    required this.mix,
    required this.nextTakeNumber,
    required this.notices,
    required this.parts,
    required this.phase,
    required this.position,
    required this.preRollBars,
    required this.projectId,
    required this.punch,
    required this.sections,
    required this.startTime,
    required this.title,
    this.block,
    this.blockReason,
    this.countBeat,
    this.loadError,
    this.offset,
    this.plannedStop,
    this.selectedTakeId,
    this.startSectionId,
    this.takeSaveError,
  });
  factory RecordSnapshot.fromJson(Json j) => RecordSnapshot(
        activePartId: j['activePartId'] as String,
        audio: RecordAudio.fromJson(j['audio'] as Json),
        barSeconds: j['barSeconds'] as num,
        beatsPerBar: j['beatsPerBar'] as int,
        bpm: j['bpm'] as num,
        busy: j['busy'] as bool,
        camera: RecordCamera.fromJson(j['camera'] as Json),
        countIn: j['countIn'] as bool,
        downbeats: [for (final d in j['downbeats'] as List) (d as num).toDouble()],
        duration: j['duration'] as num,
        guitarRoles: [for (final r in j['guitarRoles'] as List) RecordGuitarRole.fromJson(r as Json)],
        messages: [for (final m in j['messages'] as List) m as String],
        mix: RecordMix.fromJson(j['mix'] as Json),
        nextTakeNumber: j['nextTakeNumber'] as int,
        notices: [for (final n in j['notices'] as List) n as String],
        parts: [for (final p in j['parts'] as List) RecordPart.fromJson(p as Json)],
        phase: enumOf(RecordPhase.values, RecordPhase.unknown, j['phase']),
        position: j['position'] as num,
        preRollBars: j['preRollBars'] as int,
        projectId: j['projectId'] as String,
        punch: RecordPunch.fromJson(j['punch'] as Json),
        sections: [for (final s in j['sections'] as List) RecordSection.fromJson(s as Json)],
        startTime: j['startTime'] as num,
        title: j['title'] as String,
        block: j['block'] == null ? null : CoreMessage.fromJson(j['block'] as Json),
        blockReason: j['blockReason'] as String?,
        countBeat: j['countBeat'] as int?,
        loadError: j['loadError'] as String?,
        offset: j['offset'] == null ? null : RecordOffset.fromJson(j['offset'] as Json),
        plannedStop: j['plannedStop'] as num?,
        selectedTakeId: j['selectedTakeId'] as String?,
        startSectionId: j['startSectionId'] as String?,
        takeSaveError: j['takeSaveError'] as String?,
      );
  final String activePartId;
  final RecordAudio audio;
  final num barSeconds;
  final int beatsPerBar;
  final num bpm;
  final bool busy;
  final RecordCamera camera;
  final bool countIn;
  final List<double> downbeats;
  final num duration;
  final List<RecordGuitarRole> guitarRoles;
  final List<String> messages;
  final RecordMix mix;
  final int nextTakeNumber;
  final List<String> notices;
  final List<RecordPart> parts;
  final RecordPhase phase;
  final num position;
  final int preRollBars;
  final String projectId;
  final RecordPunch punch;
  final List<RecordSection> sections;
  final num startTime;
  final String title;
  final CoreMessage? block;
  final String? blockReason;
  final int? countBeat;
  final String? loadError;
  final RecordOffset? offset;
  final num? plannedStop;
  final String? selectedTakeId;
  final String? startSectionId;
  final String? takeSaveError;
  Json toJson() => {
        'activePartId': activePartId,
        'audio': audio.toJson(),
        'barSeconds': barSeconds,
        'beatsPerBar': beatsPerBar,
        'bpm': bpm,
        'busy': busy,
        'camera': camera.toJson(),
        'countIn': countIn,
        'downbeats': downbeats,
        'duration': duration,
        'guitarRoles': [for (final r in guitarRoles) r.toJson()],
        'messages': messages,
        'mix': mix.toJson(),
        'nextTakeNumber': nextTakeNumber,
        'notices': notices,
        'parts': [for (final p in parts) p.toJson()],
        'phase': phase.name,
        'position': position,
        'preRollBars': preRollBars,
        'projectId': projectId,
        'punch': punch.toJson(),
        'sections': [for (final s in sections) s.toJson()],
        'startTime': startTime,
        'title': title,
        if (block != null) 'block': block!.toJson(),
        if (blockReason != null) 'blockReason': blockReason,
        if (countBeat != null) 'countBeat': countBeat,
        if (loadError != null) 'loadError': loadError,
        if (offset != null) 'offset': offset!.toJson(),
        if (plannedStop != null) 'plannedStop': plannedStop,
        if (selectedTakeId != null) 'selectedTakeId': selectedTakeId,
        if (startSectionId != null) 'startSectionId': startSectionId,
        if (takeSaveError != null) 'takeSaveError': takeSaveError,
      };
}
