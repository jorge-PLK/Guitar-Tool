import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/backing/analysis_banner.dart';
import 'package:toneforge/features/backing/backing_chooser.dart';
import 'package:toneforge/features/backing/backing_header.dart';
import 'package:toneforge/features/backing/backing_layout.dart';
import 'package:toneforge/features/backing/not_separated_card.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_card.dart';
import 'package:toneforge/widgets/tf_progress.dart';

/// Por debajo de este alto de pantalla el mezclador usa su mínimo bajo (BackingView.swift:78).
const double _lowHeight = 780;
const double _verticalPadding = TfSpace.s20;
const double _mixerMin = 270;
const double _mixerMinLow = 236;
const double _mixerIdeal = 346;

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
                  lastMinHeight: low ? _mixerMinLow : _mixerMin,
                  lastIdealHeight: _mixerIdeal,
                  children: const [
                    BackingHeader(),
                    LoadErrorBanner(),
                    AnalysisBanner(),
                    _TimelineCardSlot(),
                    _MixerCardSlot(),
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

// SLOT: TimelineCard. Sustituir por la tarjeta «Línea de tiempo» (alto natural; recibe el store por Riverpod).
class _TimelineCardSlot extends StatelessWidget {
  const _TimelineCardSlot();

  @override
  Widget build(BuildContext context) => const TfCard(child: SizedBox(height: 200));
}

// SLOT: MixerCard. Sustituir por el mezclador; último hijo: recibe alto fijo entre 270 (236 si < 780) y 346.
class _MixerCardSlot extends StatelessWidget {
  const _MixerCardSlot();

  @override
  Widget build(BuildContext context) => const TfCard(child: SizedBox.expand());
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
