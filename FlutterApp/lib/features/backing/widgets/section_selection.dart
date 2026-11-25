import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/shell/selected_project.dart';

/// Id de la sección seleccionada en Backing (`selection.select(id)` / `clear()`, SB:96).
///
/// Se limpia al cambiar de tema, al activar o salir de «Editar acordes» (BT:41-42) y cuando la sección
/// seleccionada deja de existir (borrada o descartada).
final sectionSelectionProvider =
    NotifierProvider<SectionSelectionNotifier, String?>(SectionSelectionNotifier.new);

class SectionSelectionNotifier extends Notifier<String?> {
  @override
  String? build() {
    ref.listen<String?>(selectedProjectProvider, (_, _) => state = null);
    ref.listen<bool>(studyStoreProvider.select((s) => s.editMode), (_, _) => state = null);
    ref.listen<List<StudySectionInfo>?>(
      studyStoreProvider.select((s) => s.study?.sections),
      (_, List<StudySectionInfo>? sections) {
        final String? id = state;
        if (id == null) return;
        if (sections == null || !sections.any((StudySectionInfo s) => s.id == id)) state = null;
      },
    );
    return null;
  }

  void select(String id) => state = id;

  void clear() => state = null;
}
