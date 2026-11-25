import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/tab/songsterr_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_accent_bar.dart';
import 'package:toneforge/widgets/tf_buttons.dart';

/// Paso `.working(text)` de la hoja de Songsterr (TSS:179-189): texto, barra de acento
/// indeterminada, `Spacer` y «Cancelar» (vuelve a resultados con `back`).
class SongsterrWorking extends ConsumerWidget {
  const SongsterrWorking({super.key, required this.text});

  final String? text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s12,
      children: <Widget>[
        if (text != null) Text(text!),
        const SizedBox(width: TfSize.songsterrWorkingBarWidth, child: TfAccentBar()),
        const Spacer(),
        TfSecondaryButton(
          label: l.tab_sheetCancel,
          height: TfSpace.s36,
          onPressed: ref.read(songsterrStoreProvider.notifier).back,
        ),
      ],
    );
  }
}
