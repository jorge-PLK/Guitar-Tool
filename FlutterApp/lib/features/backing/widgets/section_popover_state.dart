import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/shell/selected_project.dart';

/// Id de la sección cuya hoja «Sección / Solo» está abierta (`selection.popover`, SectionBoxes.swift).
///
/// Una a la vez. Se limpia al cambiar de tema, al activar o salir de «Editar acordes» y cuando la sección
/// deja de existir (mismas reglas que [sectionSelectionProvider]).
final sectionPopoverProvider =
    NotifierProvider<SectionPopoverNotifier, String?>(SectionPopoverNotifier.new);

class SectionPopoverNotifier extends Notifier<String?> {
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

  void open(String id) => state = id;

  void close() => state = null;
}
