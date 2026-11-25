import 'package:flutter/widgets.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

/// Tono de un aviso de la hoja de importación.
enum ImportBannerTone { error, warning }

/// Aviso en línea de la hoja de importación (`banner`, LinkImportSheet.swift:820-826): texto 13,
/// padding h12 v10, radio 8; error = danger sobre dangerBg, aviso = accent sobre accentBg. Sin icono ni cierre
/// (por eso no es `TfNotice`).
class ImportBanner extends StatelessWidget {
  const ImportBanner({super.key, required this.text, this.tone = ImportBannerTone.error});

  final String text;
  final ImportBannerTone tone;

  @override
  Widget build(BuildContext context) {
    final error = tone == ImportBannerTone.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s12, vertical: TfSpace.s10),
      decoration: BoxDecoration(
        color: error ? TfColors.dangerBg : TfColors.accentBg,
        borderRadius: BorderRadius.circular(TfRadius.field),
      ),
      child: Text(
        text,
        style: TfText.body(13).copyWith(color: error ? TfColors.danger : TfColors.accent),
      ),
    );
  }
}
