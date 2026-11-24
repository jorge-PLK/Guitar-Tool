import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/host_pickers.dart';
import 'package:toneforge/contract/jobs.dart';
import 'package:toneforge/contract/link_import.dart';
import 'package:toneforge/contract/link_resolve.dart';
import 'package:toneforge/contract/tools.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/features/library/link_import_logic.dart';

export 'package:toneforge/features/library/link_import_logic.dart';

/// Hoja «Importar tema / desde enlace». Sin autoDispose: `link.finished` (duplicado,
/// cancelación) puede llegar con la hoja ya cerrada; la hoja llama a `reset()` al abrirse.
final linkImportStoreProvider = NotifierProvider<LinkImportStore, LinkImportState>(
  LinkImportStore.new,
);

class LinkImportStore extends Notifier<LinkImportState> {
  CoreClient get _core => ref.read(coreClientProvider);

  int _pass = 0;
  int _searchSeq = 0;
  bool _lastDownload = false;
  LinkSource? _source;
  final _manualLinks = <String>[];

  /// Trabajos `link-N` propios sin `link.finished` todavía (incluye los de hojas ya reiniciadas).
  final _jobs = <String>{};
  bool _importing = false;
  final _early = <LinkFinished>[];

  @override
  LinkImportState build() {
    final subs = [
      _core.on<JobInfo>('jobs.progress', JobInfo.fromJson).listen(_onJob),
      _core.on<LinkFinished>('link.finished', LinkFinished.fromJson).listen(_onFinished),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });
    return const LinkImportState();
  }

  bool _live(int pass) => ref.mounted && pass == _pass;

  // ---- Campo y Spotify ----

  void setText(String t) => state = state.copyWith(text: t, spotifyError: null);

  void dismissDuplicate() => state = state.copyWith(duplicateOf: null);

  /// «Importar» / Intro: clasifica; pista o lista → resolver; lo demás → buscar en Spotify.
  Future<void> submit() async {
    if (!state.canSubmit) return;
    final text = state.text.trim();
    final pass = ++_pass;
    state = state.copyWith(passRunning: true, spotifyError: null, error: null);
    final LinkClassifyResult c;
    try {
      c = await _core.call('link.classify', LinkURLParams(url: text).toJson(), LinkClassifyResult.fromJson);
    } on CoreError catch (e) {
      if (_live(pass)) _showError(e);
      return;
    }
    if (!_live(pass)) return;
    if (c.kind == LinkKind.track || c.kind == LinkKind.playlist) {
      _lastDownload = false;
      _manualLinks.clear();
      _source = c.source;
      await _resolve(text, pass);
    } else {
      state = state.copyWith(passRunning: false);
      await _search(text);
    }
  }

  Future<void> _search(String query) async {
    final seq = ++_searchSeq;
    state = state.copyWith(searching: true, spotifyTracks: null, spotifyQuery: null, spotifyError: null);
    try {
      final r = await _core.call('link.search', LinkSearchParams(query: query).toJson(), LinkSearchResult.fromJson);
      if (!ref.mounted || seq != _searchSeq) return;
      state = state.copyWith(searching: false, spotifyQuery: r.query, spotifyTracks: r.tracks);
    } on CoreError catch (e) {
      if (!ref.mounted || seq != _searchSeq) return;
      state = state.copyWith(searching: false, spotifyError: e.code == 'cancelled' ? null : e);
    }
  }

  /// «Elegir» de un resultado de Spotify: sigue el recorrido con su enlace.
  Future<void> chooseSpotifyTrack(LinkSpotifyTrack track) async {
    if (state.busy) return;
    _searchSeq++;
    _lastDownload = false;
    _manualLinks.clear();
    _source = LinkSource.spotify;
    state = state.copyWith(text: track.trackURL, spotifyTracks: null, spotifyQuery: null);
    await _resolve(track.trackURL, ++_pass);
  }

  /// ▶ «Oír en Spotify»: abre [url] (app) y, si no se puede, [fallback] (web).
  Future<void> openSpotify(String url, {String? fallback}) async {
    try {
      await _core.call(
        'host.openURL',
        OpenURLParams(urls: [url, ?fallback]).toJson(),
        OpenURLResult.fromJson,
      );
    } on CoreError {
      // sin navegador: no hay nada más que hacer
    }
  }

  // ---- Resolver y elegir ----

  /// [quiet]: no cambia a «resolviendo» (el reintento tras actualizar sigue en «Trabajando»).
  Future<bool> _resolve(String url, int pass, {bool quiet = false}) async {
    if (!quiet) {
      state = state.copyWith(
        screen: LinkImportScreen.resolving,
        passRunning: true,
        resolved: null,
        error: null,
        manualError: null,
        alreadyLatest: false,
        resolvePhase: _source == LinkSource.spotify ? LinkResolvePhase.searching : LinkResolvePhase.metadata,
      );
    }
    try {
      final r = await _core.call('link.resolve', LinkURLParams(url: url).toJson(), LinkResolveResult.fromJson);
      if (!_live(pass)) return false;
      final snap = r.playlistSnapshot;
      if (snap != null) {
        state = state.copyWith(screen: LinkImportScreen.playlist, passRunning: false, playlist: snap);
        return false;
      }
      if (r.existing != null) {
        state = state.copyWith(screen: LinkImportScreen.repeated, passRunning: false, resolved: r);
        return false;
      }
      final first = r.candidates.isEmpty ? null : r.candidates.first;
      state = state.copyWith(
        screen: LinkImportScreen.candidates,
        passRunning: false,
        resolved: r,
        title: r.title,
        artist: r.artist ?? '',
        selectedId: first != null && first.isClose && first.difference == null ? first.id : null,
      );
      return true;
    } on CoreError catch (e) {
      if (_live(pass)) _showError(e);
      return false;
    }
  }

  void selectCandidate(String id) {
    for (final c in state.resolved?.candidates ?? const <LinkCandidateInfo>[]) {
      if (c.id == id && c.inLibrary == null) {
        state = state.copyWith(selectedId: id);
        return;
      }
    }
  }

  void setTitle(String t) => state = state.copyWith(title: t);

  void setArtist(String a) => state = state.copyWith(artist: a);

  void swap() => state = state.copyWith(title: state.artist, artist: state.title);

  /// Añade un vídeo de YouTube pegado a mano a los candidatos.
  Future<void> addManual(String url) async {
    final t = url.trim();
    if (t.isEmpty || state.resolved == null || state.busy) return;
    final pass = _pass;
    state = state.copyWith(passRunning: true, manualError: null);
    try {
      final r = await _core.call('link.addManual', LinkAddManualParams(url: t).toJson(), LinkAddManualResult.fromJson);
      if (!_live(pass)) return;
      _manualLinks.add(t);
      state = state.copyWith(
        passRunning: false,
        resolved: r.resolution,
        selectedId: r.selectable ? r.added : null,
        error: null,
      );
    } on CoreError catch (e) {
      if (!_live(pass)) return;
      state = state.copyWith(passRunning: false, manualError: e.code == 'cancelled' ? null : e);
    }
  }

  // ---- Importar ----

  Future<void> importSelected() async {
    final c = state.selectedCandidate;
    if (c == null || state.busy) return;
    _lastDownload = true;
    final pass = ++_pass;
    final params = LinkImportParams(candidateId: c.id, title: state.title, artist: state.artist);
    state = state.copyWith(
      screen: LinkImportScreen.working,
      passRunning: true,
      error: null,
      alreadyLatest: false,
      workPhase: LinkWorkPhase.downloading,
      progress: null,
      jobId: null,
    );
    _importing = true;
    _early.clear();
    try {
      final r = await _core.call('link.import', params.toJson(), LinkJobResult.fromJson);
      _jobs.add(r.jobId);
      if (!_live(pass)) {
        // Cancelado mientras se encolaba: se cancela el trabajo recién creado.
        unawaited(cancelJob(r.jobId));
        return;
      }
      state = state.copyWith(jobId: r.jobId, passRunning: false);
    } on CoreError catch (e) {
      _importing = false;
      _early.clear();
      if (_live(pass)) _showError(e);
      return;
    }
    _importing = false;
    final early = [..._early];
    _early.clear();
    for (final f in early) {
      _handleFinished(f);
    }
  }

  void _onJob(JobInfo j) {
    if (!ref.mounted || j.id != state.jobId || state.screen != LinkImportScreen.working) return;
    state = state.copyWith(progress: j.fraction, workPhase: workPhaseOf(j));
  }

  void _onFinished(LinkFinished f) {
    if (!ref.mounted) return;
    if (_importing) {
      _early.add(f);
      return;
    }
    _handleFinished(f);
  }

  void _handleFinished(LinkFinished f) {
    if (!_jobs.remove(f.jobId)) return;
    if (f.jobId != state.jobId) {
      // Trabajo de una hoja ya reiniciada: solo importa el duplicado (alerta).
      if (f.duplicate && f.id != null) state = state.copyWith(duplicateOf: f.id);
      return;
    }
    final err = f.error;
    if (err != null) {
      state = state.copyWith(jobId: null, progress: null);
      if (err.code == 'cancelled') {
        _back();
      } else {
        _showError(CoreError(err.code, err.message));
      }
    } else if (f.duplicate) {
      state = LinkImportState(duplicateOf: f.id ?? state.duplicateOf);
    } else {
      state = state.copyWith(
        screen: LinkImportScreen.done,
        jobId: null,
        progress: null,
        notices: f.notices,
        importedId: f.id,
      );
    }
  }

  // ---- Cancelar y reintentar ----

  /// «Cancelar»: resolviendo → `link.cancel`; trabajando → `link.cancel {jobId}`;
  /// error o banner → vuelve a candidatos o al campo vacío.
  Future<void> cancel() async {
    final s = state;
    switch (s.screen) {
      case LinkImportScreen.resolving || LinkImportScreen.preparing:
        _pass++;
        unawaited(_cancelResolution());
        state = s.copyWith(passRunning: false, screen: LinkImportScreen.empty);
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

  Future<void> retry() async {
    if (state.passRunning) return;
    if (_lastDownload) return importSelected();
    await _resolve(state.text.trim(), ++_pass);
  }

  /// `tools.updateYtDlp` y repite lo último (resolver, o resolver y volver a importar).
  Future<void> updateAndRetry() async {
    if (state.passRunning) return;
    final broken = state.error;
    final saved = (state.title, state.artist, state.selectedId);
    final pass = ++_pass;
    state = state.copyWith(
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
        state = state.copyWith(screen: LinkImportScreen.error, passRunning: false, error: broken, alreadyLatest: true);
        return;
      }
    } on CoreError catch (e) {
      if (_live(pass)) _showError(e);
      return;
    }
    final ok = await _resolve(state.text.trim(), pass, quiet: true);
    if (!ok || !_live(pass)) return;
    for (final link in [..._manualLinks]) {
      try {
        await _core.call('link.addManual', LinkAddManualParams(url: link).toJson(), LinkAddManualResult.fromJson);
      } on CoreError {
        // un enlace manual que ya no sirve no impide el reintento
      }
      if (!_live(pass)) return;
    }
    final still = state.resolved?.candidates.any((c) => c.id == saved.$3) ?? false;
    state = state.copyWith(title: saved.$1, artist: saved.$2, selectedId: still ? saved.$3 : state.selectedId);
    if (_lastDownload) await importSelected();
  }

  /// «Probar con otro enlace» / apertura de la hoja: campo vacío. Un trabajo en curso sigue
  /// (su `link.finished` solo se atiende para la alerta de duplicado).
  void reset() {
    if (state.passRunning && state.screen == LinkImportScreen.resolving) unawaited(_cancelResolution());
    _pass++;
    _searchSeq++;
    _early.clear();
    _manualLinks.clear();
    _lastDownload = false;
    _source = null;
    state = LinkImportState(duplicateOf: state.duplicateOf);
  }

  // ---- Interno ----

  void _back({bool passRunning = false}) => state = state.copyWith(
    screen: state.resolved != null ? LinkImportScreen.candidates : LinkImportScreen.empty,
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
    final toCandidates = err.returnsToCandidates && state.resolved != null;
    state = state.copyWith(
      screen: toCandidates ? LinkImportScreen.candidates : LinkImportScreen.error,
      passRunning: false,
      error: err,
    );
  }
}
