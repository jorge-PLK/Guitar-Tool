import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_progress.dart';

/// `bannerBox` (BackingView.swift:191-196): body 13, padding 16x12, fondo `field`, radio 10, borde `fieldLine`.
class BannerBox extends StatelessWidget {
  const BannerBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TfColors.field,
        borderRadius: BorderRadius.circular(TfRadius.control),
        border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TfSpace.s16, vertical: TfSpace.s12),
        child: DefaultTextStyle(
          style: TfText.body(TfSize.font13).copyWith(color: TfColors.text),
          child: child,
        ),
      ),
    );
  }
}

/// Caja de error de carga (`loadError`); sin error no ocupa nada.
class LoadErrorBanner extends ConsumerWidget {
  const LoadErrorBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = ref.watch(studyStoreProvider.select((s) => s.study?.loadError));
    if (error == null) return const SizedBox.shrink();
    return BannerBox(
      child: Text(error, style: TfText.body(TfSize.font13).copyWith(color: TfColors.danger)),
    );
  }
}

/// Caja de estado del análisis: analizando, sin análisis («Analizar») o fallido («Reintentar»); `ready` no pinta nada.
class AnalysisBanner extends ConsumerWidget {
  const AnalysisBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final analysis = ref.watch(studyStoreProvider.select((s) => s.study?.analysis));
    final text = TfText.body(TfSize.font13);
    void analyze() => ref.read(studyStoreProvider.notifier).analyze();
    switch (analysis?.state) {
      case StudyAnalysisState.analyzing:
        return BannerBox(
          child: Row(
            spacing: TfSpace.s12,
            children: [
              const TfSpinner.small(),
              Flexible(child: Text(l.backing_analyzing, style: text.copyWith(color: TfColors.text2))),
            ],
          ),
        );
      case StudyAnalysisState.missing:
        return BannerBox(
          child: _WithAction(
            text: Text(l.backing_analysisMissing, style: text.copyWith(color: TfColors.text2)),
            label: l.backing_analyze,
            onPressed: analyze,
          ),
        );
      case StudyAnalysisState.failed:
        return BannerBox(
          child: _WithAction(
            text: Text(
              l.backing_analysisFailed(analysis?.error ?? ''),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.copyWith(color: TfColors.danger),
            ),
            label: l.backing_retry,
            onPressed: analyze,
          ),
        );
      case StudyAnalysisState.ready || StudyAnalysisState.unknown || null:
        return const SizedBox.shrink();
    }
  }
}

class _WithAction extends StatelessWidget {
  const _WithAction({required this.text, required this.label, required this.onPressed});

  final Widget text;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: TfSpace.s12,
      children: [
        Expanded(child: text),
        TfSecondaryButton(label: label, height: TfSize.pillHeight, onPressed: onPressed),
      ],
    );
  }
}
