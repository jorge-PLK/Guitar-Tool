import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../contract/record.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/tokens.dart';
import '../../../theme/typography.dart';
import '../../../widgets/tf_card.dart';
import '../../../widgets/tf_checkbox.dart';
import '../../../widgets/tf_dropdown.dart';
import '../record_store.dart';
import '../record_texts.dart';
import 'time_readout.dart';

/// Valor de «Empezar en» para «Principio» (sin sección).
const String _beginning = '';

/// Tarjeta de transporte de Grabar (RecordView.swift:462-538).
class RecordBar extends ConsumerWidget {
  const RecordBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final RecordState s = ref.watch(recordStoreProvider);
    final RecordStore store = ref.read(recordStoreProvider.notifier);
    final RecordSnapshot? snap = s.snapshot;
    final bool busy = s.isBusy;
    final bool hasCamera = snap != null && (snap.camera.state == CameraState.live || snap.camera.state == CameraState.simulated);
    final bool timing = s.phase == RecordPhase.recording || s.phase == RecordPhase.finishing;
    final double total = (snap?.plannedStop ?? snap?.duration ?? 0).toDouble();
    final bool punchOn = snap?.punch.enabled ?? false;
    return TfCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TfSpace.s16, vertical: TfSpace.s14),
        child: DefaultTextStyle.merge(
          style: TfText.body().copyWith(color: TfColors.text2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TfSpace.s12,
            children: <Widget>[
              Row(
                spacing: TfSpace.s14,
                children: <Widget>[
                  RecordButton(
                    stop: s.canStopTake || (busy && s.phase == RecordPhase.finishing && snap?.audio.recording == true),
                    dimmed: !s.canPressRecord,
                    onPressed: s.canPressRecord ? store.toggleTake : null,
                  ),
                  TimeReadout(
                    position: timing ? s.position.toDouble() : 0,
                    total: total,
                    autoStop: snap?.plannedStop != null,
                  ),
                  const Spacer(),
                  if (hasCamera) Flexible(child: OffsetLabel(ms: snap.camera.defaultOffsetMs)),
                ],
              ),
              Wrap(
                spacing: TfSpace.s18,
                runSpacing: TfSpace.s18,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  _Labeled(
                    label: l.record_startAt,
                    child: TfDropdown<String>(
                      value: snap?.startSectionId ?? _beginning,
                      items: <TfDropdownItem<String>>[
                        TfDropdownItem<String>(value: _beginning, label: l.record_startBeginning),
                        for (final RecordSection sec in snap?.sections ?? const <RecordSection>[])
                          TfDropdownItem<String>(value: sec.id, label: sec.name),
                      ],
                      onChanged: busy || punchOn
                          ? null
                          : (String v) => store.setStartSection(v == _beginning ? null : v),
                    ),
                  ),
                  TfCheckbox(
                    value: snap?.countIn ?? false,
                    label: l.record_countIn,
                    onChanged: busy ? null : (bool v) => store.setCountIn(v),
                  ),
                  _Labeled(
                    label: l.record_preRoll,
                    child: TfDropdown<int>(
                      value: snap?.preRollBars ?? 0,
                      items: <TfDropdownItem<int>>[
                        TfDropdownItem<int>(value: 2, label: l.record_preRoll2),
                        TfDropdownItem<int>(value: 1, label: l.record_preRoll1),
                        TfDropdownItem<int>(value: 0, label: l.record_preRoll0),
                      ],
                      onChanged: busy ? null : (int v) => store.setPreRoll(v),
                    ),
                  ),
                  Semantics(
                    tooltip: l.record_punchToggleHelp,
                    child: TfCheckbox(
                      value: punchOn,
                      label: l.record_punchToggle,
                      onChanged: s.canArmPunch ? (bool v) => store.setPunchEnabled(v) : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        spacing: TfSpace.s8,
        children: <Widget>[Text(label), child],
      );
}

/// Cápsula roja de 48 de alto: «Grabar» (círculo) o «Parar» (cuadrado). RV:474-489.
class RecordButton extends StatelessWidget {
  const RecordButton({super.key, required this.stop, required this.dimmed, required this.onPressed});

  final bool stop;
  final bool dimmed;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final Widget capsule = Container(
      height: TfSpace.s48,
      // TODO(ola3): falta token del padding horizontal 22 del botón de grabar (RV:482).
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s20 + TfSpace.s2),
      decoration: const BoxDecoration(
        color: TfColors.recordButton,
        borderRadius: BorderRadius.all(Radius.circular(TfRadius.pill)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: TfSpace.s8,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              color: TfColors.white,
              shape: stop ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: stop ? const BorderRadius.all(Radius.circular(TfRadius.r2)) : null,
            ),
            child: const SizedBox.square(dimension: TfSpace.s10),
          ),
          Text(
            stop ? l.record_stop : l.record_start,
            style: TfText.body(15, TfWeight.semibold).copyWith(color: TfColors.white),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: stop ? l.record_stopA11y : l.record_start,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Opacity(opacity: dimmed ? TfOpacity.dim : 1, child: capsule),
      ),
    );
  }
}

/// «Desfase de la cámara: …» (RV:530-537); solo con cámara.
class OffsetLabel extends StatelessWidget {
  const OffsetLabel({super.key, required this.ms});

  final int ms;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          recordOffsetText(l, ms),
          maxLines: 1,
          style: TfText.body(TfSize.font13, TfWeight.semibold).copyWith(color: ms == 0 ? TfColors.muted : TfColors.ok),
        ),
      ),
    );
  }
}
