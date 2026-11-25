import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/backing/analysis_banner.dart';
import 'package:toneforge/features/backing/backing_chooser.dart';
import 'package:toneforge/features/backing/backing_header.dart';
import 'package:toneforge/features/backing/backing_layout.dart';
import 'package:toneforge/features/backing/not_separated_card.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/chords_expanded.dart';
import 'package:toneforge/features/backing/widgets/mixer_card.dart';
import 'package:toneforge/features/backing/widgets/timeline_card.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_progress.dart';

/// Por debajo de este alto de pantalla el mezclador usa su mínimo bajo (BackingView.swift:78).
const double _lowHeight = 780;
const double _verticalPadding = TfSpace.s20;

/// Backing track: elige entre selector de tema, spinner, error de apertura, «sin separar» y contenido.
class BackingScreen extends ConsumerWidget {
  const BackingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasProject = ref.watch(selectedProjectProvider) != null;
    if (!hasProject) return const BackingChooser();
    final status = ref.watch(studyStoreProvider.select((s) => s.status));
    return switch (status) {
      StudyLoadStatus.open => const _BackingContent(),
      StudyLoadStatus.error => const _OpenError(),
      StudyLoadStatus.idle || StudyLoadStatus.opening => const Center(child: TfSpinner.small()),
    };
  }
}

class _BackingContent extends ConsumerWidget {
  const _BackingContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final separated = ref.watch(studyStoreProvider.select((s) {
      final st = s.study;
      return st == null || st.transport.channels.isNotEmpty || st.emptyStems.isNotEmpty;
    }));
    return LayoutBuilder(
      builder: (context, box) {
        final low = box.maxHeight < _lowHeight;
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: TfSpace.s36, vertical: _verticalPadding),
          child: separated
              ? FillLastLayout(
                  available: box.maxHeight - 2 * _verticalPadding,
                  spacing: TfSpace.s14,
                  lastMinHeight: low ? MixerCard.minHeightLow : MixerCard.minHeight,
                  lastIdealHeight: MixerCard.idealHeight,
                  children: [
                    const BackingHeader(),
                    const LoadErrorBanner(),
                    const AnalysisBanner(),
                    const TimelineCard(),
                    _Mixer(low: low),
                  ],
                )
              : const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: TfSpace.s14,
                  children: [BackingHeader(), NotSeparatedCard()],
                ),
        );
      },
    );
  }
}

/// Mezclador: último hijo, recibe alto fijo entre su mínimo y su ideal; compacto con la rejilla expandida.
class _Mixer extends ConsumerWidget {
  const _Mixer({required this.low});

  final bool low;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expanded = ref.watch(chordsExpandedProvider);
    return MixerCard(compact: expanded, lowHeight: low);
  }
}

/// Fallo al abrir el estudio (`study.open`): mensaje del núcleo y «Reintentar».
class _OpenError extends ConsumerWidget {
  const _OpenError();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final error = ref.watch(studyStoreProvider.select((s) => s.error));
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s36, vertical: _verticalPadding),
      child: BannerBox(
        child: Row(
          spacing: TfSpace.s12,
          children: [
            Expanded(
              child: Text(
                l.backing_errorLoadStems(error?.message ?? ''),
                style: TfText.body(TfSize.font13).copyWith(color: TfColors.danger),
              ),
            ),
            TfSecondaryButton(
              label: l.backing_retry,
              height: TfSize.pillHeight,
              onPressed: () => ref.read(studyStoreProvider.notifier).retryOpen(),
            ),
          ],
        ),
      ),
    );
  }
}
