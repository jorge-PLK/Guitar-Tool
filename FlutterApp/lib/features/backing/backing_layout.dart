import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Apila hijos con [spacing]; hijos de alto <= 0,5 no suman hueco. El último recibe
/// `clamp(available - usado, lastMinHeight, max(lastMinHeight, lastIdealHeight))`.
/// Si no cabe, el total excede [available] y el padre hace scroll (BackingView.swift:201-230).
class FillLastLayout extends MultiChildRenderObjectWidget {
  const FillLastLayout({
    super.key,
    required this.available,
    required this.spacing,
    required this.lastMinHeight,
    required this.lastIdealHeight,
    super.children,
  });

  final double available;
  final double spacing;
  final double lastMinHeight;
  final double lastIdealHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderFillLastLayout(
        available: available,
        spacing: spacing,
        lastMinHeight: lastMinHeight,
        lastIdealHeight: lastIdealHeight,
      );

  @override
  void updateRenderObject(BuildContext context, RenderFillLastLayout renderObject) {
    renderObject
      ..available = available
      ..spacing = spacing
      ..lastMinHeight = lastMinHeight
      ..lastIdealHeight = lastIdealHeight;
  }
}

class _Parent extends ContainerBoxParentData<RenderBox> {}

class RenderFillLastLayout extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _Parent>, RenderBoxContainerDefaultsMixin<RenderBox, _Parent> {
  RenderFillLastLayout({
    required double available,
    required double spacing,
    required double lastMinHeight,
    required double lastIdealHeight,
  })  : _available = available, // ignore: prefer_initializing_formals
        _spacing = spacing, // ignore: prefer_initializing_formals
        _lastMin = lastMinHeight,
        _lastIdeal = lastIdealHeight;

  double _available;
  double _spacing;
  double _lastMin;
  double _lastIdeal;

  set available(double v) => _set(_available, v, (x) => _available = x);
  set spacing(double v) => _set(_spacing, v, (x) => _spacing = x);
  set lastMinHeight(double v) => _set(_lastMin, v, (x) => _lastMin = x);
  set lastIdealHeight(double v) => _set(_lastIdeal, v, (x) => _lastIdeal = x);

  void _set(double old, double v, void Function(double) apply) {
    if (old == v) return;
    apply(v);
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _Parent) child.parentData = _Parent();
  }

  @override
  void performLayout() {
    final loose = BoxConstraints.tightFor(width: constraints.maxWidth);
    final kids = <RenderBox>[];
    for (var c = firstChild; c != null; c = childAfter(c)) {
      kids.add(c);
    }
    var y = 0.0;
    var anyBefore = false;
    for (var i = 0; i < kids.length; i++) {
      final c = kids[i];
      final isLast = i == kids.length - 1;
      if (isLast) {
        if (anyBefore) y += _spacing;
        final h = (_available - y).clamp(_lastMin, math.max(_lastMin, _lastIdeal)).toDouble();
        c.layout(loose.tighten(height: h), parentUsesSize: true);
      } else {
        c.layout(loose, parentUsesSize: true);
      }
      final h = c.size.height;
      if (!isLast && h <= 0.5) {
        (c.parentData! as _Parent).offset = Offset(0, y);
        continue;
      }
      if (!isLast && anyBefore) y += _spacing;
      (c.parentData! as _Parent).offset = Offset(0, y);
      y += h;
      anyBefore = true;
    }
    size = constraints.constrain(Size(constraints.maxWidth, y));
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
