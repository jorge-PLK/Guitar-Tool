import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../contract/record_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/icons.dart';
import '../../../theme/tokens.dart';
import '../../../theme/typography.dart';
import '../../../widgets/tf_alert.dart';
import '../../../widgets/tf_buttons.dart';
import '../../../widgets/tf_progress.dart';
import '../../../widgets/tf_sheet.dart';
import '../../../widgets/tf_video_surface.dart';
import '../record_store.dart';
import '../take_viewer_store.dart';
import '../widgets/viewer_controls.dart';

/// Abre el visor «Ver toma» (hoja de 720): `takeview.open` al abrir y `takeview.close` al cerrar.
Future<void> showTakeViewer(BuildContext context, {required String projectId, required String takeId}) async {
  final TakeViewerStore store = ProviderScope.containerOf(context).read(takeViewerStoreProvider.notifier);
  unawaited(store.open(projectId, takeId));
  await showTfSheet<void>(
    context: context,
    builder: (BuildContext ctx) => TakeViewerSheet(projectId: projectId, takeId: takeId),
  );
  await store.close();
}

/// Contenido de la hoja (TV:282-301). Estado en `takeViewerStoreProvider`; título y «mejor» salen de
/// `recordStoreProvider`. «Marcar como mejor» no cierra; «Eliminar…» confirma, cierra y borra.
class TakeViewerSheet extends ConsumerWidget {
  const TakeViewerSheet({super.key, required this.projectId, required this.takeId});

  final String projectId;
  final String takeId;

  static (RecordPart, RecordTake)? _find(RecordSnapshot? s, String takeId) {
    if (s == null) return null;
    for (final RecordPart p in s.parts) {
      for (final RecordTake t in p.takes) {
        if (t.id == takeId) return (p, t);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final TakeViewerState s = ref.watch(takeViewerStoreProvider);
    final (RecordPart, RecordTake)? found = _find(ref.watch(recordStoreProvider).snapshot, takeId);
    final bool best = found?.$2.best ?? false;
    final String title = found == null ? '' : l.record_takePill(found.$2.number, found.$1.name);
    final String? error = _errorText(l, s);
    // Cargando, o error del visor: controles deshabilitados (acciones siguen activas).
    final bool controls = s.isOpen && s.audioError == null;
    final NavigatorState nav = Navigator.of(context);
    final RecordStore record = ref.read(recordStoreProvider.notifier);

    return Stack(
      children: <Widget>[
        TfSheetScaffold(
          width: TfSize.sheetWidthWide,
          padding: TfSpace.s20,
          background: TfColors.bg,
          titleSize: 18,
          title: title,
          titleTrailing: best ? const _BestChip() : null,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TfSpace.s14,
            children: <Widget>[
              _VideoBox(state: s),
              ViewerControls(enabled: controls),
              if (error != null) Text(error, style: TfText.body(TfSize.font12).copyWith(color: TfColors.danger)),
              Row(
                spacing: TfSpace.s10,
                children: <Widget>[
                  TfSecondaryButton(
                    label: l.takeview_markBest,
                    onPressed: best ? null : () => record.markBest(takeId),
                  ),
                  const Spacer(),
                  TfSecondaryButton(
                    label: l.takeview_delete,
                    onPressed: () async {
                      final bool ok = await showTfConfirm(
                        context: context,
                        title: l.takeview_deleteTitle,
                        confirmLabel: l.takeview_deleteConfirm,
                        cancelLabel: l.record_cancel,
                        message: l.takeview_deleteBody,
                        destructive: true,
                      );
                      if (!ok) return;
                      nav.pop();
                      await record.deleteTake(takeId);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          top: TfSpace.s20,
          right: TfSpace.s20,
          child: Row(
            spacing: TfSpace.s12,
            children: <Widget>[
              Semantics(
                button: true,
                label: l.takeview_close,
                child: GestureDetector(
                  key: const ValueKey<String>('viewer-close'),
                  behavior: HitTestBehavior.opaque,
                  onTap: nav.maybePop,
                  child: const TfIconView(TfIcon.xmark, size: TfSize.viewerCloseIcon, color: TfColors.text2),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Error del visor (TV:287): del núcleo (`message`, sin códigos propios del visor) o del audio de la toma.
  static String? _errorText(AppLocalizations l, TakeViewerState s) {
    final String? audio = s.audioError;
    if (audio != null) return l.takeview_errPrepare(audio);
    final e = s.error;
    if (e != null) return l.takeview_errPrepare(e.message);
    if (s.video == TakeVideoState.error && s.videoMessage != null) return l.takeview_errPrepare(s.videoMessage!);
    return null;
  }
}

class _BestChip extends StatelessWidget {
  const _BestChip();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: TfColors.okBg, borderRadius: BorderRadius.all(Radius.circular(TfRadius.pill))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TfSpace.s8 + TfSpace.s1, vertical: TfSpace.s3),
        child: Text(
          AppLocalizations.of(context).takeview_bestChip,
          style: TfText.body(TfSize.font11, TfWeight.semibold).copyWith(color: TfColors.ok),
        ),
      ),
    );
  }
}

/// Pantalla negra 16:9, radio 10, borde `line` (TV:318-332).
class _VideoBox extends StatelessWidget {
  const _VideoBox({required this.state});

  final TakeViewerState state;

  @override
  Widget build(BuildContext context) {
    final TakeViewerState s = state;
    final bool failed = s.error != null || s.audioError != null || s.video == TakeVideoState.error;
    final bool spinner = !failed && (s.isLoading || s.phase == TakeViewerPhase.closed || s.video == TakeVideoState.converting);
    final Widget content;
    if (s.hasVideo) {
      content = TfVideoSurface(textureId: s.textureId, frameSize: s.frameSize);
    } else if (spinner) {
      content = const Center(child: TfSpinner.small());
    } else if (s.isOpen && s.video == TakeVideoState.none) {
      content = Center(
        child: Text(
          AppLocalizations.of(context).takeview_noVideo,
          style: TfText.body(TfSize.font12).copyWith(color: TfColors.muted),
        ),
      );
    } else {
      content = const SizedBox.shrink();
    }
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TfColors.black,
          borderRadius: BorderRadius.circular(TfRadius.control),
          border: Border.all(color: TfColors.line, width: TfStroke.hairline),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(TfRadius.control - TfStroke.hairline), child: content),
      ),
    );
  }
}
