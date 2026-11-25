import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../contract/record_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/tokens.dart';
import '../../../theme/typography.dart';
import '../../../widgets/tf_buttons.dart';
import '../../../widgets/tf_checkbox.dart';
import '../../../widgets/tf_number_field.dart';
import '../../../widgets/tf_progress.dart';
import '../../../widgets/tf_sheet.dart';
import '../../../widgets/tf_video_surface.dart';
import '../record_offset_actions.dart';
import '../record_store.dart';
import '../take_viewer_store.dart';

/// «Ajustar desfase» (OS, 720). Abre el reproductor de la hoja (`takeview.openOffset`); al cerrar,
/// `takeview.close` y después `record.finishOffset` (en NTFS no se borra una toma abierta). Esc no cierra.
Future<void> showOffsetSheet(BuildContext context) async {
  final ProviderContainer c = ProviderScope.containerOf(context);
  final TakeViewerStore viewer = c.read(takeViewerStoreProvider.notifier);
  final RecordStore record = c.read(recordStoreProvider.notifier);
  unawaited(viewer.openOffset());
  final ({bool save, bool makeDefault})? r = await showTfSheet<({bool save, bool makeDefault})>(
    context: context,
    onCancel: () {},
    builder: (BuildContext ctx) => const OffsetSheet(),
  );
  await viewer.close();
  if (r != null) await record.finishOffset(save: r.save, makeDefault: r.makeDefault);
}

/// Contenido de la hoja. Cierra con `({save, makeDefault})`; el cierre real lo hace [showOffsetSheet].
class OffsetSheet extends ConsumerStatefulWidget {
  const OffsetSheet({super.key});

  @override
  ConsumerState<OffsetSheet> createState() => _OffsetSheetState();
}

class _OffsetSheetState extends ConsumerState<OffsetSheet> {
  bool _makeDefault = true;

  void _finish(bool save) {
    unawaited(ref.read(takeViewerStoreProvider.notifier).pause());
    Navigator.of(context).pop((save: save, makeDefault: save && _makeDefault));
  }

  void _togglePlay(TakeViewerState v) {
    final TakeViewerStore t = ref.read(takeViewerStoreProvider.notifier);
    if (!v.playing && v.duration > 0 && v.position >= v.duration - 1 / 30) {
      unawaited(t.seek(0).then((_) => t.play()));
      return;
    }
    unawaited(t.togglePlay());
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final RecordOffset? o = ref.watch(recordStoreProvider.select((s) => s.offset));
    final TakeViewerState v = ref.watch(takeViewerStoreProvider);
    final RecordStore store = ref.read(recordStoreProvider.notifier);
    final bool isNew = o?.isNew ?? false;
    final bool ready = v.isOpen && v.audioError == null && v.error == null;
    final num frameMs = o?.frameMs ?? 1000 / 30;
    final double value = (o?.valueMs ?? 0).toDouble();

    Widget step(String label, VoidCallback f) =>
        TfSecondaryButton(label: label, height: TfSize.offsetButtonHeight, onPressed: o == null ? null : f);

    return TfSheetScaffold(
      width: TfSize.sheetWidthWide,
      title: l.record_offsetTitle,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TfSpace.s16,
        children: <Widget>[
          Text(l.record_offsetHelp, style: TfText.body(TfSize.font13).copyWith(color: TfColors.muted)),
          // El recuadro 16:9 se encoge antes que el resto cuando la ventana es baja (1100×680).
          Flexible(child: Center(heightFactor: 1, child: _VideoBox(state: v, error: _error(l, v)))),
          Row(
            spacing: TfSpace.s8,
            children: <Widget>[
              TfSecondaryButton(
                key: const ValueKey<String>('offset-play'),
                label: l.record_offsetPlayPause,
                height: TfSize.offsetButtonHeight,
                onPressed: ready ? () => _togglePlay(v) : null,
              ),
              TfSecondaryButton(
                key: const ValueKey<String>('offset-restart'),
                label: l.record_offsetRestart,
                height: TfSize.offsetButtonHeight,
                onPressed: ready ? () => unawaited(ref.read(takeViewerStoreProvider.notifier).seek(0)) : null,
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Wrap(
                  spacing: TfSpace.s8,
                  runSpacing: TfSpace.s8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
              step(l.record_offsetMinusFrame, () => store.setOffset(frames: -1)),
              step(l.record_offsetMinusMs, () => store.setOffset(deltaMs: -1)),
              Semantics(
                label: l.record_offsetMsA11y,
                child: TfNumberField(
                  key: const ValueKey<String>('offset-field'),
                  value: value,
                  min: (o?.minMs ?? -500).toDouble(),
                  max: (o?.maxMs ?? 500).toDouble(),
                  decimals: value == value.roundToDouble() ? 0 : 1,
                  width: TfSize.offsetFieldWidth,
                  onChanged: o == null ? null : (double x) => store.setOffset(valueMs: x),
                ),
              ),
              Text(l.record_offsetUnit, style: TfText.body(TfSize.font13).copyWith(color: TfColors.muted)),
              step(l.record_offsetPlusMs, () => store.setOffset(deltaMs: 1)),
              step(l.record_offsetPlusFrame, () => store.setOffset(frames: 1)),
                  ],
                ),
              ),
              Text(l.record_offsetFrameNote(double.parse(frameMs.toStringAsFixed(1))), style: TfText.body(TfSize.font12).copyWith(color: TfColors.muted)),
            ],
          ),
          TfCheckbox(
            key: const ValueKey<String>('offset-default'),
            value: _makeDefault,
            label: l.record_offsetMakeDefault(o?.cameraName ?? ''),
            onChanged: (bool b) => setState(() => _makeDefault = b),
          ),
        ],
      ),
      actions: <Widget>[
        TfSecondaryButton(
          key: const ValueKey<String>('offset-cancel'),
          label: isNew ? l.record_offsetDiscard : l.record_cancel,
          onPressed: () => _finish(false),
        ),
        TfPrimaryButton(
          key: const ValueKey<String>('offset-save'),
          label: isNew ? l.record_offsetSaveTake : l.record_offsetSave,
          onPressed: () => _finish(true),
        ),
      ],
    );
  }

  static String? _error(AppLocalizations l, TakeViewerState v) {
    final String? m = v.audioError ?? v.error?.message;
    return m == null ? null : l.record_offsetLoadError(m);
  }
}

/// Recuadro 16:9 negro, radio 12, borde `line`: vídeo, spinner mientras carga o error en rojo.
class _VideoBox extends StatelessWidget {
  const _VideoBox({required this.state, required this.error});

  final TakeViewerState state;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (error != null) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(TfSpace.s16),
          child: Text(error!, style: TfText.body(TfSize.font13).copyWith(color: TfColors.danger)),
        ),
      );
    } else if (state.isOpen) {
      content = TfVideoSurface(textureId: state.textureId, frameSize: state.frameSize, rotation: state.videoRotation);
    } else {
      content = const Center(child: TfSpinner.small());
    }
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TfColors.black,
          borderRadius: BorderRadius.circular(TfRadius.tile),
          border: Border.all(color: TfColors.line, width: TfStroke.hairline),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(TfRadius.tile - TfStroke.hairline), child: content),
      ),
    );
  }
}
