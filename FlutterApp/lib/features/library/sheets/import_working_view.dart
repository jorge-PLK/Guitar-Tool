import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/library/link_import_store.dart';
import 'package:toneforge/features/library/sheets/import_banner.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/fmt.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_accent_bar.dart';
import 'package:toneforge/widgets/tf_buttons.dart';

/// Pantalla «trabajando» de la hoja de importación (LS:738-757): título/artista, fase + porcentaje,
/// barra de acento (indeterminada sin valor), avisos y «Cancelar» (deshabilitado si `!canCancel`).
class ImportWorkingView extends ConsumerWidget {
  const ImportWorkingView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(linkImportStoreProvider);
    final label = switch (s.workPhase) {
      LinkWorkPhase.updating => l.library_importUpdating,
      LinkWorkPhase.importing => l.library_importImporting,
      LinkWorkPhase.downloading => l.library_importDownloading,
      LinkWorkPhase.converting => l.library_importConverting,
    };
    final p = s.progress;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s14,
      children: [
        if (s.title.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TfSpace.s2,
            children: [
              Text(
                s.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TfText.body(15, TfWeight.semibold).copyWith(color: TfColors.text),
              ),
              if (s.artist.isNotEmpty) Text(s.artist, style: TfText.body(13).copyWith(color: TfColors.muted)),
            ],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TfText.body().copyWith(color: TfColors.text)),
            if (p != null) Text(TfFmt.percent(p), style: TfText.body().copyWith(color: TfColors.muted)),
          ],
        ),
        TfAccentBar(value: p),
        for (final n in s.notices) ImportBanner(text: n, tone: ImportBannerTone.warning),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TfSecondaryButton(
              label: l.library_importCancel,
              onPressed: s.canCancel ? () => ref.read(linkImportStoreProvider.notifier).cancel() : null,
            ),
          ],
        ),
      ],
    );
  }
}
