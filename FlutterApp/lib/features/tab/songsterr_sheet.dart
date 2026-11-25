import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/tab/songsterr_choosing.dart';
import 'package:toneforge/features/tab/songsterr_failed.dart';
import 'package:toneforge/features/tab/songsterr_pairing.dart';
import 'package:toneforge/features/tab/songsterr_store.dart';
import 'package:toneforge/features/tab/songsterr_working.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_sheet.dart';

const double songsterrListWidth = 612;
const double songsterrSheetHeight = 640;
const double _maxWidth = 1320;
const double _windowMargin = TfSpace.s40;

/// Ancho de la hoja: 660 sin vista previa; con ella, min(1320, ventana − márgenes).
double songsterrSheetWidth(double window, {required bool preview}) => preview
    ? math.min(_maxWidth, window - 2 * _windowMargin)
    : songsterrListWidth + 2 * TfSpace.s24;

/// Muestra la hoja de Songsterr (`TfSheet`) mientras `songsterrStoreProvider.isOpen` y la
/// cierra cuando deja de estarlo (también tras `accept`/`automatic`: cierre en cliente).
class SongsterrSheetHost extends ConsumerStatefulWidget {
  const SongsterrSheetHost({super.key});

  @override
  ConsumerState<SongsterrSheetHost> createState() => _SongsterrSheetHostState();
}

class _SongsterrSheetHostState extends ConsumerState<SongsterrSheetHost> {
  BuildContext? _sheetContext;

  void _sync(bool open) {
    if (!mounted) return;
    if (open && _sheetContext == null) {
      showTfSheet<void>(
        context: context,
        onCancel: () => ref.read(songsterrStoreProvider.notifier).close(),
        builder: (BuildContext ctx) {
          _sheetContext = ctx;
          return const SongsterrSheet();
        },
      ).whenComplete(() => _sheetContext = null);
    } else if (!open && _sheetContext != null) {
      final BuildContext ctx = _sheetContext!;
      _sheetContext = null;
      if (ctx.mounted) Navigator.of(ctx).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool open = ref.watch(songsterrStoreProvider.select((s) => s.isOpen));
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync(open));
    return const SizedBox.shrink();
  }
}

/// Contenido de la hoja (TSS:23-41). `previewOpen` es estado de vista local.
class SongsterrSheet extends ConsumerStatefulWidget {
  const SongsterrSheet({super.key});

  @override
  ConsumerState<SongsterrSheet> createState() => _SongsterrSheetState();
}

class _SongsterrSheetState extends ConsumerState<SongsterrSheet> {
  bool _previewOpen = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final SongsterrSheetState? sheet = ref.watch(songsterrStoreProvider.select((s) => s.sheet));
    final TabSongsterrStage stage = sheet?.stage ?? TabSongsterrStage.choosing;
    final bool preview =
        _previewOpen && stage == TabSongsterrStage.choosing && sheet?.selected != null;
    final double width =
        songsterrSheetWidth(MediaQuery.sizeOf(context).width, preview: preview);
    const double padding = TfSpace.s24;
    final double previewWidth = width - 2 * padding - songsterrListWidth - TfSpace.s20;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      scopesRoute: true,
      namesRoute: true,
      label: l.tab_sheetTitle,
      child: Container(
        width: width,
        height: songsterrSheetHeight,
        padding: const EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: TfColors.bg,
          borderRadius: BorderRadius.circular(TfRadius.card),
        ),
        // El borde se pinta encima para no restar ancho a la lista de 612.
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TfRadius.card),
          border: Border.all(color: TfColors.line, width: TfStroke.hairline),
        ),
        child: DefaultTextStyle(
          style: TfText.body(13).copyWith(color: TfColors.text2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TfSpace.s20,
            children: <Widget>[
              SizedBox(
                width: songsterrListWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: TfSpace.s14,
                  children: <Widget>[
                    Text(
                      l.tab_sheetTitle,
                      style: TfText.display(22).copyWith(color: TfColors.text),
                    ),
                    Expanded(child: _step(stage, sheet)),
                  ],
                ),
              ),
              if (preview)
                // SLOT: SongsterrPreview (recibe `sheet.selected` y `previewWidth`)
                SizedBox(
                  key: const ValueKey<String>('songsterr-preview-slot'),
                  width: previewWidth,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _step(TabSongsterrStage stage, SongsterrSheetState? sheet) {
    switch (stage) {
      case TabSongsterrStage.choosing:
        if (sheet == null) return const SizedBox.shrink();
        return SongsterrChoosing(
          sheet: sheet,
          previewOpen: _previewOpen,
          onOpenPreview: () => setState(() => _previewOpen = true),
        );
      case TabSongsterrStage.working:
        return SongsterrWorking(text: sheet?.workingText);
      case TabSongsterrStage.failed:
        return SongsterrFailed(issue: sheet?.failure);
      case TabSongsterrStage.pairing:
        return SongsterrPairing(pairing: sheet?.pairing);
      case TabSongsterrStage.unknown:
        return const SizedBox.shrink();
    }
  }
}
