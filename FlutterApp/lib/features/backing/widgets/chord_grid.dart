import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/study_position.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/chord_grid_geometry.dart';
import 'package:toneforge/features/backing/widgets/chord_grid_painter.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

/// Rejilla expandida (CG:116-192): filas de 4 compases (8 si cabe), scroll vertical sin barra, autoscroll a la
/// fila del compás actual. Clic = saltar al pulso; arrastre = bucle (⌥ = compases). En edición no hay gesto de bucle
/// y el clic en una celda con acorde llama a [onEditChord] con su posición en `analysis.chords`.
class ChordGrid extends ConsumerStatefulWidget {
  const ChordGrid({super.key, this.sectionsLayer, this.onEditChord});

  /// SLOT: GridSectionBoxesLayer. Capa sobre las celdas, en coordenadas del contenido, con la geometría de la rejilla.
  final Widget Function(BuildContext context, ChordGridGeometry geometry)? sectionsLayer;
  final void Function(int chordIndex)? onEditChord;

  @override
  ConsumerState<ChordGrid> createState() => _ChordGridState();
}

class _ChordGridState extends ConsumerState<ChordGrid> {
  final ScrollController _scroll = ScrollController();
  StudyAnalysisInfo? _analysis;
  ChordGridLayout? _layout;
  int _perRow = 0;
  List<List<GridBar>> _rows = const <List<GridBar>>[];
  int? _lastRow;
  Offset? _down;
  bool _moved = false;
  (double, double)? _drag;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Reconstruye compases y filas solo si cambian los datos o las columnas.
  void _sync(StudyAnalysisInfo a, int perRow) {
    if (!identical(a, _analysis)) {
      _analysis = a;
      _layout = ChordGridLayout.build(beats: a.beats, downbeats: a.downbeats, bpm: a.bpm, chords: a.chords);
      _perRow = 0;
    }
    if (perRow != _perRow && _layout != null) {
      _perRow = perRow;
      _rows = _layout!.rows(perRow);
    }
  }

  /// Autoscroll: la fila del compás actual, centrada (CG:171-173).
  void _follow(int row, {required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      // Centro de la fila con su franja superior: `row·68 + (18 + 46)/2`.
      final double center =
          row * ChordGridGeometry.rowPitch + (ChordGridGeometry.sectionGutter + ChordGridGeometry.rowHeight) / 2;
      final double target =
          (center - ChordGridGeometry.visibleHeight / 2).clamp(0.0, _scroll.position.maxScrollExtent);
      if (animate) {
        _scroll.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  /// Punto → pulso, con los pulsos del compás pulsado (nunca null con rejilla).
  GridBeat? _beatAt(Offset p, ChordGridGeometry g) {
    if (_rows.isEmpty) return null;
    final GridCell probe = g.hitTest(p, rows: _rows.length, beats: 1);
    final List<GridBar> row = _rows[probe.row];
    final GridBar bar = row[math.min(probe.col, row.length - 1)];
    final GridCell cell = g.hitTest(p, rows: _rows.length, beats: bar.cells.length);
    return bar.cells[math.min(cell.beat, bar.cells.length - 1)];
  }

  (double, double)? _range(GridBeat? a, GridBeat? b) {
    if (a == null || b == null) return null;
    final GridBeat lo = a.time <= b.time ? a : b;
    final GridBeat hi = a.time <= b.time ? b : a;
    return (lo.time, hi.end);
  }

  void _onDown(PointerDownEvent e) {
    if ((e.buttons & kPrimaryButton) == 0) return;
    _down = e.localPosition;
    _moved = false;
  }

  void _onMove(PointerMoveEvent e, ChordGridGeometry g, bool edit) {
    final Offset? d0 = _down;
    if (d0 == null || (e.localPosition - d0).distance < ChordGridGeometry.clickSlop) return;
    if (edit) {
      _moved = true; // en edición no hay bucle, pero un arrastre tampoco es un clic
      return;
    }
    final (double, double)? r = _range(_beatAt(d0, g), _beatAt(e.localPosition, g));
    if (r == null) return;
    setState(() {
      _moved = true;
      _drag = r;
    });
  }

  void _onUp(PointerUpEvent e, ChordGridGeometry g, bool edit, AppLocalizations l) {
    final Offset? d0 = _down;
    _down = null;
    if (d0 == null) return;
    if (_drag != null) setState(() => _drag = null);
    final GridBeat? a = _beatAt(d0, g), b = _beatAt(e.localPosition, g);
    if (a == null || b == null) return;
    final bool drag = _moved && (e.localPosition - d0).distance >= ChordGridGeometry.clickSlop;
    if (edit) {
      if (!drag && a.chord != null) widget.onEditChord?.call(a.chord!);
      return;
    }
    final StudyStore store = ref.read(studyStoreProvider.notifier);
    if (!drag) {
      store.seek(a.time);
      return;
    }
    final (double, double) r = _range(a, b)!;
    final bool bar = HardwareKeyboard.instance.isAltPressed;
    store.setLoop(
      r.$1,
      r.$2,
      name: bar ? l.backing_loopNameBars : l.backing_loopNameChords,
      snap: bar ? StudySnap.bar : StudySnap.beat,
    );
  }

  void _onCancel(PointerCancelEvent e) {
    _down = null;
    if (_drag != null) setState(() => _drag = null);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final StudyOpenResult? study = ref.watch(studyStoreProvider.select((s) => s.study));
    final bool edit = ref.watch(studyStoreProvider.select((s) => s.editMode));
    final double seconds = ref.watch(studyPositionProvider.select((p) => p.seconds));
    return SizedBox(
      height: ChordGridGeometry.visibleHeight,
      child: LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
        final ChordGridGeometry g = ChordGridGeometry(c.maxWidth);
        if (study != null) _sync(study.analysis, g.perRow);
        final ChordGridLayout? layout = study == null ? null : _layout;
        if (layout == null) {
          return Center(
            child: Text(l.backing_noGrid, style: TfText.body(13).copyWith(color: TfColors.muted)),
          );
        }
        final int row = layout.barIndexAt(seconds) ~/ g.perRow;
        if (row != _lastRow) {
          _follow(row, animate: _lastRow != null);
          _lastRow = row;
        }
        final StudyLoop? active = study!.transport.loop;
        final (double, double)? loop = _drag ?? (active == null ? null : (active.start, active.end));
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            scrollbars: false,
            // El arrastre con el puntero dibuja el bucle; la rueda y el trackpad desplazan.
            dragDevices: <PointerDeviceKind>{PointerDeviceKind.trackpad},
          ),
          child: SingleChildScrollView(
            controller: _scroll,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onDown,
              onPointerMove: (PointerMoveEvent e) => _onMove(e, g, edit),
              onPointerUp: (PointerUpEvent e) => _onUp(e, g, edit, l),
              onPointerCancel: _onCancel,
              child: SizedBox(
                key: const ValueKey<String>('chord-grid-content'),
                width: g.width,
                height: g.contentHeight(_rows.length),
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: CustomPaint(
                        key: const ValueKey<String>('chord-grid-paint'),
                        painter: ChordGridPainter(
                          rows: _rows,
                          geometry: g,
                          seconds: seconds,
                          loop: loop,
                          barLabel: (int n) => l.backing_barLabel(n),
                        ),
                      ),
                    ),
                    // SLOT: GridSectionBoxesLayer
                    if (widget.sectionsLayer != null)
                      Positioned.fill(child: widget.sectionsLayer!(context, g)),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
