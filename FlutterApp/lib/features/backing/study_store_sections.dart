part of 'study_store.dart';

/// Intenciones de transporte, análisis, secciones y guitarras (misma API que el resto del store).
extension StudyStoreSections on StudyStore {
  // Transporte

  Future<void> play() => _transportCall('study.play', _empty);
  Future<void> pause() => _transportCall('study.pause', _empty);
  Future<void> seek(double seconds) =>
      _transportCall('study.seek', StudySeekParams(seconds: seconds).toJson());
  Future<void> setRate(double rate) =>
      _transportCall('study.setRate', StudyRateParams(rate: rate).toJson());

  /// Envía solo lo que cambie el control (`semitones` o `fineCents`).
  Future<void> setTranspose({int? semitones, double? fineCents}) => _transportCall(
      'study.setTranspose', StudyTransposeParams(semitones: semitones, fineCents: fineCents).toJson());
  Future<void> setCapo(int capo) => _transportCall('study.setCapo', StudyCapoParams(capo: capo).toJson());

  /// El imán (`snap`) lo aplica el núcleo.
  Future<void> setLoop(double start, double end, {String? name, StudySnap? snap}) => _transportCall(
      'study.setLoop', StudyLoopParams(start: start, end: end, name: name, snap: snap).toJson());
  Future<void> clearLoop() => _transportCall('study.setLoop', const StudyLoopParams().toJson());

  /// Sin `gainDB`: la interfaz no lo expone.
  Future<void> setMetronome(bool on) =>
      _transportCall('study.setMetronome', StudyMetronomeParams(on: on).toJson());
  Future<void> setMix(String channel, {double? gainDB, bool? mute, bool? solo}) => _transportCall(
      'study.setMix', StudyMixParams(channel: channel, gainDB: gainDB, mute: mute, solo: solo).toJson());
  Future<void> setMaster(double gainDB) =>
      _transportCall('study.setMaster', StudyMasterParams(gainDB: gainDB).toJson());

  /// «Sin guitarras» (D-9): un `setMix` por canal de guitarra. Activo = todas silenciadas; entonces restaura.
  Future<void> toggleNoGuitars() async {
    final guitars = [
      for (final c in state.transport?.channels ?? const <StudyChannel>[])
        if (c.kind == StudyStemKind.guitar) c,
    ];
    if (guitars.isEmpty) return;
    final mute = !guitars.every((c) => c.muted);
    for (final c in guitars) {
      await setMix(c.id, mute: mute);
    }
  }

  // Análisis y acordes

  Future<void> analyze() => _edit('study.analyze', _empty);

  /// `null` vuelve a la tonalidad detectada.
  Future<void> setKey(String? key) => _edit('study.setKey', StudySetKeyParams(key: key).toJson());

  /// Tonalidad tal como se ve (transpuesta); el núcleo deshace la transposición.
  Future<void> setKeyShown(StudyShownKey shown) =>
      _edit('study.setKey', StudySetKeyParams(shown: shown).toJson());

  /// Forma de un acorde por índice; `capo` ausente = el del transporte. No cambia el estado.
  Future<StudyChordShapeResult?> chordShape(int index, {int? capo}) => _call(
      'study.chordShape',
      StudyChordShapeParams(index: index, capo: capo).toJson(),
      StudyChordShapeResult.fromJson);
  Future<void> setChord(double start, double end, {int? index, String? label}) => _edit(
      'study.setChord', StudySetChordParams(start: start, end: end, index: index, label: label).toJson());
  Future<void> removeChordOverrides(double start, double end) =>
      _edit('study.removeChordOverrides', StudyChordRangeParams(start: start, end: end).toJson());
  Future<void> clearChordOverrides() => _edit('study.clearChordOverrides', _empty);
  Future<void> splitChord(double at) => _edit('study.splitChord', StudySplitChordParams(at: at).toJson());

  // Secciones

  /// Devuelve el id de la sección nueva.
  Future<String?> markSection(double start, double end, {bool? solo, StudySnap? snap}) async =>
      (await _edit('study.markSection',
              StudyMarkSectionParams(start: start, end: end, solo: solo, snap: snap).toJson()))
          ?.added;
  Future<void> updateSection(StudyUpdateSectionParams p) => _edit('study.updateSection', p.toJson());

  /// No cambia el estado ni emite `study.state`; vale la última respuesta de un arrastre.
  Future<List<StudySectionInfo>?> previewSectionEdge(StudyPreviewSectionEdgeParams p) async =>
      (await _call('study.previewSectionEdge', p.toJson(), StudyPreviewSections.fromJson))?.sections;
  Future<void> nudgeSectionEdge(String id, {required bool start, required bool forward, bool? bar}) =>
      _edit('study.nudgeSectionEdge',
          StudyNudgeSectionParams(id: id, start: start, forward: forward, bar: bar).toJson());
  Future<void> deleteSection(String id) =>
      _edit('study.deleteSection', StudyDeleteSectionParams(id: id).toJson());
  Future<void> applySections() => _edit('study.applySections', _empty);
  Future<void> discardSections() => _edit('study.discardSections', _empty);

  // Guitarras

  Future<void> renameGuitar(StudyGuitarRole role, String name) =>
      _edit('study.renameGuitar', StudyRenameGuitarParams(role: role, name: name).toJson());
  Future<void> setGuitarStereo(bool on) =>
      _edit('study.setGuitarStereo', StudyGuitarStereoParams(on: on).toJson());
}
