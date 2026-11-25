import 'package:flutter/widgets.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

/// «Todavía no hay temas» (LV:99-105), sin marco: la tabla lo pone tras un divisor y la cuadrícula
/// de artistas dentro de una tarjeta.
class LibraryEmpty extends StatelessWidget {
  const LibraryEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TfSpace.s48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l.library_emptyTitle,
              textAlign: TextAlign.center,
              style: TfText.body(15, TfWeight.semibold).copyWith(color: TfColors.text),
            ),
            const SizedBox(height: TfSpace.s6),
            Text(
              l.library_emptyBody,
              textAlign: TextAlign.center,
              style: TfText.body().copyWith(color: TfColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
