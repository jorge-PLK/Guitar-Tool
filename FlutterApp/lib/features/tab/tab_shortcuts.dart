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
/// Un único `Focus` de pantalla: da igual quién tenga el foco salvo un campo de texto. Las teclas de
/// edición se filtran como la web (una sola letra/cifra/signo, flechas, Retroceso, Supr, Esc) y se
/// mandan al núcleo con `tab.edit {op:key}`; Espacio alterna el transporte de estudio.
class TabShortcuts extends ConsumerStatefulWidget {
  const TabShortcuts({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<TabShortcuts> createState() => _TabShortcutsState();
}

class _TabShortcutsState extends ConsumerState<TabShortcuts> {
  final FocusNode _node = FocusNode(debugLabel: 'TabShortcuts');

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
    if (tab == null) return KeyEventResult.ignored;
    final bool editing = tab.phase == TabPhase.ready && tab.editMode;
    final TabStore store = ref.read(tabStoreProvider.notifier);

    final String? named = _namedKey(logical);
    if (named == 'Escape') {
      if (ctrl || alt) return KeyEventResult.ignored;
      final bool hasSpan = tab.span != null || ref.read(tabStoreProvider).range != null;
      if (!editing && !hasSpan) return KeyEventResult.ignored;
      unawaited(store.key('Escape', shift: shift)); // por `key`: conserva el ancla (D3)
      return KeyEventResult.handled;
    }
    if (!editing) return KeyEventResult.ignored;

    if (ctrl || alt) {
      // Solo ⌘Z, ⇧⌘Z, ⌥Y y (Windows) Ctrl+Y.
      if (ctrl && !alt && logical == LogicalKeyboardKey.keyZ) {
        unawaited(store.key('z', shift: shift, ctrl: true));
        return KeyEventResult.handled;
      }
      if (ctrl && !alt && !shift && !mac && logical == LogicalKeyboardKey.keyY) {
        unawaited(store.redo()); // D1
        return KeyEventResult.handled;
      }
      if (alt && !ctrl && logical == LogicalKeyboardKey.keyY) {
        unawaited(store.key('y', shift: shift, alt: true));
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    String? key = named;
    if (key == null) {
      final String? ch = event.character;
      if (ch == null || ch.runes.length != 1) return KeyEventResult.ignored;
      final int code = ch.runes.first;
      if (code <= 0x20 || code == 0x7f) return KeyEventResult.ignored; // Espacio, Tab, Intro, control
      key = ch;
    }
    unawaited(store.key(key, shift: shift));
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
