import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/backing/study_position.dart';
import 'package:toneforge/features/backing/study_store.dart';

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

/// Atajos de teclado de la pantalla Backing (ficha backing-interaccion §6.1).
///
/// Hechos: Espacio (sin ⌘ ⌃ ⌥ ⇧, sin auto-repetición, no escribiendo).
/// Pendientes: Supr/Retroceso (borrar sección) y Esc (deseleccionar) necesitan la selección de
/// secciones, que aún no existe en la vista.
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
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.space, includeRepeats: false): TogglePlayIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            TogglePlayIntent: _GuardedAction<TogglePlayIntent>(_togglePlay),
          },
          child: Focus(focusNode: _node, autofocus: true, child: widget.child),
        ),
      ),
    );
  }
}

/// Acción que se desactiva (y deja pasar la tecla) mientras se escribe en un campo de texto.
class _GuardedAction<T extends Intent> extends Action<T> {
  _GuardedAction(this._run);

  final VoidCallback _run;

  @override
  bool isEnabled(T intent) => !primaryFocusIsTextInput();

  @override
  Object? invoke(T intent) {
    _run();
    return null;
  }
}
