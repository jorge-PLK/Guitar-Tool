import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../contract/audio_calibration.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/tokens.dart';
import '../../../theme/typography.dart';
import '../../../widgets/tf_accent_bar.dart';
import '../../../widgets/tf_buttons.dart';
import '../../../widgets/tf_chip.dart';
import '../../../widgets/tf_sheet.dart';
import '../audio_store.dart';
import '../widgets/audio_texts.dart';

/// Abre la hoja «Calibrar latencia» (Ajustes · Audio). Lee y actúa solo por [audioStoreProvider].
Future<void> showCalibrationSheet(BuildContext context) =>
    showTfSheet<void>(
      context: context,
      // La ruta modal queda fuera de cualquier Material: sin esto el título hereda el subrayado de error.
      builder: (_) => DefaultTextStyle(
        style: TfText.body().copyWith(color: TfColors.text, decoration: TextDecoration.none),
        child: const CalibrationSheet(),
      ),
    );

/// Hoja «Calibrar latencia» (CalibrationSheet.swift:19-134): pasos, midiendo, resultado, fallo y error.
/// No se puede cerrar midiendo; al destruirse envía `closeCalibration` (cancela si mide, si no descarta).
class CalibrationSheet extends ConsumerStatefulWidget {
  const CalibrationSheet({super.key});

  @override
  ConsumerState<CalibrationSheet> createState() => _CalibrationSheetState();
}

class _CalibrationSheetState extends ConsumerState<CalibrationSheet> {
  late final AudioStore _store;

  @override
  void initState() {
    super.initState();
    _store = ref.read(audioStoreProvider.notifier);
  }

  @override
  void dispose() {
    final AudioStore s = _store;
    // Fuera del desmontaje: el store notifica a los widgets.
    Future<void>.microtask(() {
      if (s.ref.mounted) unawaited(s.closeCalibration());
    });
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AudioStoreState s = ref.watch(audioStoreProvider);
    final AudioCalibrationState? c = s.calibration;
    final bool running = s.calibrationRunning || s.calibrating || c?.phase == CalibrationPhase.running;
    final bool success = !running && c?.outcome == CalibrationOutcome.success && c?.success != null;
    final bool failure = !running && c?.outcome == CalibrationOutcome.failure && c?.failure != null;
    final bool error = !running && c?.outcome == CalibrationOutcome.error;

    final Widget body;
    final List<Widget> actions;
    if (running) {
      body = _Running(progress: c?.progress, text: l.settings_cal_running);
      actions = const <Widget>[];
    } else if (success) {
      body = _Success(l, c!.success!);
      actions = <Widget>[TfPrimaryButton(label: l.settings_cal_close, onPressed: _close)];
    } else if (failure || error) {
      body = failure ? _Failure(l, c!.failure!) : _ErrorBody(l, c?.error);
      actions = <Widget>[
        TfSecondaryButton(
          label: l.settings_cal_retry,
          onPressed: () => unawaited(_store.dismissCalibration()),
        ),
        TfPrimaryButton(label: l.settings_cal_close, onPressed: _close),
      ];
    } else {
      final String? block = calibrateBlockText(l, s.calibrateBlockMessage, fallback: s.calibrateBlock);
      body = _Steps(l, block);
      actions = <Widget>[
        TfSecondaryButton(label: l.settings_cal_cancel, onPressed: _close),
        TfPrimaryButton(
          label: l.settings_cal_start,
          onPressed: block == null ? () => unawaited(_store.calibrate()) : null,
        ),
      ];
    }

    return PopScope(
      canPop: !running,
      child: TfSheetScaffold(
        width: 540,
        padding: TfSpace.s28,
        spacing: TfSpace.s18,
        background: TfColors.bg,
        title: l.settings_cal_title,
        body: body,
        actions: actions,
      ),
    );
  }
}

TextStyle _body(double size, Color color, [TfWeight w = TfWeight.regular]) =>
    TfText.body(size, w).copyWith(color: color, decoration: TextDecoration.none);

class _Steps extends StatelessWidget {
  const _Steps(this.l, this.block);

  final AppLocalizations l;
  final String? block;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s18,
      children: <Widget>[
        Text(l.settings_cal_step1, style: _body(TfSize.font14, TfColors.text2)),
        Text(l.settings_cal_step2, style: _body(TfSize.font14, TfColors.text2)),
        Text(l.settings_cal_step3, style: _body(TfSize.font14, TfColors.muted)),
        if (block != null) Text(block!, style: _body(TfSize.font13, TfColors.accent)),
      ],
    );
  }
}

class _Running extends StatelessWidget {
  const _Running({required this.progress, required this.text});

  final double? progress;
  final String text;

  @override
  Widget build(BuildContext context) {
    final double? p = progress;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s18,
      children: <Widget>[
        Text(text, style: _body(TfSize.font14, TfColors.text2)),
        TfAccentBar(value: p, height: TfSpace.s8),
        if (p != null) Text('${(p.clamp(0.0, 1.0) * 100).round()} %',
            style: TfText.body(TfSize.font13, TfWeight.regular, true)
                .copyWith(color: TfColors.muted, decoration: TextDecoration.none)),
      ],
    );
  }
}

class _Success extends StatelessWidget {
  const _Success(this.l, this.success);

  final AppLocalizations l;
  final AudioCalibrationSuccess success;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s12,
      children: <Widget>[
        TfChip(l.settings_cal_done, kind: TfChipKind.ok),
        // Filas hechas por el núcleo (en español): no hay claves ARB para «muestras».
        DecoratedBox(
          decoration: BoxDecoration(
            color: TfColors.field,
            borderRadius: BorderRadius.circular(TfRadius.control),
          ),
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.all(TfSpace.s14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: TfSpace.s8,
                children: <Widget>[
                  for (final AudioCalibrationRow r in success.rows)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: TfSpace.s12,
                      children: <Widget>[
                        SizedBox(
                          width: 120,
                          child: Text(r.label, style: _body(TfSize.font13, TfColors.muted)),
                        ),
                        Expanded(
                          child: Text(r.value,
                              style: _body(TfSize.font14, TfColors.text, TfWeight.semibold)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure(this.l, this.f);

  final AppLocalizations l;
  final AudioCalibrationFailure f;

  @override
  Widget build(BuildContext context) {
    final (String title, String hint) = switch (f.reason) {
      CalibrationFailureReason.noSignal => (l.settings_cal_noSignalTitle, l.settings_cal_noSignalHint),
      CalibrationFailureReason.saturated => (l.settings_cal_saturatedTitle, l.settings_cal_saturatedHint),
      CalibrationFailureReason.unstable => (l.settings_cal_unstableTitle(f.spreadMS), l.settings_cal_unstableHint),
      CalibrationFailureReason.unknown => (f.title, f.hint),
    };
    return _Problem(title: title, hint: hint);
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody(this.l, this.message);

  final AppLocalizations l;
  final String? message;

  @override
  Widget build(BuildContext context) => _Problem(title: l.settings_cal_errorTitle, hint: message);
}

class _Problem extends StatelessWidget {
  const _Problem({required this.title, this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s8,
      children: <Widget>[
        Text(title, style: TfText.display(TfSize.font16).copyWith(color: TfColors.danger, decoration: TextDecoration.none)),
        if (hint != null) Text(hint!, style: _body(TfSize.font14, TfColors.text2)),
      ],
    );
  }
}
