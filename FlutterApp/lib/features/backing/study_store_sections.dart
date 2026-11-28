part of 'study_store.dart';

const String _masterKey = '\u0000master';
const String _fineKey = '\u0000fine';
const String _rateKey = '\u0000rate';

/// Faders en arrastre: valor local mostrado, última posición pendiente y canales con llamada en vuelo.
final class _GainQueue {
  final Map<String, double> local = <String, double>{};
  final Map<String, double> pending = <String, double>{};
  final Set<String> inFlight = <String>{};
  double? rateBase;
}

/// Intenciones de transporte, análisis, secciones y guitarras (misma API que el resto del store).
extension StudyStoreSections on StudyStore {
  // Transporte

  Future<void> play() => _transportCall('study.play', _empty);
  Future<void> pause() => _transportCall('study.pause', _empty);
  Future<void> seek(double seconds) =>
      _transportCall('study.seek', StudySeekParams(seconds: seconds).toJson());
  Future<void> setRate(double rate) =>
      _transportCall('study.setRate', StudyRateParams(rate: rate).toJson());

  /// Arrastre del tempo: solo valor local (el núcleo reinicia la pasada con cada `setRate`).
  void dragRate(double rate) {
    final g = _gain;
    if (!g.local.containsKey(_rateKey)) g.rateBase = _cur.transport?.rate;
    g.local[_rateKey] = rate;
    _showLocalGain();
  }

  /// Al soltar: un único `setRate` si el valor difiere del que tenía el núcleo al empezar.
  Future<void> commitRate(double rate) async {
    final g = _gain;
    final base = g.rateBase ?? _cur.transport?.rate;
    g.rateBase = null;
    if (base == null || (base - rate).abs() < 1e-9) {
      if (base != null) {
        g.local[_rateKey] = base;
        _showLocalGain();
      }
      g.local.remove(_rateKey);
      return;
    }
    g.local[_rateKey] = rate;
    _showLocalGain();
    try {
      await setRate(rate);
    } finally {
      g.local.remove(_rateKey);
      final t = _cur.transport;
      if (_isOpen && t != null) _cur = _cur.copyWith(study: _withTransport(_cur.study!, _overlayGain(t)));
    }
  }

  /// Envía solo lo que cambie el control (`semitones` o `fineCents`). `fineCents` solo: una llamada
  /// en vuelo, la última gana, valor local mientras tanto.
  Future<void> setTranspose({int? semitones, double? fineCents}) {
    if (fineCents != null && semitones == null) {
      return _dragGain(_fineKey, fineCents, 'study.setTranspose',
          (v) => StudyTransposeParams(fineCents: v).toJson());
    }
    return _transportCall(
        'study.setTranspose', StudyTransposeParams(semitones: semitones, fineCents: fineCents).toJson());
  }
  Future<void> setCapo(int capo) => _transportCall('study.setCapo', StudyCapoParams(capo: capo).toJson());

  /// El imán (`snap`) lo aplica el núcleo.
  Future<void> setLoop(double start, double end, {String? name, StudySnap? snap}) => _transportCall(
      'study.setLoop', StudyLoopParams(start: start, end: end, name: name, snap: snap).toJson());
  Future<void> clearLoop() => _transportCall('study.setLoop', const StudyLoopParams().toJson());

  /// Sin `gainDB`: la interfaz no lo expone.
  Future<void> setMetronome(bool on) =>
      _transportCall('study.setMetronome', StudyMetronomeParams(on: on).toJson());

  /// Solo `gainDB` (arrastre del fader): una llamada en vuelo por canal, la última posición gana y
  /// lo mostrado sigue al puntero (valor local) hasta reconciliar con la respuesta del núcleo.
  Future<void> setMix(String channel, {double? gainDB, bool? mute, bool? solo}) {
    if (gainDB != null && mute == null && solo == null) {
      return _dragGain(channel, gainDB, 'study.setMix',
          (v) => StudyMixParams(channel: channel, gainDB: v).toJson());
    }
    return _transportCall(
        'study.setMix', StudyMixParams(channel: channel, gainDB: gainDB, mute: mute, solo: solo).toJson());
  }

  Future<void> setMaster(double gainDB) => _dragGain(
      _masterKey, gainDB, 'study.setMaster', (v) => StudyMasterParams(gainDB: v).toJson());

  Future<void> _dragGain(String key, double v, String method, Object? Function(double) params) async {
    final g = _gain;
    g.local[key] = v;
    g.pending[key] = v;
    _showLocalGain();
    if (!g.inFlight.add(key)) return;
    StudyTransport? last;
    while (g.pending.containsKey(key)) {
      final x = g.pending.remove(key)!;
      last = await _call(method, params(x), StudyTransport.fromJson) ?? last;
    }
    g.inFlight.remove(key);
    g.local.remove(key);
    if (!_isOpen) return;
    if (last == null) {
      _showLocalGain();
      await refresh();
    } else {
      _cur = _cur.copyWith(study: _withTransport(_cur.study!, _overlayGain(last)), clearError: true);
    }
  }

  void _showLocalGain() {
    final t = _cur.transport;
    if (!_isOpen || t == null) return;
    _cur = _cur.copyWith(study: _withTransport(_cur.study!, _overlayGain(t)));
  }

  StudyTransport _overlayGain(StudyTransport t) {
    final l = _gain.local;
    if (l.isEmpty) return t;
    return StudyTransport(
      playing: t.playing,
      position: t.position,
      duration: t.duration,
      rate: l[_rateKey] ?? t.rate,
      transpose: t.transpose,
      fineCents: l[_fineKey] ?? t.fineCents,
      capo: t.capo,
      metronome: t.metronome,
      loop: t.loop,
      masterGainDB: l[_masterKey] ?? t.masterGainDB,
      channels: [
        for (final c in t.channels)
          if (l.containsKey(c.id))
            StudyChannel(
                id: c.id,
                kind: c.kind,
                guitarRole: c.guitarRole,
                name: c.name,
                gainDB: l[c.id]!,
                muted: c.muted,
                solo: c.solo)
          else
            c,
      ],
      anySolo: t.anySolo,
      audioError: t.audioError,
      outputName: t.outputName,
      audioErrorCode: t.audioErrorCode,
    );
  }

  /// «Sin guitarras» (D-9): un `setMix` por canal de guitarra. Activo = todas silenciadas; entonces restaura.
  Future<void> toggleNoGuitars() async {
    final guitars = [
      for (final c in _cur.transport?.channels ?? const <StudyChannel>[])
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

  /// Vocabulario de acordes (no exige tema abierto); no cambia el estado.
  Future<StudyChordVocabulary?> chordVocabulary() =>
      _call('study.chordVocabulary', _empty, StudyChordVocabulary.fromJson);

  /// Solo uno de [index], [label] y [shown] (acorde tal como se ve; el núcleo destranspone).
  Future<void> setChord(double start, double end, {int? index, String? label, StudyShownChord? shown}) =>
      _edit(
          'study.setChord',
          StudySetChordParams(start: start, end: end, index: index, label: label, shown: shown)
              .toJson());
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
