import 'package:flutter/widgets.dart';
import 'package:toneforge/contract/library_detail.dart';
import 'package:toneforge/features/library/library_format.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_card.dart';

/// Tarjeta «Stems» (LV:327-344).
class StemsCard extends StatelessWidget {
  const StemsCard({super.key, required this.stems});

  final List<StemInfo> stems;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    TextStyle body(Color c) => TfText.body().copyWith(color: c, decoration: TextDecoration.none);
    return TfCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TfSpace.s20, vertical: TfSpace.s18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: TfSpace.s10,
          children: [
            SizedBox(
              width: double.infinity,
              child: Text(
                l.library_stemsTitle,
                style: TfText.display(18).copyWith(color: TfColors.text, decoration: TextDecoration.none),
              ),
            ),
            if (stems.isEmpty) Text(l.library_stemsNone, style: body(TfColors.muted)),
            for (final s in stems)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: TfSpace.s12, vertical: TfSpace.s10),
                decoration: BoxDecoration(
                  color: TfColors.field,
                  borderRadius: BorderRadius.circular(TfRadius.control),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(s.kind.raw, style: body(TfColors.text)),
                    Text(
                      s.isEmpty ? l.library_stemEmpty : formatBytes(s.bytes, locale),
                      style: body(TfColors.muted),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
