import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/montage.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_card.dart';
import 'package:toneforge/widgets/tf_popover.dart';

import 'montage_cut_menu.dart';
import 'montage_store.dart';
import 'montage_timeline_labels.dart';
import 'montage_timeline_mapping.dart';
import 'widgets/montage_timeline_painter.dart';

/// Tarjeta de la línea de tiempo de Montaje (MV:499-725): etiquetas + carriles + leyenda.
class MontageTimeline extends ConsumerWidget {
  const MontageTimeline({super.key, required this.onOpenFraming});

  final ValueChanged<String> onOpenFraming;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(montageStoreProvider);
    final s = st.snapshot;
    if (s == null) return const SizedBox.shrink();
    final store = ref.read(montageStoreProvider.notifier);
    final l10n = AppLocalizations.of(context);
    final analyzing = {
      for (final l in s.lanes)
        if (st.framingStatus(l.takeId) == MontageFramingStatus.analyzing) l.takeId,
    };
    final legend = l10n.montageLegend(s.anticipationLabel) + (s.isSingleShot ? l10n.montageLegendCuts : '');
    return TfCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TfSpace.s18, vertical: TfSpace.s14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: TfSpace.s8, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: TfSpace.s10, children: [
            MontageTimelineLabels(
              snapshot: s,
              analyzing: analyzing,
              onOpenFraming: onOpenFraming,
              onRotate: store.rotateTake,
              onMoveLane: store.moveLane,
              onAddCut: () => _addAtCursor(ref),
            ),
            Expanded(child: MontageTimelineArea(key: _areaKey, snapshot: s)),
          ]),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(legend, style: TfText.body(TfSize.font12).copyWith(color: TfColors.muted))),
            if (s.isSingleShot && s.cuts.isNotEmpty)
              GestureDetector(
                onTap: store.clearCuts,
                // TODO(l10n): «Quitar cortes» sin clave en los ARB.
                child: Text('Quitar cortes', style: TfText.body(TfSize.font12).copyWith(color: TfColors.muted, decoration: TextDecoration.underline)),
              ),
          ]),
        ]),
      ),
    );
  }

  static final GlobalKey<MontageTimelineAreaState> _areaKey = GlobalKey<MontageTimelineAreaState>();

  Future<void> _addAtCursor(WidgetRef ref) async {
    final id = await ref.read(montageStoreProvider.notifier).addCut(ref.read(montagePositionProvider).seconds);
    if (id != null) _areaKey.currentState?.openMenu(id);
  }
}

/// Área de carriles: painter, cursor (capa propia) y gestos (MV:556-587, 657-693).
class MontageTimelineArea extends ConsumerStatefulWidget {
  const MontageTimelineArea({super.key, required this.snapshot});
  final MontageSnapshot snapshot;

  @override
  ConsumerState<MontageTimelineArea> createState() => MontageTimelineAreaState();
}

class MontageTimelineAreaState extends ConsumerState<MontageTimelineArea> {
  static const double _slop = 4;
  final TfPopoverController _menu = TfPopoverController();
  String? _menuCut;
  Offset? _down;
  String? _markId; // marca pulsada (modo marca) o null (modo seek)
  bool _moved = false;
  bool _inPlane = false;
  double? _dragTime;

  MontageStore get _store => ref.read(montageStoreProvider.notifier);

  void openMenu(String cutId) {
    setState(() => _menuCut = cutId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _menuCut == cutId) _menu.show();
    });
  }

  void _closeMenu() {
    _menu.hide();
    if (mounted) setState(() => _menuCut = null);
  }

  void _onDown(PointerDownEvent e, MontageTimelineGeometry g) {
    _down = e.localPosition;
    _moved = false;
    _dragTime = null;
    final i = g.cutAt(e.localPosition);
    _markId = i == null ? null : widget.snapshot.cuts[i].id;
    _inPlane = i == null && (g.planeRect?.contains(e.localPosition) ?? false);
    if (_markId == null) _store.seek(g.xToTime(e.localPosition.dx));
  }

  void _onMove(PointerMoveEvent e, MontageTimelineGeometry g) {
    if (_down == null) return;
    if ((e.localPosition - _down!).distance >= _slop) _moved = true;
    if (_markId == null) {
      _store.seek(g.xToTime(e.localPosition.dx));
    } else if (_moved) {
      setState(() => _dragTime = g.xToTime(e.localPosition.dx));
    }
  }

  void _onUp(PointerUpEvent e, MontageTimelineGeometry g) {
    final down = _down;
    if (down == null) return;
    _down = null;
    final id = _markId;
    if (id != null) {
      if (_moved) {
        _store.moveCut(id, g.xToTime(e.localPosition.dx));
        setState(() => _dragTime = null);
      } else {
        openMenu(id);
      }
      return;
    }
    _store.seekEnd();
    if (_inPlane && !_moved) {
      _store.addCut(g.xToTime(down.dx)).then((cut) {
        if (cut != null && mounted) openMenu(cut);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.snapshot;
    final base = montageTimelineData(s);
    final data = _dragTime == null || _markId == null
        ? base
        : _withDrag(base, s.cuts.indexWhere((c) => c.id == _markId), _dragTime!);
    return LayoutBuilder(builder: (context, box) {
      final g = MontageTimelineGeometry(data, box.maxWidth);
      final size = Size(box.maxWidth, g.totalHeight);
      return SizedBox(
        height: size.height,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _onDown(e, g),
              onPointerMove: (e) => _onMove(e, g),
              onPointerUp: (e) => _onUp(e, g),
              onPointerCancel: (_) => _down = null,
              child: RepaintBoundary(child: CustomPaint(size: size, painter: MontageTimelinePainter(data))),
            ),
          ),
          Positioned.fill(child: IgnorePointer(child: RepaintBoundary(child: _CursorLayer(geometry: g)))),
          if (_menuCut != null) _menuAnchor(s, g),
        ]),
      );
    });
  }

  MontageTimelineData _withDrag(MontageTimelineData d, int i, double t) => i < 0
      ? d
      : MontageTimelineData(
          axisStart: d.axisStart, axisEnd: d.axisEnd, spanStart: d.spanStart, spanEnd: d.spanEnd,
          barDuration: d.barDuration, fadeIn: d.fadeIn, fadeOut: d.fadeOut, sections: d.sections, lanes: d.lanes,
          missingCount: d.missingCount, showPlane: d.showPlane, planeShots: d.planeShots, gaps: d.gaps, cursor: d.cursor,
          cuts: [for (var k = 0; k < d.cuts.length; k++) k == i ? MontageCutMark(time: t, covered: d.cuts[k].covered) : d.cuts[k]],
        );

  Widget _menuAnchor(MontageSnapshot s, MontageTimelineGeometry g) {
    final i = s.cuts.indexWhere((c) => c.id == _menuCut);
    if (i < 0) return const SizedBox.shrink();
    final cut = s.cuts[i];
    final r = g.cutMarkRect(i);
    final names = {for (final l in s.lanes) l.id: l.partName};
    return Positioned.fromRect(
      rect: r,
      child: TfPopover(
        controller: _menu,
        onClosed: () => setState(() => _menuCut = null),
        popoverBuilder: (_) => MontageCutMenu(
          time: cut.time,
          selectedPartId: cut.partId,
          choices: [
            for (final id in s.cutCandidates)
              MontageCutChoice(id: id, name: names[id] ?? AppLocalizations.of(context).montageCutPartFallback, eligible: cut.eligible.contains(id)),
          ],
          onSelectPart: (p) {
            _store.setCutPart(cut.id, p);
            _closeMenu();
          },
          onDelete: () {
            _store.removeCut(cut.id);
            _closeMenu();
          },
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Cursor: la única capa que escucha `montagePositionProvider` (30 Hz).
class _CursorLayer extends ConsumerWidget {
  const _CursorLayer({required this.geometry});
  final MontageTimelineGeometry geometry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(montagePositionProvider.select((e) => e.seconds));
    return CustomPaint(painter: _CursorPainter(geometry, t));
  }
}

class _CursorPainter extends CustomPainter {
  const _CursorPainter(this.g, this.seconds);
  final MontageTimelineGeometry g;
  final double seconds;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      Rect.fromLTWH(g.timeToX(seconds) - TfStroke.thick / 2, 0, TfStroke.thick, g.totalHeight),
      Paint()..color = TfColors.text,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CursorPainter old) => old.seconds != seconds || old.g.width != g.width || old.g.data != g.data;
}
