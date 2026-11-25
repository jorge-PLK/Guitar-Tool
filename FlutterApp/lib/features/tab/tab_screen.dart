import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/tab/songsterr_sheet.dart';
import 'package:toneforge/features/tab/tab_canvas.dart';
import 'package:toneforge/features/tab/tab_canvas_controller.dart';
import 'package:toneforge/features/tab/tab_card.dart';
import 'package:toneforge/features/tab/tab_edit_bar.dart';
import 'package:toneforge/features/tab/tab_header.dart';
import 'package:toneforge/features/tab/tab_notice.dart';
import 'package:toneforge/features/tab/tab_stage.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/features/tab/tab_theme_chooser.dart';
import 'package:toneforge/features/tab/tab_transport.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/shell/shell_route.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_progress.dart';
import 'package:toneforge/widgets/tf_state_message.dart';

/// Pantalla de Tablatura: selector de tema, cargando o contenido (TabScreen.swift:13-19, 59-72).
class TabScreen extends ConsumerWidget {
  const TabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedProjectProvider);
    if (selected == null) return const TabThemeChooser();
    final tab = ref.watch(tabStoreProvider.select((s) => s.tab));
    if (tab == null) {
      final error = ref.watch(tabStoreProvider.select((s) => s.error));
      if (error != null) {
        return Center(child: TfStateMessage(icon: ShellRoute.tab.icon, text: error.message));
      }
      return const Center(child: TfSpinner.small());
    }
    final editing = tab.editMode && tab.phase == TabPhase.ready;
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s36, vertical: TfSpace.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TfSpace.s14,
        children: [
          const TabHeader(),
          const TabNotice(),
          const Expanded(child: TabCard(stage: _Stage())),
          if (editing) const TabEditBar(),
          const TabTransport(),
        ],
      ),
    );
    // La hoja de Songsterr se abre y cierra sola según `songsterrStoreProvider` (TabScreen.swift:99-102).
    return Stack(children: [body, const SongsterrSheetHost()]);
  }
}

/// Lienzo alphaTab con el overlay de fases encima (TabScreen.swift:191-198).
class _Stage extends ConsumerWidget {
  const _Stage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final webError = ref.watch(tabCanvasProvider.select((s) => s.webError));
    return TabStage(canvas: const TabCanvas(), webError: webError);
  }
}
