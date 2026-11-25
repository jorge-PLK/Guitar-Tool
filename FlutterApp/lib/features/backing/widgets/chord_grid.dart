import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/study_position.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/chord_editor.dart';
import 'package:toneforge/features/backing/widgets/chord_grid_geometry.dart';
import 'package:toneforge/features/backing/widgets/chord_grid_painter.dart';
import 'package:toneforge/features/backing/widgets/section_boxes_geometry.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_popover.dart';

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
  final TfPopoverController _pop = TfPopoverController();
  ({Rect rect, double start, double end, double time})? _editing;
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

  /// Marco de la celda del pulso pulsado, para anclar la hoja «Acorde».
  Rect? _cellRect(Offset p, ChordGridGeometry g) {
    if (_rows.isEmpty) return null;
    final GridCell probe = g.hitTest(p, rows: _rows.length, beats: 1);
    final List<GridBar> row = _rows[probe.row];
    final int col = math.min(probe.col, row.length - 1);
    final int beats = row[col].cells.length;
    final GridCell cell = g.hitTest(p, rows: _rows.length, beats: beats);
    return g.cellRect(probe.row, col, math.min(cell.beat, beats - 1), beats);
  }

  void _openEditor(GridBeat beat, Rect rect, StudyOpenResult? study) {
    final int? i = beat.chord;
    if (study == null || i == null || i >= study.analysis.chords.length) return;
    final StudyChord c = study.analysis.chords[i];
    setState(() => _editing = (rect: rect, start: c.start, end: c.end, time: beat.time));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pop.show();
    });
  }

  (double, double)? _range(GridBeat? a, GridBeat? b) {
    if (a == null || b == null) return null;
    final GridBeat lo = a.time <= b.time ? a : b;
    final GridBeat hi = a.time <= b.time ? b : a;
    return (lo.time, hi.end);
  }

  void _onDown(PointerDownEvent e, ChordGridGeometry g) {
    if ((e.buttons & kPrimaryButton) == 0) return;
    // Las cabeceras de sección tienen clic, pulsación larga y menú propios: sin seek ni bucle desde ahí
    // (misma geometría que la capa de cajas; solo sobre una caja de sección, como la tira).
    final List<StudySectionInfo> sections =
        ref.read(studyStoreProvider).study?.sections ?? const <StudySectionInfo>[];
    for (final SectionPlacement p in SectionBoxesGeometry.grid(sections, _rows, g)) {
      if (p.rect.contains(e.localPosition) && e.localPosition.dy < p.rect.top + p.headerHeight) {
        _down = null;
        return;
      }
    }
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
      if (!drag && a.chord != null) {
        widget.onEditChord?.call(a.chord!);
        final Rect? r = _cellRect(d0, g);
        if (r != null) _openEditor(a, r, ref.read(studyStoreProvider).study);
      }
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
      // El núcleo solo admite none/chord/bar (StudyMethods.swift:317-325): `beat` lo rechaza con bad-params.
      // Sin ⌥ el rango ya sale ajustado a pulsos de las celdas, así que no hace falta imán.
      snap: bar ? StudySnap.bar : StudySnap.none,
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
    if (!edit) _editing = null;
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
              onPointerDown: (PointerDownEvent e) => _onDown(e, g),
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
                    if (edit && _editing != null)
                      Positioned.fromRect(
                        rect: _editing!.rect,
                        child: IgnorePointer(
                          child: TfPopover(
                            controller: _pop,
                            onClosed: () => setState(() => _editing = null),
                            popoverBuilder: (BuildContext _) =>
                                ChordEditor(start: _editing!.start, end: _editing!.end, time: _editing!.time),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
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
