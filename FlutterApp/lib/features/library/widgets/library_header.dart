import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/library/library_logic.dart';
import 'package:toneforge/features/library/library_store.dart';
import 'package:toneforge/features/library/sheets/import_sheet.dart';
import 'package:toneforge/features/library/widgets/playlist_indicator.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_segmented.dart';
import 'package:toneforge/widgets/tf_text_field.dart';

/// Cabecera de la Biblioteca (LV:107-136): título, indicador de lista, buscador, vista e importar.
class LibraryHeader extends ConsumerWidget {
  const LibraryHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final grouping = ref.watch(libraryStoreProvider.select((s) => s.grouping));
    final store = ref.read(libraryStoreProvider.notifier);
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.library_title, style: TfText.display(TfSize.font32).copyWith(color: TfColors.text)),
            const SizedBox(height: TfSpace.s6),
            Text(l.library_subtitle, style: TfText.body().copyWith(color: TfColors.muted)),
          ],
        ),
        const Spacer(),
        const PlaylistIndicator(),
        const SizedBox(width: TfSpace.s8),
        TfTextField(
          search: true,
          width: TfSize.searchFieldWidth,
          hint: l.library_searchHint,
          clearSemanticLabel: l.library_searchClear,
          onChanged: store.setQuery,
        ),
        const SizedBox(width: TfSpace.s8),
        Semantics(
          label: l.library_viewLabel,
          child: TfSegmented<LibraryGrouping>(
            segments: [
              TfSegment(value: LibraryGrouping.songs, label: l.library_viewSongs),
              TfSegment(value: LibraryGrouping.artists, label: l.library_viewArtists),
            ],
            value: grouping,
            onChanged: store.setGrouping,
          ),
        ),
        const SizedBox(width: TfSpace.s8),
        TfPrimaryButton(label: l.library_importButton, onPressed: () => showImportSheet(context)),
      ],
    );
  }
}
