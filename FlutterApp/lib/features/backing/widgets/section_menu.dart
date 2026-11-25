import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/section_popover_state.dart';
import 'package:toneforge/features/backing/widgets/section_selection.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/widgets/tf_menu.dart';

/// Entradas del menú contextual de una sección (SectionBoxes.swift:268-279). Reutilizable
/// (cabecera de la caja y menú del acorde de la tira).
List<TfMenuEntry> sectionMenuEntries(WidgetRef ref, StudySectionInfo s, AppLocalizations l) {
  final StudyStore store = ref.read(studyStoreProvider.notifier);
  return <TfMenuEntry>[
    TfMenuItem(
      label: l.backing_menuRenameAdjust,
      onSelected: () {
        ref.read(sectionSelectionProvider.notifier).select(s.id);
        ref.read(sectionPopoverProvider.notifier).open(s.id);
      },
    ),
    TfMenuItem(
      label: s.solo ? l.backing_menuUnmarkSolo : l.backing_menuMarkSolo,
      onSelected: () => store.updateSection(StudyUpdateSectionParams(id: s.id, solo: !s.solo)),
    ),
    const TfMenuDivider(),
    TfMenuItem(
      label: l.backing_menuDeleteSection,
      destructive: true,
      onSelected: () {
        ref.read(sectionSelectionProvider.notifier).clear();
        store.deleteSection(s.id);
      },
    ),
  ];
}

/// Pulsación larga en la cabecera: alterna el bucle de la sección (SB:96-100).
void toggleSectionLoop(WidgetRef ref, StudySectionInfo s, {double sameTime = 0.01}) {
  final StudyStore store = ref.read(studyStoreProvider.notifier);
  final StudyLoop? loop = ref.read(studyStoreProvider).study?.transport.loop;
  if (loop != null && (loop.start - s.start).abs() < sameTime && (loop.end - s.end).abs() < sameTime) {
    store.clearLoop();
  } else {
    store.setLoop(s.start, s.end, name: s.name);
  }
}
