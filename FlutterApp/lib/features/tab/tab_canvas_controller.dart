import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/backing/study_position.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/widgets/tf_web_view.dart';

/// Ruta absoluta de `tab.html` dentro de `flutter_assets` del paquete (Mac: `.app/Contents/Frameworks/App.framework`;
/// Windows: `data\flutter_assets` junto al .exe). Los tests la sustituyen.
final tabCanvasHtmlPathProvider = Provider<String>((ref) {
  const key = 'assets/alphatab/tab.html';
  final exeDir = File(Platform.resolvedExecutable).parent;
  return Platform.isWindows
      ? '${exeDir.path}\\data\\flutter_assets\\${key.replaceAll('/', '\\')}'
      : '${exeDir.parent.path}/Frameworks/App.framework/Resources/flutter_assets/$key';
});

/// Estado de vista del lienzo: `webError` es el D1 (mensaje de la página, sin método en el núcleo).
final class TabCanvasState {
  const TabCanvasState({this.pageReady = false, this.rendered = false, this.webError});

  /// La página avisó `ready` (alphaTab cargado).
  final bool pageReady;

  /// La última partitura cargada ya se pintó.
  final bool rendered;

  /// Texto del último fallo de alphaTab o de la carga; se borra al pintar una partitura.
  final String? webError;

  TabCanvasState copyWith({bool? pageReady, bool? rendered, Object? webError = _keep}) => TabCanvasState(
        pageReady: pageReady ?? this.pageReady,
        rendered: rendered ?? this.rendered,
        webError: identical(webError, _keep) ? this.webError : webError as String?,
      );
}

const Object _keep = Object();

/// Lienzo alphaTab (autoDispose: vive mientras haya un [TabCanvas] o alguien lo escuche).
final tabCanvasProvider =
    NotifierProvider.autoDispose<TabCanvasController, TabCanvasState>(TabCanvasController.new);

/// Máximo que se extrapola la posición sin evento nuevo (el núcleo emite a ≤ 30 Hz).
const double _maxExtrapolationSeconds = 0.2;

/// Puente alphaTab <-> `tab.*`: crea el WebView, reenvía los mensajes de la página al store y lleva al lienzo
/// partitura, selección, tramo y cursor. Sin lógica de negocio.
class TabCanvasController extends Notifier<TabCanvasState> {
  late final TfWebViewController web;
  late final Ticker _ticker;

  int _loadGen = 0;
  (int, String?, String)? _loadedKey;
  bool _dragBusy = false;
  TabClickParams? _dragPending;

  // Cursor: ancla de `study.position` y última hora enviada al lienzo.
  double _anchorSeconds = 0;
  Duration _anchorAt = Duration.zero;
  Duration _lastElapsed = Duration.zero;
  bool _playing = false;
  double? _lastCursor;

  TabStore get _store => ref.read(tabStoreProvider.notifier);

  @override
  TabCanvasState build() {
    web = ref.read(tfWebViewControllerFactoryProvider)(TfWebViewConfig(
      onMessage: _onMessage,
      onError: (d) => _fail(d),
    ));
    _ticker = Ticker(_onTick);
    ref.onDispose(() {
      _ticker.dispose();
      web.dispose();
    });
    ref.listen(
      tabStoreProvider.select((s) => (s.tab?.revision ?? -1, s.tab?.selectedTrack, _readyKey(s.tab))),
      (_, _) => unawaited(_reload()),
    );
    ref.listen(tabStoreProvider.select((s) => s.selection), (_, _) => _pushSelection());
    ref.listen(tabStoreProvider.select((s) => s.range), (_, _) => _pushRange());
    ref.listen(studyPositionProvider, (_, e) => _onPosition(e));
    unawaited(web.loadFile(ref.read(tabCanvasHtmlPathProvider)).catchError((Object e) => _fail('$e')));
    return const TabCanvasState();
  }

  static String _readyKey(TabState? t) =>
      [for (final x in t?.tracks ?? const <TabTrackInfo>[]) if (x.transcription == TabTranscription.ready) x.id].join(',');

  void _fail(String message) {
    if (ref.mounted) state = state.copyWith(webError: message);
  }

  void _js(String js) {
    unawaited(web.runJavaScript(js).catchError((Object e) => _fail('$e')));
  }

  // ---- JS -> Dart ----

  void _onMessage(Object? json) {
    if (!ref.mounted || json is! Map) return;
    int i(String k) => (json[k] as num?)?.toInt() ?? 0;
    switch (json['event']) {
      case 'ready':
        state = state.copyWith(pageReady: true);
        unawaited(_reload());
        _pushSelection();
        _pushRange();
      case 'rendered':
        state = state.copyWith(rendered: true, webError: null);
        _lastCursor = null;
        _pushSelection();
        _pushRange();
        _pushCursor(_currentSeconds());
      case 'beatClick':
        unawaited(_store.beatClick(
            TabClickParams(track: i('track'), bar: i('bar'), beat: i('beat'), shift: json['shift'] == true)));
      case 'beatDrag':
        _drag(TabClickParams(track: i('track'), bar: i('bar'), beat: i('beat')));
      case 'noteClick':
        // Con ⇧ lo trata el beatClick (store.js:69); `fret` no se reenvía.
        if (json['shift'] == true) return;
        unawaited(_store.noteClick(TabClickParams(
            track: i('track'), bar: i('bar'), beat: i('beat'), string: i('string'), shift: false)));
      case 'error':
        _fail('${json['message'] ?? ''}');
      default: // `cursor` y desconocidos: se ignoran
    }
  }

  /// D9: una petición de arrastre viva; mientras vuela solo se guarda la última.
  void _drag(TabClickParams p) {
    if (_dragBusy) {
      _dragPending = p;
      return;
    }
    _dragBusy = true;
    unawaited(_runDrag(p));
  }

  Future<void> _runDrag(TabClickParams first) async {
    var current = first;
    try {
      while (true) {
        await _store.beatDrag(current);
        final next = _dragPending;
        _dragPending = null;
        if (next == null || !ref.mounted) return;
        current = next;
      }
    } finally {
      _dragBusy = false;
      _dragPending = null;
    }
  }

  // ---- Partitura ----

  /// `tab.score` + `TF.load` cuando cambia `revision`, la pista visible o el conjunto de pistas listas.
  Future<void> _reload() async {
    if (!ref.mounted || !state.pageReady) return;
    final tab = ref.read(tabStoreProvider).tab;
    if (tab == null) return;
    final ready = [for (final t in tab.tracks) if (t.transcription == TabTranscription.ready) t.id];
    if (ready.isEmpty) return;
    final selected = tab.selectedTrack;
    if (selected == null || !ready.contains(selected)) {
      await _store.selectTrack(ready.first); // el nuevo tab.state vuelve a disparar la recarga
      return;
    }
    final key = (tab.revision, selected, ready.join(','));
    if (key == _loadedKey) return;
    final gen = ++_loadGen;
    final r = await _store.score(track: selected);
    if (r == null || gen != _loadGen || !ref.mounted) return;
    _loadedKey = key;
    state = state.copyWith(rendered: false);
    _lastCursor = null;
    _js('TF.load(${jsonEncode(r.json)}, ${r.trackIndex});');
  }

  void _pushSelection() {
    if (!state.pageReady) return;
    final s = ref.read(tabStoreProvider).selection;
    _js(s == null ? 'TF.setSelection(-1, 0);' : 'TF.setSelection(${s.bar}, ${s.fraction});');
  }

  void _pushRange() {
    if (!state.pageReady) return;
    final r = ref.read(tabStoreProvider).range;
    _js(r == null
        ? 'TF.setRange(-1, 0, -1, 0);'
        : 'TF.setRange(${r.startBar}, ${r.startFraction}, ${r.endBar}, ${r.endFraction});');
  }

  // ---- Cursor (D3): `study.position` interpolada por fotograma ----

  void _onPosition(StudyPositionEvent e) {
    _anchorSeconds = e.seconds;
    _anchorAt = _lastElapsed;
    _playing = e.playing;
    _pushCursor(e.seconds);
    if (_playing && !_ticker.isActive) {
      _lastElapsed = Duration.zero;
      _anchorAt = Duration.zero;
      _ticker.start();
    } else if (!_playing && _ticker.isActive) {
      _ticker.stop();
    }
  }

  double _currentSeconds() {
    if (!_playing) return _anchorSeconds;
    final dt = (_lastElapsed - _anchorAt).inMicroseconds / 1e6;
    return _anchorSeconds + dt.clamp(0, _maxExtrapolationSeconds);
  }

  void _onTick(Duration elapsed) {
    _lastElapsed = elapsed;
    _pushCursor(_currentSeconds());
  }

  /// Solo llama al lienzo si la hora cambió y la partitura está pintada.
  void _pushCursor(double seconds) {
    if (!state.rendered || seconds == _lastCursor) return;
    _lastCursor = seconds;
    _js('TF.setCursorTime($seconds, true);');
  }

  // ---- Export ----

  /// `.gp` en base64 que genera alphaTab (`TF.exportGpBase64`); `null` si falla (el error queda en `webError`).
  Future<String?> exportGpBase64() async {
    try {
      final v = await web.evaluateJavaScript('TF.exportGpBase64({})');
      final s = v?.toString() ?? '';
      return s.isEmpty ? null : s;
    } catch (e) {
      _fail('$e');
      return null;
    }
  }
}
