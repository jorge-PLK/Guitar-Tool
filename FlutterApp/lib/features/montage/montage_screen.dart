import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/montage.dart';
import 'package:toneforge/core/frame_channel.dart';
import 'package:toneforge/core/frame_providers.dart';
import 'package:toneforge/features/montage/montage_export_banner.dart';
import 'package:toneforge/features/montage/montage_framing_sheet.dart';
import 'package:toneforge/features/montage/montage_header.dart';
import 'package:toneforge/features/montage/montage_layout_column.dart';
import 'package:toneforge/features/montage/montage_preview.dart';
import 'package:toneforge/features/montage/montage_settings_column.dart';
import 'package:toneforge/features/montage/montage_song_picker.dart';
import 'package:toneforge/features/montage/montage_store.dart';
import 'package:toneforge/features/montage/montage_timeline.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/shell/shell_providers.dart';
import 'package:toneforge/shell/shell_route.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_card.dart';
import 'package:toneforge/widgets/tf_progress.dart';

// Geometría de MontageView.swift:100-120 (anchos de columna según ancho disponible).
const double _compactBelow = 900;
const double _layoutWide = 270;
const double _layoutCompact = 252;
const double _settingsWide = 300;
const double _settingsCompact = 276;
const double _rowHeight = 420;
const double _rowHeightPortrait = 440;

/// Pantalla Montaje (MontageView.swift:7-236): selector de tema, carga, error o contenido.
class MontageScreen extends ConsumerStatefulWidget {
  const MontageScreen({super.key});

  @override
  ConsumerState<MontageScreen> createState() => _MontageScreenState();
}

class _MontageScreenState extends ConsumerState<MontageScreen> {
  late final MontageStore _store;

  @override
  void initState() {
    super.initState();
    _store = ref.read(montageStoreProvider.notifier);
    Future<void>.microtask(() {
      if (!mounted) return;
      final String? id = ref.read(selectedProjectProvider);
      if (id != null && ref.read(montageStoreProvider).projectId == null) {
        unawaited(_store.open(id).catchError((Object _) {}));
      }
    });
    ref.listenManual<String?>(selectedProjectProvider, (String? prev, String? next) {
      if (next == prev) return;
      if (next == null) {
        unawaited(_store.close().catchError((Object _) {}));
      } else if (ref.read(montageStoreProvider).projectId != next) {
        unawaited(_store.open(next).catchError((Object _) {}));
      }
    });
  }

  @override
  void dispose() {
    final MontageStore store = _store;
    unawaited(Future<void>.microtask(store.close).catchError((Object _) {}));
    super.dispose();
  }

  void _goRecord() => ref.read(shellRouteProvider.notifier).select(ShellRoute.record);

  @override
  Widget build(BuildContext context) {
    final MontageState state = ref.watch(montageStoreProvider);
    switch (state.status) {
      case MontageStatus.noSong:
        return MontageSongPicker(songs: ref.watch(montageSongsProvider), onPick: _store.selectSong, onGoRecord: _goRecord);
      case MontageStatus.loading:
        return const Center(child: TfSpinner.small());
      case MontageStatus.error:
        return _LoadError(message: state.loadError!.message, onRetry: _store.retry);
      case MontageStatus.ready:
        return _Content(state: state, onGoRecord: _goRecord);
    }
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: TfSpace.s12,
        children: <Widget>[
          Text(message, style: TfText.body().copyWith(color: TfColors.danger)),
          TfSecondaryButton(label: l.montageRetry, onPressed: onRetry),
        ],
      ),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({required this.state, required this.onGoRecord});

  final MontageState state;
  final VoidCallback onGoRecord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MontageSnapshot s = state.snapshot!;
    final MontageStore store = ref.read(montageStoreProvider.notifier);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s36, vertical: TfSpace.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TfSpace.s16,
        children: <Widget>[
          MontageHeader(state: state, onExport: store.startExport, onCancelExport: store.cancelExport),
          MontageNotices(state: state, onDismissAction: store.clearActionError),
          if (state.export.phase != MontageExportPhase.idle)
            MontageExportBanner(export: state.export, onReveal: store.reveal, onDismiss: store.dismissExport),
          if (!s.hasVideo)
            TfCard(
              child: Padding(
                padding: const EdgeInsets.all(TfSpace.s20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: TfSpace.s12,
                  children: <Widget>[
                    Text(l.montageNoVideoTitle, style: TfText.display(TfSize.font18).copyWith(color: TfColors.text)),
                    Text(l.montageNoVideoBody, style: TfText.body().copyWith(color: TfColors.muted)),
                    TfSecondaryButton(label: l.montageGoRecord, onPressed: onGoRecord),
                  ],
                ),
              ),
            )
          else ...<Widget>[
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c) {
                final bool compact = c.maxWidth < _compactBelow;
                return SizedBox(
                  height: state.isPortrait ? _rowHeightPortrait : _rowHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: TfSpace.s16,
                    children: <Widget>[
                      SizedBox(width: compact ? _layoutCompact : _layoutWide, child: MontageLayoutColumn(snapshot: s)),
                      Expanded(child: _PreviewHost(state: state)),
                      SizedBox(width: compact ? _settingsCompact : _settingsWide, child: const MontageSettingsColumn()),
                    ],
                  ),
                );
              },
            ),
            MontageTimeline(onOpenFraming: (String id) => unawaited(showMontageFramingSheet(context, id))),
          ],
        ],
      ),
    );
  }
}

/// Textura de la vista previa + columna. Solo este subárbol escucha la posición a 30 Hz.
class _PreviewHost extends ConsumerStatefulWidget {
  const _PreviewHost({required this.state});

  final MontageState state;

  @override
  ConsumerState<_PreviewHost> createState() => _PreviewHostState();
}

class _PreviewHostState extends ConsumerState<_PreviewHost> {
  FrameChannel? _channel;
  int? _textureId;

  @override
  void initState() {
    super.initState();
    _channel = ref.read(frameChannelProvider(FrameChannelId.montage));
    final int? t = _channel?.create();
    _textureId = t != null && t >= 0 ? t : null;
  }

  @override
  void dispose() {
    _channel?.dispose();
    super.dispose();
  }

  static Duration _dur(double seconds) => Duration(milliseconds: (seconds * 1000).round());

  @override
  Widget build(BuildContext context) {
    final MontageSnapshot s = widget.state.snapshot!;
    final MontageStore store = ref.read(montageStoreProvider.notifier);
    final MontageRangeInfo span = s.transport.span;
    final MontagePreviewInfo p = s.preview;
    return TfCard(
      child: Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? _) {
          final MontagePositionEvent pos = ref.watch(montagePositionProvider);
          String? section;
          for (final MontageSectionInfo x in s.sections) {
            if (x.start <= pos.seconds && pos.seconds < x.end) {
              section = x.name;
              break;
            }
          }
          return MontagePreviewColumn(
            textureId: _textureId,
            frameSize: p.width > 0 && p.height > 0 ? Size(p.width.toDouble(), p.height.toDouble()) : null,
            portrait: widget.state.isPortrait,
            canvasLabel: widget.state.canvasLabel,
            sectionLabel: section,
            position: _dur(pos.seconds),
            duration: _dur(span.end),
            rangeStart: _dur(span.start),
            playing: pos.playing,
            ready: p.phase == MontagePreviewPhase.ready,
            onTogglePlay: () => unawaited(pos.playing ? store.pause() : store.play()),
            onSeek: (Duration d) => store.seek(d.inMilliseconds / 1000),
            onSeekEnd: (Duration _) => store.seekEnd(),
          );
        },
      ),
    );
  }
}
