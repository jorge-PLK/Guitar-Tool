import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/backing/study_position.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/section_popover_state.dart';
import 'package:toneforge/features/backing/widgets/section_selection.dart';

/// Espacio: reproducir/pausar (`ctl.togglePlay()`, SectionGridBoxes.swift:114-130).
class TogglePlayIntent extends Intent {
  const TogglePlayIntent();
}

/// ¿El foco está en un campo de texto? Entonces los atajos de Backing no se disparan.
bool primaryFocusIsTextInput() {
  final BuildContext? ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  if (ctx.widget is EditableText) return true;
  return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// Supr / Retroceso: borra la sección seleccionada (`selection.clear()` + `removeSection`, SGB:151).
class DeleteSectionIntent extends Intent {
  const DeleteSectionIntent();
}

/// Esc: quita la selección de sección (SGB:155); no con la hoja de sección abierta.
class ClearSectionSelectionIntent extends Intent {
  const ClearSectionSelectionIntent();
}

/// Atajos de teclado de la pantalla Backing (ficha backing-interaccion §6.1).
///
/// Espacio (sin ⌘ ⌃ ⌥ ⇧, sin auto-repetición, no escribiendo). Supr/Retroceso (⇧ vale; sin ⌘ ⌃ ⌥) y Esc
/// solo actúan con una sección seleccionada y sin foco en un campo de texto; si no, dejan pasar la tecla.
class BackingShortcuts extends ConsumerStatefulWidget {
  const BackingShortcuts({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<BackingShortcuts> createState() => _BackingShortcutsState();
}

class _BackingShortcutsState extends ConsumerState<BackingShortcuts> {
  final FocusNode _node = FocusNode(debugLabel: 'BackingShortcuts');

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final bool playing = ref.read(studyPositionProvider).playing;
    final StudyStore store = ref.read(studyStoreProvider.notifier);
    unawaited(playing ? store.pause() : store.play());
  }

  /// Con la hoja de sección abierta, Supr/Retroceso no borran y Esc lo cierra la propia hoja.
  bool get _hasSelection =>
      ref.read(sectionSelectionProvider) != null && ref.read(sectionPopoverProvider) == null;

  void _deleteSection() {
    final String? id = ref.read(sectionSelectionProvider);
    if (id == null) return;
    ref.read(sectionSelectionProvider.notifier).clear();
    unawaited(ref.read(studyStoreProvider.notifier).deleteSection(id));
  }

  void _clearSelection() => ref.read(sectionSelectionProvider.notifier).clear();

  /// Un clic fuera de un campo de texto devuelve el foco a los atajos.
  void _onPointerDown(PointerDownEvent _) {
    if (!primaryFocusIsTextInput()) _node.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    // Mantiene viva la posición para conocer `playing` aunque nadie más la observe.
    ref.listen(studyPositionProvider, (_, _) {});
    return Listener(
      onPointerDown: _onPointerDown,
      child: Shortcuts(
        shortcuts: <ShortcutActivator, Intent>{
          const SingleActivator(LogicalKeyboardKey.space, includeRepeats: false): const TogglePlayIntent(),
          for (final bool shift in <bool>[false, true]) ...<ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.delete, shift: shift, includeRepeats: false):
                const DeleteSectionIntent(),
            SingleActivator(LogicalKeyboardKey.backspace, shift: shift, includeRepeats: false):
                const DeleteSectionIntent(),
            SingleActivator(LogicalKeyboardKey.escape, shift: shift, includeRepeats: false):
                const ClearSectionSelectionIntent(),
          },
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            TogglePlayIntent: _GuardedAction<TogglePlayIntent>(_togglePlay),
            DeleteSectionIntent: _GuardedAction<DeleteSectionIntent>(_deleteSection, when: () => _hasSelection),
            ClearSectionSelectionIntent:
                _GuardedAction<ClearSectionSelectionIntent>(_clearSelection, when: () => _hasSelection),
          },
          child: Focus(focusNode: _node, autofocus: true, child: widget.child),
        ),
      ),
    );
  }
}

/// Acción que se desactiva (y deja pasar la tecla) mientras se escribe en un campo de texto.
class _GuardedAction<T extends Intent> extends Action<T> {
  _GuardedAction(this._run, {this.when});

  final VoidCallback _run;

  /// Condición extra (p. ej. «hay sección seleccionada»); sin ella solo cuenta no estar escribiendo.
  final bool Function()? when;

  @override
  bool isEnabled(T intent) => !primaryFocusIsTextInput() && (when?.call() ?? true);

  @override
  Object? invoke(T intent) {
    _run();
    return null;
  }
}
