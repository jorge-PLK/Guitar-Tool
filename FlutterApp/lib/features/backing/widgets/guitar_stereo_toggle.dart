import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_progress.dart';
import 'package:toneforge/widgets/tf_switch.dart';
import 'package:toneforge/widgets/tf_tooltip.dart';

/// Interruptor «Guitarras en L y R» con el estado del paso de guitarras (GuitarOptionsViews.swift:9-26, 54-77).
class GuitarStereoToggle extends ConsumerWidget {
  const GuitarStereoToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final StudyGuitarsInfo? g = ref.watch(studyStoreProvider.select((s) => s.study?.guitars));
    if (g == null) return const SizedBox.shrink();
    final AppLocalizations l = AppLocalizations.of(context);
    final TextStyle body = TfText.body(TfSize.font13, TfWeight.medium).copyWith(color: TfColors.text);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: TfSpace.s12,
      children: <Widget>[
        _Status(info: g),
        TfTooltip(
          message: l.backing_stereoSplitTooltip,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: TfSpace.s8,
            children: <Widget>[
              Text(l.backing_stereoSplit, style: body),
              TfSwitch(
                small: true,
                value: g.stereoSplit,
                semanticLabel: l.backing_stereoSplit,
                onChanged: (bool on) => ref.read(studyStoreProvider.notifier).setGuitarStereo(on),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.info});
  final StudyGuitarsInfo info;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = TfText.body(TfSize.font13);
    if (info.process == StudyGuitarProcess.processing) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: TfSpace.s8,
        children: <Widget>[
          const TfSpinner.mini(),
          Text(AppLocalizations.of(context).backing_guitarsProcessing,
              style: style.copyWith(color: TfColors.text2)),
        ],
      );
    }
    final String? msg = info.process == StudyGuitarProcess.failed ? info.error : info.saveError;
    if (msg == null || msg.isEmpty) return const SizedBox.shrink();
    final TextStyle danger = style.copyWith(color: TfColors.danger);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: TfSpace.s6,
      children: <Widget>[
        if (info.process == StudyGuitarProcess.failed)
          const TfIconView(TfIcon.exclamationmarkTriangleFill, size: TfSize.font13, color: TfColors.danger),
        Flexible(child: Text(msg, maxLines: 1, overflow: TextOverflow.ellipsis, style: danger)),
      ],
    );
  }
}
