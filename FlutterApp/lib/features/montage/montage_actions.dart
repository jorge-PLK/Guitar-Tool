part of 'montage_store.dart';

/// Una acción por método de `montage.*` que usa la pantalla. Todas aplican el snapshot de la respuesta
/// (salvo `seek`, `reveal` y `framingFrame`). Devuelven `true` si el núcleo respondió bien.
extension MontageActions on MontageStore {
  Future<bool> _empty(String method) => act(method, const MontageEmptyParams().toJson());

  Future<bool> _on(String method, bool on) => act(method, MontageBoolParams(on: on).toJson());

  Future<bool> play() => _empty('montage.play');
  Future<bool> pause() => _empty('montage.pause');

  /// `layout`: `side|grid|stack|single|single-landscape`.
  Future<bool> setLayout(String layout) => act('montage.setLayout', MontageLayoutParams(layout: layout).toJson());

  /// `partId` nulo = automática.
  Future<bool> setSingleRhythm(String? partId) =>
      act('montage.setSingleRhythm', MontagePartParams(partId: partId).toJson());

  Future<bool> setCutGaps(bool on) => _on('montage.setCutGaps', on);
  Future<bool> setCaption(bool on) => _on('montage.setCaption', on);
  Future<bool> setShowPartLabels(bool on) => _on('montage.setShowPartLabels', on);
  Future<bool> setKeepVideoAspect(bool on) => _on('montage.setKeepVideoAspect', on);

  Future<bool> moveLane(String id, String to) => act('montage.moveLane', MontageMoveLaneParams(id: id, to: to).toJson());

  Future<bool> moveCut(String id, double time) => act('montage.moveCut', MontageCutMoveParams(id: id, time: time).toJson());

  /// Consulta de solo lectura (`montage.snapCut`): tiempo de [id] ajustado al pulso y a los vecinos. No toca el estado.
  /// `null` si falló (el error queda en `actionError`).
  Future<double?> snapCut(String id, double time) async {
    try {
      final r = await _core.call('montage.snapCut', MontageSnapCutParams(id: id, time: time).toJson(), MontageSnapCutResult.fromJson);
      return r.time;
    } catch (e) {
      _fail(e);
      return null;
    }
  }

  /// Consulta de solo lectura (`montage.framingBox`): caja efectiva en [time] con los overrides dados. No toca el estado.
  /// `null` si falló; con éxito, `box` nulo = sin caja.
  Future<MontageFramingBoxResult?> framingBox(
    String takeId,
    double time, {
    String? mode,
    MontageBoxInfo? manualBox,
    double? followZoom,
    MontageOffsetInfo? followOffset,
  }) async {
    try {
      return await _core.call(
        'montage.framingBox',
        MontageFramingBoxParams(
          takeId: takeId,
          time: time,
          mode: mode,
          manualBox: manualBox,
          followZoom: followZoom,
          followOffset: followOffset,
        ).toJson(),
        MontageFramingBoxResult.fromJson,
      );
    } catch (e) {
      _fail(e);
      return null;
    }
  }

  Future<bool> setCutPart(String id, String? partId) =>
      act('montage.setCutPart', MontageCutPartParams(id: id, partId: partId).toJson());

  Future<bool> removeCut(String id) => act('montage.removeCut', MontageIDParams(id: id).toJson());
  Future<bool> clearCuts() => _empty('montage.clearCuts');

  /// Parcial: solo se envía lo no nulo.
  Future<bool> setExport({
    String? codec,
    String? container,
    MontageResolutionInfo? resolution,
    double? fps,
    bool? normalize,
    bool? limiter,
    bool? trackWAVs,
  }) =>
      act(
        'montage.setExport',
        MontageSetExportParams(
          codec: codec,
          container: container,
          resolution: resolution,
          fps: fps,
          normalize: normalize,
          limiter: limiter,
          trackWAVs: trackWAVs,
        ).toJson(),
      );

  Future<bool> cancelExport() => _empty('montage.cancelExport');
  Future<bool> dismissExport() => _empty('montage.dismissExport');

  /// «Mostrar en Finder/Explorador»; `true` si el núcleo lo mostró.
  Future<bool> reveal() async {
    try {
      final r = await _core.call('montage.reveal', const MontageEmptyParams().toJson(), MontageRevealResult.fromJson);
      return r.revealed;
    } catch (e) {
      _fail(e);
      return false;
    }
  }

  /// Solo se envía lo no nulo; `clearManualBox` borra la caja manual y se aplica antes que `manualBox`.
  Future<bool> setFraming(
    String takeId, {
    String? mode,
    MontageBoxInfo? manualBox,
    bool clearManualBox = false,
    double? followZoom,
    MontageOffsetInfo? followOffset,
  }) =>
      act(
        'montage.setFraming',
        MontageSetFramingParams(
          takeId: takeId,
          mode: mode,
          manualBox: manualBox,
          clearManualBox: clearManualBox ? true : null,
          followZoom: followZoom,
          followOffset: followOffset,
        ).toJson(),
      );

  Future<bool> resetFraming(String takeId) => act('montage.resetFraming', MontageTakeParams(takeId: takeId).toJson());
  Future<bool> reanalyze(String takeId) => act('montage.reanalyze', MontageTakeParams(takeId: takeId).toJson());
  Future<bool> rotateTake(String takeId) => act('montage.rotateTake', MontageTakeParams(takeId: takeId).toJson());

  /// `montage.setPreviewFps` (1...60).
  Future<bool> setPreviewFps(double fps) => act('montage.setPreviewFps', MontageFPSParams(fps: fps).toJson());

  /// Fotograma de la hoja de encuadre. `path` llega relativa a la carpeta del tema (MO6): se resuelve aquí.
  Future<MontageFrame?> framingFrame(String takeId, double time) async {
    try {
      final r = await _core.call(
        'montage.framingFrame',
        MontageFramingFrameParams(takeId: takeId, time: time).toJson(),
        MontageFramingFrameResult.fromJson,
      );
      final folder = themeFolder;
      return MontageFrame(
        result: r,
        themeFolder: folder,
        absolutePath: folder == null ? r.path : joinPath(folder, r.path, windows: Platform.isWindows),
      );
    } catch (e) {
      _fail(e);
      return null;
    }
  }
}
