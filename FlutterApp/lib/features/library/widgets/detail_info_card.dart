import 'package:flutter/widgets.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/features/library/library_format.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_card.dart';

/// Tarjeta de datos (LV:319-326): Frecuencia, Duración, Estado.
class DetailInfoCard extends StatelessWidget {
  const DetailInfoCard({super.key, required this.summary});

  final ProjectSummary summary;

  String _state(AppLocalizations l) => switch (summary.separationState) {
    SeparationState.none || SeparationState.unknown => l.library_stateDetailImported,
    SeparationState.queued => l.library_stateDetailQueued,
    SeparationState.running => l.library_stateDetailRunning,
    SeparationState.done => l.library_stateDetailDone,
    SeparationState.failed => l.library_stateDetailFailed(
      summary.separationError ?? l.library_stateDetailFailedUnknown,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    return TfCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: TfSpace.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InfoRow(label: l.library_infoRate, value: formatRate(summary.sampleRate.toInt(), locale)),
            InfoRow(label: l.library_infoDuration, value: formatDuration(summary.duration, locale)),
            InfoRow(label: l.library_infoState, value: _state(l)),
          ],
        ),
      ),
    );
  }
}

/// Fila de datos del detalle (LV:382-385): sin fondo, `padding h20 v10`; distinta de `TfInfoRow`.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s20, vertical: TfSpace.s10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TfText.body().copyWith(color: TfColors.muted, decoration: TextDecoration.none)),
          const SizedBox(width: TfSpace.s12),
          Flexible(
            child: Text(
              value,
              style: TfText.body(TfSize.font14, TfWeight.semibold).copyWith(
                color: TfColors.text,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
