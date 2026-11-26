import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/tab/tab_phase_overlay.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/features/tab/tab_track_strip.dart';
import 'package:toneforge/theme/tokens.dart';

/// Zona del lienzo (`TabScreen.swift:191-198`): el lienzo alphaTab y, encima, el overlay de fase.
/// El fondo, el radio y el alto mínimo los pone `TabCard`.
class TabStage extends ConsumerWidget {
  const TabStage({super.key, required this.canvas, this.webError});

  final Widget canvas;
  final String? webError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TabState? tab = ref.watch(tabStoreProvider.select((s) => s.tab));
    final TabPhase? phase = tab?.phase;
    final bool visible =
        phase == TabPhase.ready || (phase == TabPhase.working && tabEntries(tab).isNotEmpty);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // Montado siempre: con opacidad 0 sigue vivo y cargado.
        IgnorePointer(
          ignoring: !visible,
          child: Opacity(key: const ValueKey<String>('stage-canvas-opacity'), opacity: visible ? 1 : 0, child: canvas),
        ),
        // El recorte de esquinas solo cubre el overlay; el lienzo nativo no puede ir bajo un recorte.
        ClipRRect(
          key: const ValueKey<String>('stage-overlay-clip'),
          borderRadius: BorderRadius.circular(TfRadius.control),
          child: TabPhaseOverlay(webError: webError),
        ),
      ],
    );
  }
}
