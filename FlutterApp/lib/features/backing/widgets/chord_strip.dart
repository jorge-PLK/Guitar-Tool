import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/chord_chip.dart';
import 'package:toneforge/features/backing/widgets/chord_editor.dart';
import 'package:toneforge/features/backing/widgets/chord_strip_menu.dart';
import 'package:toneforge/features/backing/widgets/section_boxes_geometry.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/widgets/tf_menu.dart';
import 'package:toneforge/widgets/tf_popover.dart';

/// Nombre que se ve de un acorde: el transpuesto si el núcleo lo da.
String chordShownName(StudyChord c) => c.display ?? c.name;

/// Geometría de la tira en coordenadas del contenido desplazable. Las cajas de sección se alinean con [rects].
class ChordStripLayout {
  const ChordStripLayout({required this.rects, required this.width});

  /// Hueco superior para los nombres de las cajas de sección (`SectionBoxes.headerHeight`).
  static const double topGap = 22;
  static const double gap = 3;
  static const double padH = 3;
  static const double spacing = 6;

  /// 40 + 22 + 3 + 2 + 12 (BT:212).
  static const double height = 79;
  static const double chipTop = topGap + gap;

  /// Marco de la caja de cada acorde (36 de alto), sin el número de compás.
  final List<Rect> rects;
  final double width;

  factory ChordStripLayout.compute(List<String> names) {
    double x = padH;
    final List<Rect> rects = <Rect>[];
    for (final String n in names) {
      final double w = ChordChip.widthFor(n);
      rects.add(Rect.fromLTWH(x, chipTop, w, ChordChip.boxHeight));
      x += w + spacing;
    }
    return ChordStripLayout(rects: rects, width: names.isEmpty ? 2 * padH : x - spacing + padH);
  }

  /// Acorde cuyo marco contiene [x]; en un hueco, el de `midX` más cercano (BT:281).
  int? indexAt(double x) {
    if (rects.isEmpty) return null;
    for (int i = 0; i < rects.length; i++) {
      if (rects[i].left <= x && x <= rects[i].right) return i;
    }
    int best = 0;
    for (int i = 1; i < rects.length; i++) {
      if ((rects[i].center.dx - x).abs() < (rects[best].center.dx - x).abs()) best = i;
    }
    return best;
  }
}

/// Número de compás de los acordes que abren compás (BT:253). Sin análisis, vacío.
Map<int, int> chordBarNumbers(List<StudyChord> chords, List<double> downbeats, double tolerance) {
  final Map<int, int> out = <int, int>{};
  int d = 0;
  for (int i = 0; i < chords.length; i++) {
    final double start = chords[i].start;
    while (d < downbeats.length && downbeats[d] < start - tolerance) {
      d++;
    }
    if (d < downbeats.length && (downbeats[d] - start).abs() <= tolerance) {
      out[i] = d + 1;
      d++;
    }
  }
  return out;
}

/// Tira de acordes (BT:176-231): scroll horizontal sin barra; clic = saltar, arrastre = bucle.
class ChordStrip extends ConsumerStatefulWidget {
  const ChordStrip({
    super.key,
    required this.chords,
    required this.current,
    required this.onSeek,
    required this.onLoop,
    this.downbeats = const <double>[],
    this.bpm,
    this.loopStart,
    this.loopEnd,
    this.edit = false,
    this.onEditChord,
    this.sectionsLayer,
  });

  /// Umbral de clic frente a arrastre en la tira (`clickSlop`, solo horizontal).
  static const double clickSlop = 4;

  final List<StudyChord> chords;
  final int? current;
  final List<double> downbeats;
  final double? bpm;
  final double? loopStart;
  final double? loopEnd;

  /// En edición se anula el gesto de bucle y el clic en un chip llama a [onEditChord].
  final bool edit;
  final void Function(int index)? onEditChord;
  final void Function(double seconds) onSeek;

  /// Rango de acordes arrastrado, con `bar` = ⌥/Alt (compases en vez de acordes).
  final void Function(double start, double end, {required bool bar}) onLoop;

  /// SLOT: SectionBoxesLayer. Capa sobre los chips, en coordenadas del contenido, con sus [ChordStripLayout.rects].
  final Widget Function(BuildContext context, ChordStripLayout layout)? sectionsLayer;

  @override
  ConsumerState<ChordStrip> createState() => _ChordStripState();
}

class _ChordStripState extends ConsumerState<ChordStrip> {
  final ScrollController _scroll = ScrollController();
  final Map<double, TfPopoverController> _pops = <double, TfPopoverController>{};
  ChordStripLayout _layout = const ChordStripLayout(rects: <Rect>[], width: 0);
  double _viewport = 0;
  double? _downX;
  bool _moved = false;
  (int, int)? _drag;

  @override
  void initState() {
    super.initState();
    _layout = _computeLayout();
    WidgetsBinding.instance.addPostFrameCallback((_) => _center(animate: false));
  }

  ChordStripLayout _computeLayout() =>
      ChordStripLayout.compute([for (final StudyChord c in widget.chords) chordShownName(c)]);

  @override
  void didUpdateWidget(ChordStrip old) {
    super.didUpdateWidget(old);
    if (!identical(old.chords, widget.chords)) _layout = _computeLayout();
    if (old.current != widget.current && widget.current != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _center(animate: true));
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Autoscroll al acorde actual, centrado (BT:213-216).
  void _center({required bool animate}) {
    final int? c = widget.current;
    if (!mounted || c == null || c >= _layout.rects.length || !_scroll.hasClients) return;
    final double target = (_layout.rects[c].center.dx - _viewport / 2)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    if (animate) {
      _scroll.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _scroll.jumpTo(target);
    }
  }

  bool get _bar => HardwareKeyboard.instance.isAltPressed;

  void _down(PointerDownEvent e) {
    if (widget.edit || (e.buttons & kPrimaryButton) == 0) return;
    // Las cabeceras de sección tienen clic, pulsación larga y menú propios: el Listener ve todo el
    // pointer que cruza la pila, así que se descarta por geometría (misma que la capa de cajas).
    if (e.localPosition.dy < ChordStripLayout.topGap) {
      final List<StudySectionInfo> sections = ref.read(studyStoreProvider).study?.sections ?? const <StudySectionInfo>[];
      final double x = e.localPosition.dx;
      for (final SectionPlacement p in SectionBoxesGeometry.strip(sections, widget.chords, _layout)) {
        if (x >= p.rect.left && x <= p.rect.right) return;
      }
    }
    _downX = e.localPosition.dx;
    _moved = false;
  }

  void _move(PointerMoveEvent e) {
    final double? x0 = _downX;
    if (x0 == null || (e.localPosition.dx - x0).abs() < ChordStrip.clickSlop) return;
    final int? a = _layout.indexAt(x0), b = _layout.indexAt(e.localPosition.dx);
    if (a == null || b == null) return;
    setState(() {
      _moved = true;
      _drag = (math.min(a, b), math.max(a, b));
    });
  }

  void _up(PointerUpEvent e) {
    final double? x0 = _downX;
    _downX = null;
    if (x0 == null) return;
    final int? a = _layout.indexAt(x0), b = _layout.indexAt(e.localPosition.dx);
    final bool drag = _moved && (e.localPosition.dx - x0).abs() >= ChordStrip.clickSlop;
    if (_drag != null) setState(() => _drag = null);
    if (a == null || b == null) return;
    if (!drag) {
      widget.onSeek(widget.chords[a].start);
    } else {
      widget.onLoop(
        widget.chords[math.min(a, b)].start,
        widget.chords[math.max(a, b)].end,
        bar: _bar,
      );
    }
  }

  void _cancel(PointerCancelEvent e) {
    _downX = null;
    if (_drag != null) setState(() => _drag = null);
  }

  @override
  Widget build(BuildContext context) {
    final List<StudyChord> chords = widget.chords;
    final double? ls = _drag == null ? widget.loopStart : chords[_drag!.$1].start;
    final double? le = _drag == null ? widget.loopEnd : chords[_drag!.$2].end;
    final Map<int, int> bars = chordBarNumbers(
      chords,
      widget.downbeats,
      widget.bpm != null && widget.bpm! > 0 ? 30 / widget.bpm! : 0.05,
    );
    final int? cur = widget.current;
    final AppLocalizations l = AppLocalizations.of(context);
    final StudyLoop? loop = ref.watch(studyStoreProvider.select((s) => s.study?.transport.loop));
    final List<StudySectionInfo> sections =
        ref.watch(studyStoreProvider.select((s) => s.study?.sections ?? const <StudySectionInfo>[]));
    final List<Widget> chips = <Widget>[];
    for (int i = 0; i < chords.length; i++) {
      final StudyChord c = chords[i];
      final double mid = (c.start + c.end) / 2;
      Widget chip = ChordChip(
        name: chordShownName(c),
        barNumber: bars[i],
        isCurrent: i == cur,
        isPast: cur != null && i < cur,
        inLoop: ls != null && le != null && mid >= ls && mid <= le,
      );
      if (widget.edit) {
        final TfPopoverController pop = _pops.putIfAbsent(c.start, TfPopoverController.new);
        chip = TfPopover(
          controller: pop,
          popoverBuilder: (BuildContext _) => ChordEditor(start: c.start, end: c.end),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                widget.onEditChord?.call(i);
                for (final TfPopoverController p in _pops.values) {
                  if (p != pop) p.hide();
                }
                pop.show();
              },
              child: chip,
            ),
          ),
        );
      }
      if (!widget.edit) {
        final List<TfMenuEntry> entries = chordStripMenuEntries(ref, c, loop, sections, l);
        if (entries.isNotEmpty) chip = TfContextMenu(entries: entries, child: chip);
      }
      chips.add(Positioned(left: _layout.rects[i].left, top: ChordStripLayout.chipTop, child: chip));
    }
    return SizedBox(
      height: ChordStripLayout.height,
      child: LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
        _viewport = c.maxWidth;
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            scrollbars: false,
            // El arrastre con el puntero dibuja el bucle; la rueda y el trackpad desplazan.
            dragDevices: <PointerDeviceKind>{PointerDeviceKind.trackpad},
          ),
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
              onPointerCancel: _cancel,
              child: SizedBox(
                key: const ValueKey<String>('chord-strip-content'),
                width: _layout.width,
                height: ChordStripLayout.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    ...chips,
                    // SLOT: SectionBoxesLayer
                    Positioned.fill(child: widget.sectionsLayer?.call(context, _layout) ?? const SizedBox.shrink()),
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
