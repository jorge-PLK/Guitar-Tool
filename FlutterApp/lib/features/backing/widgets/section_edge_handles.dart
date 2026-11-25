import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/section_boxes_geometry.dart';
import 'package:toneforge/features/backing/widgets/section_boxes_painter.dart';
import 'package:toneforge/features/backing/widgets/section_edge_drag.dart';
import 'package:toneforge/theme/tokens.dart';

// TOKEN: sectionEdgeStartDistance 1 (DragGesture(minimumDistance: 1), SB:150)
const double _startDistance = 1;

/// Las dos asas de la sección seleccionada, para el `Stack` de [SectionBoxesLayer]: fuera del bucle de trozos
/// y con clave fija para que el arrastre sobreviva al cambio de fila (ficha §6.5).
/// [pieces] son los trozos de esa sección, en orden; tira: uno; rejilla: uno por fila.
List<Widget> sectionEdgeHandles({required List<SectionPlacement> pieces, required EdgeTimeMapper mapper}) {
  if (pieces.isEmpty) return const <Widget>[];
  return <Widget>[
    _handle(pieces.first, true, mapper),
    _handle(pieces.last, false, mapper),
  ];
}

Widget _handle(SectionPlacement p, bool isStart, EdgeTimeMapper mapper) {
  final double x = isStart ? p.rect.left : p.rect.right;
  final double h = p.rect.height - p.headerHeight;
  return Positioned(
    key: ValueKey<String>(isStart ? 'section-edge-start' : 'section-edge-end'),
    left: x - TfSize.sectionEdgeGrab / 2,
    top: p.rect.top + p.headerHeight,
    width: TfSize.sectionEdgeGrab,
    height: h,
    child: SectionEdgeHandle(piece: p, isStart: isStart, mapper: mapper),
  );
}

class SectionEdgeHandle extends ConsumerStatefulWidget {
  const SectionEdgeHandle({required this.piece, required this.isStart, required this.mapper, super.key});

  final SectionPlacement piece;
  final bool isStart;
  final EdgeTimeMapper mapper;

  @override
  ConsumerState<SectionEdgeHandle> createState() => _SectionEdgeHandleState();
}

class _EdgeRecognizer extends PanGestureRecognizer {
  _EdgeRecognizer({super.debugOwner}) {
    dragStartBehavior = DragStartBehavior.down;
  }

  /// Flutter entrega `onEnd` (no `onCancel`) si el sistema cancela un arrastre ya aceptado.
  bool canceled = false;

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerCancelEvent) canceled = true;
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(PointerDeviceKind pointerDeviceKind, double? deviceTouchSlop) =>
      globalDistanceMoved.abs() > _startDistance;
}

class _SectionEdgeHandleState extends ConsumerState<SectionEdgeHandle> {
  SectionEdgeDragController? _drag;
  Offset _last = Offset.zero;

  Offset _local(Offset global) {
    final RenderStack? box = context.findAncestorRenderObjectOfType<RenderStack>();
    return box == null ? global : box.globalToLocal(global);
  }

  void _start(DragStartDetails d) {
    final SectionPlacement p = widget.piece;
    final StudyStore store = ref.read(studyStoreProvider.notifier);
    final SectionEdgePreview preview = ref.read(sectionEdgePreviewProvider.notifier);
    _last = _local(d.globalPosition);
    _drag = SectionEdgeDragController(
      id: p.section.id,
      isStart: widget.isStart,
      mapper: widget.mapper,
      anchor: Offset(
        widget.isStart ? p.rect.left + SectionBoxesGeometry.inset : p.rect.right - SectionBoxesGeometry.inset,
        p.rect.center.dy,
      ),
      grab: _last,
      preview: store.previewSectionEdge,
      commit: store.updateSection,
      onPreview: preview.set,
      onClear: preview.clear,
    );
  }

  void _update(DragUpdateDetails d) {
    _last = _local(d.globalPosition);
    _drag?.update(_last, bar: HardwareKeyboard.instance.isAltPressed);
  }

  void _end(DragEndDetails d) {
    _drag?.end(_last, bar: HardwareKeyboard.instance.isAltPressed);
    _drag = null;
  }

  void _cancel() {
    _drag?.cancel();
    _drag = null;
  }

  @override
  void dispose() {
    final SectionEdgeDragController? d = _drag;
    if (d != null) {
      // Sin notificar al provider durante el desmontaje: solo se marca cerrado.
      Future<void>.microtask(d.cancel);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SectionPlacement p = widget.piece;
    final Color color = sectionColor(solo: p.section.solo, paletteIndex: p.section.paletteIndex ?? p.index);
    final double barHeight = (p.rect.height - p.headerHeight - TfSize.sectionEdgeBarInset)
        .clamp(TfSize.sectionEdgeBarMin, TfSize.sectionEdgeBarMax);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          _EdgeRecognizer: GestureRecognizerFactoryWithHandlers<_EdgeRecognizer>(
            () => _EdgeRecognizer(debugOwner: this),
            (_EdgeRecognizer r) => r
              ..onStart = ((DragStartDetails d) {
                r.canceled = false;
                _start(d);
              })
              ..onUpdate = _update
              ..onEnd = ((DragEndDetails d) => r.canceled ? _cancel() : _end(d))
              ..onCancel = _cancel,
          ),
        },
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.all(Radius.circular(TfRadius.r3)),
            ),
            child: SizedBox(width: TfSize.sectionEdgeBarWidth, height: barHeight),
          ),
        ),
      ),
    );
  }
}
