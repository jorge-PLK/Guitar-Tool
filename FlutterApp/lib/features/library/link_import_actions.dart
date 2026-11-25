part of 'link_import_store.dart';

/// Cancelar, reintentar, reiniciar y errores de la hoja «Importar desde enlace».
extension LinkImportStoreActions on LinkImportStore {
  // ---- Cancelar y reintentar ----

  /// «Cancelar»: resolviendo → `link.cancel`; trabajando → `link.cancel {jobId}`;
  /// error o banner → vuelve a candidatos o al campo vacío.
  Future<void> _cancel() async {
    final s = _s;
    switch (s.screen) {
      case LinkImportScreen.resolving || LinkImportScreen.preparing:
        _pass++;
        unawaited(_cancelResolution());
        _s = s.copyWith(passRunning: false, screen: LinkImportScreen.empty);
      case LinkImportScreen.working:
        if (!s.canCancel) return;
        final id = s.jobId;
        if (id == null) {
          _pass++;
          _back(passRunning: false);
          return;
        }
        // La vuelta a candidatos llega con `link.finished` (`cancelled`).
        await cancelJob(id);
      case LinkImportScreen.error || LinkImportScreen.candidates:
        if (s.passRunning) _pass++;
        _back(passRunning: false);
      default:
        break;
    }
  }

  Future<void> _cancelResolution() async {
    try {
      await _core.call('link.cancel', const LinkCancelParams().toJson(), CancelledResult.fromJson);
    } on CoreError {
      // ya había terminado
    }
  }

  /// `link.cancel {jobId}`: para la X de la fila `link-…` de la Biblioteca (nunca `jobs.cancel`).
  Future<CoreError?> cancelJob(String jobId) async {
    try {
      await _core.call('link.cancel', LinkCancelParams(jobId: jobId).toJson(), CancelledResult.fromJson);
      return null;
    } on CoreError catch (e) {
      return e;
    }
  }

  Future<void> _retry() async {
    if (_s.passRunning) return;
    if (_lastDownload) return importSelected();
    await _resolve(_s.text.trim(), ++_pass);
  }

  /// `tools.updateYtDlp` y repite lo último (resolver, o resolver y volver a importar).
  Future<void> _updateAndRetry() async {
    if (_s.passRunning) return;
    final broken = _s.error;
    final saved = (_s.title, _s.artist, _s.selectedId);
    final pass = ++_pass;
    _s = _s.copyWith(
      screen: LinkImportScreen.working,
      passRunning: true,
      error: null,
      alreadyLatest: false,
      workPhase: LinkWorkPhase.updating,
      progress: null,
      jobId: null,
    );
    try {
      final r = await _core.call('tools.updateYtDlp', const <String, Object?>{}, UpdateYtDlpResult.fromJson);
      if (!_live(pass)) return;
      if (broken != null && broken.suggestsUpdate && r.alreadyLatest) {
        _s = _s.copyWith(screen: LinkImportScreen.error, passRunning: false, error: broken, alreadyLatest: true);
        return;
      }
    } on CoreError catch (e) {
      if (_live(pass)) _showError(e);
      return;
    }
    final ok = await _resolve(_s.text.trim(), pass, quiet: true);
    if (!ok || !_live(pass)) return;
    for (final link in [..._manualLinks]) {
      try {
        await _core.call('link.addManual', LinkAddManualParams(url: link).toJson(), LinkAddManualResult.fromJson);
      } on CoreError {
        // un enlace manual que ya no sirve no impide el reintento
      }
      if (!_live(pass)) return;
    }
    final still = _s.resolved?.candidates.any((c) => c.id == saved.$3) ?? false;
    _s = _s.copyWith(title: saved.$1, artist: saved.$2, selectedId: still ? saved.$3 : _s.selectedId);
    if (_lastDownload) await importSelected();
  }

  /// «Probar con otro enlace» / apertura de la hoja: campo vacío. Un trabajo en curso sigue
  /// (su `link.finished` solo se atiende para la alerta de duplicado).
  void _reset() {
    if (_s.passRunning && _s.screen == LinkImportScreen.resolving) unawaited(_cancelResolution());
    _pass++;
    _searchSeq++;
    _importing = false;
    _early.clear();
    _manualLinks.clear();
    _lastDownload = false;
    _source = null;
    _s = LinkImportState(duplicateOf: _s.duplicateOf);
  }

  // ---- Interno ----

  void _back({bool passRunning = false}) => _s = _s.copyWith(
    screen: _s.resolved != null ? LinkImportScreen.candidates : LinkImportScreen.empty,
    passRunning: passRunning,
    error: null,
    jobId: null,
    progress: null,
  );

  /// Error del núcleo → pantalla de error; los de «vuelve a candidatos» dejan un banner.
  void _showError(CoreError e) {
    if (e.code == 'cancelled') {
      _back();
      return;
    }
    final err = LinkImportError.fromCore(e);
    final toCandidates = err.returnsToCandidates && _s.resolved != null;
    _s = _s.copyWith(
      screen: toCandidates ? LinkImportScreen.candidates : LinkImportScreen.error,
      passRunning: false,
      error: err,
    );
  }
}
