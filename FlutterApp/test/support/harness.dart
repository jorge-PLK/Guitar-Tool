import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

// Harness único de tests de widgets. Para regenerar goldens:
// `TF_UPDATE_GOLDENS=1 Tools/test.sh FlutterApp <ruta>`.

const List<(String, String)> _faces = <(String, String)>[
  (TfFamily.inter, 'assets/fonts/inter-latin-400.ttf'),
  (TfFamily.inter, 'assets/fonts/inter-latin-500.ttf'),
  (TfFamily.inter, 'assets/fonts/inter-latin-600.ttf'),
  (TfFamily.spaceGrotesk, 'assets/fonts/space-grotesk-latin-500.ttf'),
  (TfFamily.spaceGrotesk, 'assets/fonts/space-grotesk-latin-700.ttf'),
];

bool _fontsLoaded = false;

/// Carga las 5 caras reales (Inter y Space Grotesk) para que los goldens no usen Ahem.
Future<void> loadTfFonts() async {
  if (_fontsLoaded) return;
  for (final (String family, String path) in _faces) {
    final FontLoader loader = FontLoader(family)..addFont(rootBundle.load(path));
    await loader.load();
  }
  _fontsLoaded = true;
}

/// Fija la superficie de test a [size] con DPR 1 y la restaura al acabar.
void setTestSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// `WidgetsApp` mínima con Navigator (Overlay) sobre `bg`; [home] es la pantalla.
Widget tfNavApp(Widget home) => WidgetsApp(
      color: TfColors.bg,
      debugShowCheckedModeBanner: false,
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) => PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (BuildContext c, Animation<double> a, Animation<double> b) => builder(c),
      ),
      home: home,
    );

// ---- K1: marco centrado con RepaintBoundary, gestos y geometría ----

/// Fondo `bg`, hijo centrado con margen para golden de un widget.
Widget k1Frame(Widget child, {Key? key, double pad = 16}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key ?? const ValueKey<String>('k1'),
          child: ColoredBox(
            color: TfColors.bg,
            child: Padding(padding: EdgeInsets.all(pad), child: child),
          ),
        ),
      ),
    );

/// Mantiene el puntero pulsado sobre [finder] y asienta el estado «pulsado».
Future<TestGesture> pressOn(WidgetTester tester, Finder finder) async {
  final TestGesture g = await tester.startGesture(tester.getCenter(finder));
  await tester.pump(const Duration(milliseconds: 150));
  return g;
}

/// Ratón sobre [finder] (hover).
Future<TestGesture> hoverOn(WidgetTester tester, Finder finder) async {
  final TestGesture g = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await g.addPointer(location: Offset.zero);
  await g.moveTo(tester.getCenter(finder));
  await tester.pump();
  return g;
}

/// Caja global (con transformaciones de los ancestros) de [finder].
Rect globalBounds(WidgetTester tester, Finder finder) {
  final RenderBox box = tester.renderObject<RenderBox>(finder);
  final Size s = box.size;
  final List<Offset> pts = <Offset>[
    box.localToGlobal(Offset.zero),
    box.localToGlobal(Offset(s.width, 0)),
    box.localToGlobal(Offset(0, s.height)),
    box.localToGlobal(Offset(s.width, s.height)),
  ];
  double minX = pts.first.dx, maxX = pts.first.dx, minY = pts.first.dy, maxY = pts.first.dy;
  for (final Offset p in pts) {
    if (p.dx < minX) minX = p.dx;
    if (p.dx > maxX) maxX = p.dx;
    if (p.dy < minY) minY = p.dy;
    if (p.dy > maxY) maxY = p.dy;
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

// ---- K2: app con Navigator y caja fija ----

const ValueKey<String> k2Boundary = ValueKey<String>('k2-boundary');

/// App mínima con Navigator (Overlay), atajos de Tab y fondo `bg`.
Widget k2App(Widget child, {Size size = const Size(320, 120)}) {
  return tfNavApp(
    DefaultTextStyle(
      style: TfText.body().copyWith(color: TfColors.text, decoration: TextDecoration.none),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          key: k2Boundary,
          width: size.width,
          height: size.height,
          child: ColoredBox(
            color: TfColors.bg,
            child: Padding(
              padding: const EdgeInsets.all(TfSpace.s16),
              child: Align(alignment: Alignment.topLeft, child: child),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Fila «etiqueta + control» para láminas de estados.
Widget k2Row(String label, Widget child) {
  return Padding(
    padding: const EdgeInsets.only(bottom: TfSpace.s8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: TfText.body(11).copyWith(color: TfColors.muted, decoration: TextDecoration.none),
          ),
        ),
        child,
      ],
    ),
  );
}

Finder k2Screen() => find.byType(WidgetsApp);

Future<void> pumpK2(WidgetTester tester, Widget child, {Size size = const Size(320, 120)}) async {
  setTestSurface(tester, size);
  await tester.pumpWidget(k2App(child, size: size));
  await tester.pump();
}

// ---- K3: hijo centrado sobre bg con clave ----

/// Monta [child] sobre `TfColors.bg` con su propia clave para goldens.
Future<void> pumpK3(WidgetTester tester, Widget child, {Key key = const ValueKey('k3')}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: ColoredBox(
          key: key,
          color: TfColors.bg,
          child: Padding(padding: const EdgeInsets.all(TfSpace.s16), child: child),
        ),
      ),
    ),
  );
}

// ---- K4: WidgetsApp con Overlay a DPR 1 ----

/// Monta [home] en una `WidgetsApp` (con Navigator y Overlay) sobre `bg`, a DPR 1.
Future<void> pumpK4(WidgetTester tester, Widget home, {Size size = const Size(640, 400)}) async {
  setTestSurface(tester, size);
  await tester.pumpWidget(
    tfNavApp(
      ColoredBox(
        color: TfColors.bg,
        child: DefaultTextStyle(style: TfText.body().copyWith(color: TfColors.text), child: home),
      ),
    ),
  );
}

/// Botón de prueba mínimo (no es el de K1): enfocable y pulsable.
class K4Button extends StatelessWidget {
  const K4Button({super.key, required this.label, this.onTap, this.focusNode, this.primary = false});

  final String label;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: TfSize.controlLg,
          padding: const EdgeInsets.symmetric(horizontal: TfSpace.s16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary ? TfColors.accent : TfColors.field,
            borderRadius: BorderRadius.circular(TfRadius.control),
            border: primary ? null : Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
          ),
          child: Text(
            label,
            style: TfText.body(14, TfWeight.semibold).copyWith(
              color: primary ? TfColors.accentInk : TfColors.text,
            ),
          ),
        ),
      ),
    );
  }
}

// ---- K5: superficie con límite de captura ----

const Key k5Boundary = ValueKey<String>('k5Boundary');

/// Monta [child] sobre `bg` en una superficie de [size] a 1x, con el límite de captura [k5Boundary].
Future<void> pumpK5(WidgetTester tester, Widget child, {Size size = const Size(800, 600)}) async {
  await tester.runAsync(loadTfFonts);
  await tester.pump();
  setTestSurface(tester, size);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: k5Boundary,
        child: ColoredBox(
          color: TfColors.bg,
          child: Align(alignment: Alignment.topLeft, child: child),
        ),
      ),
    ),
  );
}
