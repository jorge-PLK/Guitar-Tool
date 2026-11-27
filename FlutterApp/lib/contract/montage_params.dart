import 'package:flutter/foundation.dart';

import '../core/core_client.dart' show Json;
import 'montage.dart' show MontageBoxInfo, MontageOffsetInfo, MontageResolutionInfo;

// ---------- Params ----------

/// Params vacíos (`{}`): play, pause, seek sin campos, close, snapshot, startExport, cancelExport, dismissExport, clearCuts, reveal.
@immutable
class MontageEmptyParams {
  const MontageEmptyParams();
  factory MontageEmptyParams.fromJson(Json j) => const MontageEmptyParams();
  Json toJson() => {};
}

/// `montage.open`.
@immutable
class MontageOpenParams {
  const MontageOpenParams({required this.projectId});
  factory MontageOpenParams.fromJson(Json j) => MontageOpenParams(projectId: j['projectId'] as String);
  final String projectId;
  Json toJson() => {'projectId': projectId};
}

/// `montage.setLayout`. `layout`: `side|grid|stack|single|single-landscape`.
@immutable
class MontageLayoutParams {
  const MontageLayoutParams({required this.layout});
  factory MontageLayoutParams.fromJson(Json j) => MontageLayoutParams(layout: j['layout'] as String);
  final String layout;
  Json toJson() => {'layout': layout};
}

/// `montage.setSingleRhythm`.
@immutable
class MontagePartParams {
  const MontagePartParams({this.partId});
  factory MontagePartParams.fromJson(Json j) => MontagePartParams(partId: j['partId'] as String?);
  final String? partId;
  Json toJson() => {if (partId != null) 'partId': partId};
}

/// `montage.setShowPartLabels`, `setKeepVideoAspect`, `setCutGaps`, `setCaption`.
@immutable
class MontageBoolParams {
  const MontageBoolParams({required this.on});
  factory MontageBoolParams.fromJson(Json j) => MontageBoolParams(on: j['on'] as bool);
  final bool on;
  Json toJson() => {'on': on};
}

/// `montage.moveLane`: `id` y `to` son ids de lane/parte.
@immutable
class MontageMoveLaneParams {
  const MontageMoveLaneParams({required this.id, required this.to});
  factory MontageMoveLaneParams.fromJson(Json j) => MontageMoveLaneParams(id: j['id'] as String, to: j['to'] as String);
  final String id;
  final String to;
  Json toJson() => {'id': id, 'to': to};
}

/// `montage.setPartOrder`.
@immutable
class MontageOrderParams {
  const MontageOrderParams({required this.ids});
  factory MontageOrderParams.fromJson(Json j) => MontageOrderParams(ids: [for (final i in j['ids'] as List) i as String]);
  final List<String> ids;
  Json toJson() => {'ids': ids};
}

/// `montage.addCut`. `time` = tema (s). `exact` true = sin ajustar a compás.
@immutable
class MontageAddCutParams {
  const MontageAddCutParams({required this.time, this.partId, this.exact});
  factory MontageAddCutParams.fromJson(Json j) => MontageAddCutParams(
        time: (j['time'] as num).toDouble(),
        partId: j['partId'] as String?,
        exact: j['exact'] as bool?,
      );
  final double time;
  final String? partId;
  final bool? exact;
  Json toJson() => {'time': time, if (partId != null) 'partId': partId, if (exact != null) 'exact': exact};
}

/// `montage.moveCut`. `time` = tema (s).
@immutable
class MontageCutMoveParams {
  const MontageCutMoveParams({required this.id, required this.time});
  factory MontageCutMoveParams.fromJson(Json j) => MontageCutMoveParams(id: j['id'] as String, time: (j['time'] as num).toDouble());
  final String id;
  final double time;
  Json toJson() => {'id': id, 'time': time};
}

/// `montage.setCutPart`.
@immutable
class MontageCutPartParams {
  const MontageCutPartParams({required this.id, this.partId});
  factory MontageCutPartParams.fromJson(Json j) => MontageCutPartParams(id: j['id'] as String, partId: j['partId'] as String?);
  final String id;
  final String? partId;
  Json toJson() => {'id': id, if (partId != null) 'partId': partId};
}

/// `montage.removeCut`.
@immutable
class MontageIDParams {
  const MontageIDParams({required this.id});
  factory MontageIDParams.fromJson(Json j) => MontageIDParams(id: j['id'] as String);
  final String id;
  Json toJson() => {'id': id};
}

/// `montage.setExport`. Todos opcionales. `codec`: `hevc|h264`; `container`: `mov|mp4`.
@immutable
class MontageSetExportParams {
  const MontageSetExportParams({this.codec, this.container, this.resolution, this.fps, this.normalize, this.limiter, this.trackWAVs});
  factory MontageSetExportParams.fromJson(Json j) => MontageSetExportParams(
        codec: j['codec'] as String?,
        container: j['container'] as String?,
        resolution: j['resolution'] == null ? null : MontageResolutionInfo.fromJson(j['resolution'] as Json),
        fps: (j['fps'] as num?)?.toDouble(),
        normalize: j['normalize'] as bool?,
        limiter: j['limiter'] as bool?,
        trackWAVs: j['trackWAVs'] as bool?,
      );
  final String? codec;
  final String? container;
  final MontageResolutionInfo? resolution;
  final double? fps;
  final bool? normalize;
  final bool? limiter;
  final bool? trackWAVs;
  Json toJson() => {
        if (codec != null) 'codec': codec,
        if (container != null) 'container': container,
        if (resolution != null) 'resolution': resolution!.toJson(),
        if (fps != null) 'fps': fps,
        if (normalize != null) 'normalize': normalize,
        if (limiter != null) 'limiter': limiter,
        if (trackWAVs != null) 'trackWAVs': trackWAVs,
      };
}

/// `montage.rotateTake`, `reanalyze`, `resetFraming`.
@immutable
class MontageTakeParams {
  const MontageTakeParams({required this.takeId});
  factory MontageTakeParams.fromJson(Json j) => MontageTakeParams(takeId: j['takeId'] as String);
  final String takeId;
  Json toJson() => {'takeId': takeId};
}

/// `montage.setFraming`. `mode`: `fixed|follow`. `clearManualBox` se aplica antes que `manualBox`.
@immutable
class MontageSetFramingParams {
  const MontageSetFramingParams({
    required this.takeId,
    this.mode,
    this.manualBox,
    this.clearManualBox,
    this.followZoom,
    this.followOffset,
  });
  factory MontageSetFramingParams.fromJson(Json j) => MontageSetFramingParams(
        takeId: j['takeId'] as String,
        mode: j['mode'] as String?,
        manualBox: j['manualBox'] == null ? null : MontageBoxInfo.fromJson(j['manualBox'] as Json),
        clearManualBox: j['clearManualBox'] as bool?,
        followZoom: (j['followZoom'] as num?)?.toDouble(),
        followOffset: j['followOffset'] == null ? null : MontageOffsetInfo.fromJson(j['followOffset'] as Json),
      );
  final String takeId;
  final String? mode;
  final MontageBoxInfo? manualBox;
  final bool? clearManualBox;
  final double? followZoom;
  final MontageOffsetInfo? followOffset;
  Json toJson() => {
        'takeId': takeId,
        if (mode != null) 'mode': mode,
        if (manualBox != null) 'manualBox': manualBox!.toJson(),
        if (clearManualBox != null) 'clearManualBox': clearManualBox,
        if (followZoom != null) 'followZoom': followZoom,
        if (followOffset != null) 'followOffset': followOffset!.toJson(),
      };
}

/// `montage.framingFrame`. `time` = tema (s).
@immutable
class MontageFramingFrameParams {
  const MontageFramingFrameParams({required this.takeId, required this.time});
  factory MontageFramingFrameParams.fromJson(Json j) => MontageFramingFrameParams(takeId: j['takeId'] as String, time: (j['time'] as num).toDouble());
  final String takeId;
  final double time;
  Json toJson() => {'takeId': takeId, 'time': time};
}

/// `montage.seek`. `seconds` = tema (s).
@immutable
class MontageSeekParams {
  const MontageSeekParams({required this.seconds});
  factory MontageSeekParams.fromJson(Json j) => MontageSeekParams(seconds: (j['seconds'] as num).toDouble());
  final double seconds;
  Json toJson() => {'seconds': seconds};
}

/// `montage.setPreviewFps`.
@immutable
class MontageFPSParams {
  const MontageFPSParams({required this.fps});
  factory MontageFPSParams.fromJson(Json j) => MontageFPSParams(fps: (j['fps'] as num).toDouble());
  final double fps;
  Json toJson() => {'fps': fps};
}
