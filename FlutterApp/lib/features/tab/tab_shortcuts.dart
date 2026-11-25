import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/backing/backing_shortcuts.dart' show primaryFocusIsTextInput;
import 'package:toneforge/features/backing/study_position.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/tab/songsterr_store.dart';
import 'package:toneforge/features/tab/tab_key_map.dart';
import 'package:toneforge/features/tab/tab_store.dart';

/// Tecla pulsada dentro de la página alphaTab (`KeyboardEvent`), reenviada por `shim.js`.
final class WebKey {
  const WebKey({
    required this.key,
    required this.code,
    this.shift = false,
    this.ctrl = false,
    this.meta = false,
    this.alt = false,
  });

  final String key;
  final String code;
  final bool shift;
  final bool ctrl;
  final bool meta;
  final bool alt;
}

/// Canal de las teclas de la página hacia [TabShortcuts] (lo alimenta el controlador del lienzo).
final tabWebKeysProvider = Provider<StreamController<WebKey>>((ref) {
  final c = StreamController<WebKey>.broadcast();
  ref.onDispose(c.close);
  return c;
});

/// Nombre `KeyboardEvent.key` de una tecla no imprimible que el núcleo conoce (D9), o `null`.
String? _namedKey(LogicalKeyboardKey k) {
  if (k == LogicalKeyboardKey.arrowUp) return 'ArrowUp';
  if (k == LogicalKeyboardKey.arrowDown) return 'ArrowDown';
  if (k == LogicalKeyboardKey.arrowLeft) return 'ArrowLeft';
  if (k == LogicalKeyboardKey.arrowRight) return 'ArrowRight';
  if (k == LogicalKeyboardKey.backspace) return 'Backspace';
  if (k == LogicalKeyboardKey.delete) return 'Delete';
  if (k == LogicalKeyboardKey.escape) return 'Escape';
  return null;
}

/// Atajos de teclado de Tablatura (ficha tablatura-interaccion §6.1, D1-D9).
///
/// Un único `Focus` de pantalla: da igual quién tenga el foco salvo un campo de texto. Las teclas que
/// reclama el mapa del núcleo (`tab.keyMap`, vía [claims]) se mandan al
/// núcleo con `tab.edit {op:key}`; Espacio alterna el transporte de estudio.
class TabShortcuts extends ConsumerStatefulWidget {
  const TabShortcuts({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<TabShortcuts> createState() => _TabShortcutsState();
}

class _TabShortcutsState extends ConsumerState<TabShortcuts> {
  final FocusNode _node = FocusNode(debugLabel: 'TabShortcuts');
  StreamSubscription<WebKey>? _webKeys;

  @override
  void initState() {
    super.initState();
    ref.read(tabKeyMapProvider); // precarga: el mapa es estático
    _webKeys = ref.read(tabWebKeysProvider).stream.listen(_onWebKey);
  }

  @override
  void dispose() {
    unawaited(_webKeys?.cancel());
    _node.dispose();
    super.dispose();
  }

  /// El foco de teclado vuelve siempre a Flutter (WebView sin foco), salvo en un campo de texto.
  void _reclaim() {
    if (mounted && !primaryFocusIsTextInput()) _node.requestFocus();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final HardwareKeyboard kb = HardwareKeyboard.instance;
    final LogicalKeyboardKey logical = event.logicalKey;
    final bool handled = _dispatch(
      source: 0,
      space: logical == LogicalKeyboardKey.space,
      freshPress: event is KeyDownEvent,
      named: _namedKey(logical),
      label: logical.keyLabel,
      ch: event.character,
      isY: logical == LogicalKeyboardKey.keyY,
      meta: kb.isMetaPressed,
      control: kb.isControlPressed,
      shift: kb.isShiftPressed,
      alt: kb.isAltPressed,
    );
    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  /// Tecla que llega desde la página alphaTab cuando el WebView tiene el foco (`shim.js`, evento `key`).
  void _onWebKey(WebKey k) {
    final String name = k.key;
    final String code = k.code;
    String label = name;
    if (code.startsWith('Key') && code.length == 4) label = code.substring(3);
    if (code.startsWith('Digit') && code.length == 6) label = code.substring(5);
    _dispatch(
      source: 1,
      space: name == ' ',
      freshPress: true,
      named: name.startsWith('Arrow') || name == 'Backspace' || name == 'Delete' || name == 'Escape' ? name : null,
      label: label,
      ch: name,
      isY: code == 'KeyY',
      meta: k.meta,
      control: k.ctrl,
      shift: k.shift,
      alt: k.alt,
    );
  }

  String? _lastKey;
  int _lastSource = -1;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Misma tecla por los dos caminos (Flutter y página) en un instante: solo cuenta la primera.
  bool _duplicate(int source, String id) {
    final DateTime now = DateTime.now();
    final bool dup = id == _lastKey && source != _lastSource && now.difference(_lastAt).inMilliseconds < 80;
    _lastKey = id;
    _lastSource = source;
    _lastAt = now;
    return dup;
  }

  /// Decisión común (Flutter y página). `source`: 0 = Flutter, 1 = página. Devuelve si la tecla se consumió.
  bool _dispatch({
    required int source,
    required bool space,
    required bool freshPress,
    required String? named,
    required String label,
    required String? ch,
    required bool isY,
    required bool meta,
    required bool control,
    required bool shift,
    required bool alt,
  }) {
    if (primaryFocusIsTextInput()) return false; // D4
    if (ref.read(songsterrStoreProvider).isOpen) return false; // hoja modal
    final bool mac = defaultTargetPlatform == TargetPlatform.macOS;
    // D2: «ctrl» es ⌘ en macOS y Ctrl en Windows; el otro no vale.
    final bool ctrl = mac ? meta : control;
    final bool stray = mac ? control : meta;

    if (space) {
      if (!freshPress || shift || alt || ctrl || stray) return false;
      if (_duplicate(source, ' ')) return true;
      _togglePlay();
      return true;
    }
    if (stray) return false;

    final TabState? tab = ref.read(tabStoreProvider).tab;
    final TabKeyMapResult? map = ref.read(tabKeyMapProvider).value;
    if (tab == null || map == null) return false; // sin mapa, el núcleo no reclama
    final TabStore store = ref.read(tabStoreProvider.notifier);

    // D1: Ctrl+Y rehace en Windows (no está en el mapa del núcleo).
    if (ctrl && !alt && !shift && !mac && isY) {
      if (tab.phase != TabPhase.ready || !tab.editMode) return false;
      if (_duplicate(source, 'redo')) return true;
      unawaited(store.redo());
      return true;
    }

    String? key = named;
    if (key == null && (ctrl || alt)) {
      // Con ⌘/⌥ el carácter no sirve (¥, control): la letra física, en minúscula.
      if (label.runes.length == 1) key = label.toLowerCase();
    } else if (key == null) {
      if (ch == null || ch.runes.length != 1) return false;
      final int code = ch.runes.first;
      if (code <= 0x20 || code == 0x7f) return false; // Espacio, Tab, Intro, control
      key = ch;
    }
    if (key == null) return false;
    final bool hasRange = ref.read(tabStoreProvider).range != null;
    if (!claims(map, key: key, shift: shift, ctrl: ctrl, alt: alt, tab: tab, hasRange: hasRange)) {
      return false;
    }
    if (_duplicate(source, '$key|$shift|$ctrl|$alt')) return true;
    // Siempre por `key` (Escape incluido): conserva el ancla (D3).
    unawaited(store.key(key, shift: shift, ctrl: ctrl, alt: alt));
    return true;
  }

  void _togglePlay() {
    final bool playing = ref.read(studyPositionProvider).playing;
    final StudyStore study = ref.read(studyStoreProvider.notifier);
    unawaited(playing ? study.pause() : study.play());
  }

  @override
  Widget build(BuildContext context) {
    // Mantiene viva la posición para conocer `playing` aunque nadie más la observe.
    ref.listen(studyPositionProvider, (_, _) {});
    ref.watch(songsterrStoreProvider.select((s) => s.isOpen));
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _reclaim(),
      onPointerUp: (_) => _reclaim(),
      child: Focus(focusNode: _node, autofocus: true, onKeyEvent: _onKey, child: widget.child),
    );
  }
}
