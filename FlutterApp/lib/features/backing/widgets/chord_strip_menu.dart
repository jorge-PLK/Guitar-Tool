import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/section_menu.dart';
import 'package:toneforge/features/backing/widgets/section_popover_state.dart';
import 'package:toneforge/features/backing/widgets/section_selection.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/widgets/tf_menu.dart';

/// Entradas del menú contextual de un acorde de la tira, fuera del modo edición (BT:198,233-244).
/// Con bucle activo: «Marcar sección» y «Marcar como solo». Si el punto medio del acorde cae en una
/// sección: divisor (solo si hubo las anteriores) + el menú de esa sección. Vacío = sin menú.
List<TfMenuEntry> chordStripMenuEntries(
  WidgetRef ref,
  StudyChord chord,
  StudyLoop? loop,
  List<StudySectionInfo> sections,
  AppLocalizations l,
) {
  final List<TfMenuEntry> out = <TfMenuEntry>[];
  if (loop != null) {
    final StudyStore store = ref.read(studyStoreProvider.notifier);
    TfMenuItem mark(String label, bool solo) => TfMenuItem(
          label: label,
          onSelected: () async {
            final String? id = await store.markSection(loop.start, loop.end, solo: solo);
            if (id == null) return;
            ref.read(sectionSelectionProvider.notifier).select(id);
            ref.read(sectionPopoverProvider.notifier).open(id);
          },
        );
    out
      ..add(mark(l.backing_markSection, false))
      ..add(mark(l.backing_markSolo, true));
  }
  final double mid = (chord.start + chord.end) / 2;
  for (final StudySectionInfo s in sections) {
    if (mid >= s.start && mid < s.end) {
      if (out.isNotEmpty) out.add(const TfMenuDivider());
      out.addAll(sectionMenuEntries(ref, s, l));
      break;
    }
  }
  return out;
}
