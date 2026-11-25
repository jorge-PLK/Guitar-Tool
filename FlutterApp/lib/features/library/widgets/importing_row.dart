import 'package:flutter/widgets.dart';
import 'package:toneforge/contract/jobs.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/fmt.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_chip.dart';
import 'package:toneforge/widgets/tf_divider.dart';
import 'package:toneforge/widgets/tf_progress.dart';

/// Ancho de la barra de progreso de una importación en curso (LV:177).
const double importingBarWidth = 160;

/// Fila de importación en curso (LV:172-181), delante de las filas de temas.
class ImportingRow extends StatelessWidget {
  const ImportingRow({super.key, required this.job});

  final JobInfo job;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final fraction = (job.fraction ?? 0).clamp(0.0, 1.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const TfDivider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: TfSpace.s20, vertical: TfSpace.s16),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  job.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TfText.body(TfSize.font14, TfWeight.semibold).copyWith(color: TfColors.text),
                ),
              ),
              const Spacer(),
              SizedBox(width: importingBarWidth, child: TfProgress(value: fraction)),
              const SizedBox(width: TfSpace.s12),
              TfChip(l.library_importing(TfFmt.percent(fraction)), kind: TfChipKind.working),
            ],
          ),
        ),
      ],
    );
  }
}
