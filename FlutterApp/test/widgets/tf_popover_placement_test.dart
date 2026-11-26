import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/widgets/tf_menu.dart';
import 'package:toneforge/widgets/tf_popover.dart';

const Key _anchor = Key('anchor');
const Key _panel = Key('panel');

Future<void> _pumpApp(WidgetTester tester, Size surface, Widget home) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFF000000),
      pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) =>
          PageRouteBuilder<T>(settings: s, pageBuilder: (c, a, s2) => b(c)),
      home: home,
    ),
  );
}

Widget _popover(TfPopoverController c, Alignment at, {double panelHeight = 100}) {
  return Align(
    alignment: at,
    child: TfPopover(
      controller: c,
      popoverBuilder: (_) => SizedBox(key: _panel, width: 120, height: panelHeight),
      child: const SizedBox(key: _anchor, width: 80, height: 30),
    ),
  );
}

Future<TfPopoverController> _openPopover(
  WidgetTester tester,
  Size surface,
  Alignment at, {
  double panelHeight = 100,
}) async {
  final TfPopoverController c = TfPopoverController();
  await _pumpApp(tester, surface, _popover(c, at, panelHeight: panelHeight));
  c.show();
  await tester.pumpAndSettle();
  return c;
}

Rect _box(WidgetTester tester, Key k) => tester.getRect(find.byKey(k));

void _inside(Size surface, Rect r) {
  expect(r.left, greaterThanOrEqualTo(-0.01));
  expect(r.top, greaterThanOrEqualTo(-0.01));
  expect(r.right, lessThanOrEqualTo(surface.width + 0.01));
  expect(r.bottom, lessThanOrEqualTo(surface.height + 0.01));
}

void main() {
  group('TfPopover', () {
    testWidgets('ancla abajo: el panel se abre encima', (tester) async {
      const Size s = Size(400, 300);
      await _openPopover(tester, s, Alignment.bottomLeft);
      final Rect a = _box(tester, _anchor);
      final Rect p = _box(tester, _panel);
      expect(p.bottom, lessThanOrEqualTo(a.top));
      _inside(s, p);
    });

    testWidgets('ancla arriba: el panel se abre debajo', (tester) async {
      const Size s = Size(400, 300);
      await _openPopover(tester, s, Alignment.topLeft);
      expect(_box(tester, _panel).top, greaterThanOrEqualTo(_box(tester, _anchor).bottom));
    });

    testWidgets('ventana baja: lado con más sitio y scroll', (tester) async {
      const Size s = Size(400, 120);
      await _openPopover(tester, s, Alignment.topLeft, panelHeight: 400);
      final Rect a = _box(tester, _anchor);
      final Rect surface = tester.getRect(find.byType(SingleChildScrollView));
      _inside(s, surface);
      expect(surface.top, greaterThanOrEqualTo(a.bottom));
      final ScrollableState sc = tester.state(find.byType(Scrollable));
      expect(sc.position.maxScrollExtent, greaterThan(0));
    });

    testWidgets('ancla en el borde derecho: el panel queda dentro', (tester) async {
      const Size s = Size(400, 300);
      await _openPopover(tester, s, Alignment.topRight);
      final Rect p = _box(tester, _panel);
      _inside(s, p);
      expect(p.right, lessThanOrEqualTo(s.width));
    });

    testWidgets('cerrado no deja nada montado en el overlay', (tester) async {
      const Size s = Size(400, 300);
      final TfPopoverController c = TfPopoverController();
      await _pumpApp(tester, s, _popover(c, Alignment.center));
      expect(find.byKey(_panel), findsNothing);
      expect(find.byType(CustomSingleChildLayout), findsNothing);
      expect(find.byType(GestureDetector), findsNothing);
      c.show();
      await tester.pumpAndSettle();
      expect(find.byKey(_panel), findsOneWidget);
      c.hide();
      await tester.pumpAndSettle();
      expect(find.byKey(_panel), findsNothing);
      expect(find.byType(CustomSingleChildLayout), findsNothing);
      expect(find.byType(GestureDetector), findsNothing);
    });
  });

  group('TfMenu / TfContextMenu', () {
    const List<TfMenuEntry> entries = <TfMenuEntry>[
      TfMenuItem(label: 'Uno', onSelected: _noop),
      TfMenuItem(label: 'Dos', onSelected: _noop),
      TfMenuItem(label: 'Tres', onSelected: _noop),
    ];

    Widget menu(Alignment at) => Align(
          alignment: at,
          child: TfMenu(
            entries: entries,
            builder: (BuildContext c, VoidCallback toggle) => GestureDetector(
              key: _anchor,
              behavior: HitTestBehavior.opaque,
              onTap: toggle,
              child: const SizedBox(width: 80, height: 30),
            ),
          ),
        );

    testWidgets('menú abajo se abre encima', (tester) async {
      const Size s = Size(400, 200);
      await _pumpApp(tester, s, menu(Alignment.bottomLeft));
      await tester.tap(find.byKey(_anchor));
      await tester.pumpAndSettle();
      final Rect a = _box(tester, _anchor);
      final Rect t = tester.getRect(find.text('Tres'));
      expect(t.bottom, lessThanOrEqualTo(a.top));
      _inside(s, t);
    });

    testWidgets('menú arriba se abre debajo', (tester) async {
      await _pumpApp(tester, const Size(400, 200), menu(Alignment.topLeft));
      await tester.tap(find.byKey(_anchor));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Uno')).top, greaterThanOrEqualTo(_box(tester, _anchor).bottom));
    });

    testWidgets('menú en el borde derecho queda dentro', (tester) async {
      const Size s = Size(400, 200);
      await _pumpApp(tester, s, menu(Alignment.topRight));
      await tester.tap(find.byKey(_anchor));
      await tester.pumpAndSettle();
      _inside(s, tester.getRect(find.text('Dos')));
    });

    testWidgets('ventana baja: el menú hace scroll dentro de la ventana', (tester) async {
      const Size s = Size(400, 70);
      await _pumpApp(tester, s, menu(Alignment.topLeft));
      await tester.tap(find.byKey(_anchor));
      await tester.pumpAndSettle();
      _inside(s, tester.getRect(find.byType(SingleChildScrollView)));
      final ScrollableState sc = tester.state(find.byType(Scrollable));
      expect(sc.position.maxScrollExtent, greaterThan(0));
    });

    testWidgets('menú contextual en la esquina inferior derecha', (tester) async {
      const Size s = Size(400, 200);
      await _pumpApp(
        tester,
        s,
        const TfContextMenu(entries: entries, child: SizedBox.expand(key: _anchor)),
      );
      const Offset click = Offset(395, 195);
      final TestGesture g = await tester.startGesture(
        click,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await g.up();
      await tester.pumpAndSettle();
      expect(find.text('Dos'), findsOneWidget);
      final Rect r = tester.getRect(find.byType(SingleChildScrollView));
      _inside(s, r);
      expect(r.bottom, lessThanOrEqualTo(click.dy));
      expect(r.right, lessThanOrEqualTo(s.width));
    });

    testWidgets('menú cerrado no monta nada', (tester) async {
      await _pumpApp(tester, const Size(400, 200), menu(Alignment.center));
      expect(find.text('Uno'), findsNothing);
      expect(find.byType(CustomSingleChildLayout), findsNothing);
    });
  });
}

void _noop() {}
