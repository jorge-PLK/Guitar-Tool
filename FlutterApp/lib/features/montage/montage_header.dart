import 'package:flutter/widgets.dart';
import 'package:toneforge/contract/montage.dart';
import 'package:toneforge/features/montage/montage_models.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_notice.dart';

/// Cabecera de Montaje (MV:130-160) y líneas de aviso bajo ella (MV:151-165).
class MontageHeader extends StatelessWidget {
  const MontageHeader({
    super.key,
    required this.state,
    required this.onExport,
    required this.onCancelExport,
  });

  final MontageState state;
  final VoidCallback onExport;
  final VoidCallback onCancelExport;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MontageSnapshot s = state.snapshot!;
    final String sub = <String>[
      if (s.artist != null) s.artist!,
      s.title,
      l.montageTakesCount(s.lanes.length),
    ].join(' · ');
    final String help = state.isAnalyzing ? l.montageExportWait : '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TfSpace.s2,
            children: <Widget>[
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TfText.body(TfSize.font13).copyWith(color: TfColors.muted)),
              Text(l.montageTitle, style: TfText.display(TfSize.font26).copyWith(color: TfColors.text)),
            ],
          ),
        ),
        if (state.exportRunning)
          TfSecondaryButton(label: l.montageExportCancel, onPressed: onCancelExport)
        else
          Semantics(
            tooltip: help,
            child: TfPrimaryButton(label: l.montageExport, onPressed: state.exportEnabled ? onExport : null),
          ),
      ],
    );
  }
}

/// Líneas bajo la cabecera: solo audio, error de vista previa, aviso de audio y error de acción (descartable).
class MontageNotices extends StatelessWidget {
  const MontageNotices({super.key, required this.state, required this.onDismissAction});

  final MontageState state;
  final VoidCallback onDismissAction;

  Widget _line(String text, Color color) =>
      Text(text, style: TfText.body(TfSize.font12).copyWith(color: color));

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MontageSnapshot s = state.snapshot!;
    final String? previewError = s.preview.phase == MontagePreviewPhase.error ? s.preview.error : null;
    final String? audioError = s.transport.audioError;
    // Errores del núcleo: sin claves por `code` en el ARB, cae a `message`.
    final String? action = state.actionError?.message;
    final List<Widget> lines = <Widget>[
      if (s.audioOnlyParts.isNotEmpty)
        _line(l.montageAudioOnlyParts(s.audioOnlyParts.join(', ')), TfColors.accent),
      if (previewError != null) _line(previewError, TfColors.danger),
      if (audioError != null) _line(audioError, TfColors.accent),
      if (action != null)
        TfNotice(
          messages: <String>[action],
          tone: TfNoticeTone.danger,
          onDismiss: onDismissAction,
          dismissLabel: l.montageClose,
        ),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: TfSpace.s6, children: lines);
  }
}
