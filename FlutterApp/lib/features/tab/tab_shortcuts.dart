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

  @override
  void initState() {
    super.initState();
    ref.read(tabKeyMapProvider); // precarga: el mapa es estático
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  /// El foco de teclado vuelve siempre a Flutter (WebView sin foco), salvo en un campo de texto.
  void _reclaim() {
    if (mounted && !primaryFocusIsTextInput()) _node.requestFocus();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (primaryFocusIsTextInput()) return KeyEventResult.ignored; // D4
    if (ref.read(songsterrStoreProvider).isOpen) return KeyEventResult.ignored; // hoja modal
    final HardwareKeyboard kb = HardwareKeyboard.instance;
    final bool mac = defaultTargetPlatform == TargetPlatform.macOS;
    // D2: «ctrl» es ⌘ en macOS y Ctrl en Windows; el otro no vale.
    final bool ctrl = mac ? kb.isMetaPressed : kb.isControlPressed;
    final bool stray = mac ? kb.isControlPressed : kb.isMetaPressed;
    final bool shift = kb.isShiftPressed;
    final bool alt = kb.isAltPressed;
    final LogicalKeyboardKey logical = event.logicalKey;

    if (logical == LogicalKeyboardKey.space) {
      if (event is! KeyDownEvent || shift || alt || ctrl || stray) return KeyEventResult.ignored;
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (stray) return KeyEventResult.ignored;

    final TabState? tab = ref.read(tabStoreProvider).tab;
    final TabKeyMapResult? map = ref.read(tabKeyMapProvider).value;
    if (tab == null || map == null) return KeyEventResult.ignored; // sin mapa, el núcleo no reclama
    final TabStore store = ref.read(tabStoreProvider.notifier);

    // D1: Ctrl+Y rehace en Windows (no está en el mapa del núcleo).
    if (ctrl && !alt && !shift && !mac && logical == LogicalKeyboardKey.keyY) {
      if (tab.phase != TabPhase.ready || !tab.editMode) return KeyEventResult.ignored;
      unawaited(store.redo());
      return KeyEventResult.handled;
    }

    String? key = _namedKey(logical);
    if (key == null && (ctrl || alt)) {
      // Con ⌘/⌥ el carácter no sirve (¥, control): la letra física, en minúscula.
      final String label = logical.keyLabel;
      if (label.runes.length == 1) key = label.toLowerCase();
    } else if (key == null) {
      final String? ch = event.character;
      if (ch == null || ch.runes.length != 1) return KeyEventResult.ignored;
      final int code = ch.runes.first;
      if (code <= 0x20 || code == 0x7f) return KeyEventResult.ignored; // Espacio, Tab, Intro, control
      key = ch;
    }
    if (key == null) return KeyEventResult.ignored;
    final bool hasRange = ref.read(tabStoreProvider).range != null;
    if (!claims(map, key: key, shift: shift, ctrl: ctrl, alt: alt, tab: tab, hasRange: hasRange)) {
      return KeyEventResult.ignored;
    }
    // Siempre por `key` (Escape incluido): conserva el ancla (D3).
    unawaited(store.key(key, shift: shift, ctrl: ctrl, alt: alt));
    return KeyEventResult.handled;
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
