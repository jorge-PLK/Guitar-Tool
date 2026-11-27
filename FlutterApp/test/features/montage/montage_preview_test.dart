import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/features/montage/montage_preview.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_slider.dart';

Future<void> pump(
  WidgetTester tester, {
  bool ready = true,
  bool playing = false,
  bool portrait = false,
  VoidCallback? onToggle,
  ValueChanged<Duration>? onSeek,
  ValueChanged<Duration>? onSeekEnd,
  Duration rangeStart = Duration.zero,
  Duration position = const Duration(seconds: 65),
  Duration duration = const Duration(seconds: 200),
  double width = 420,
}) async {
  tester.view.physicalSize = Size(width, 560);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: Localizations(
      locale: const Locale('es'),
      delegates: AppLocalizations.localizationsDelegates,
      child: RepaintBoundary(
      child: MontagePreviewColumn(
        textureId: null,
        frameSize: null,
        portrait: portrait,
        canvasLabel: portrait ? '9:16' : '16:9',
        sectionLabel: 'Estrofa',
        position: position,
        duration: duration,
        playing: playing,
        ready: ready,
        onTogglePlay: onToggle ?? () {},
        onSeek: onSeek ?? (_) {},
        onSeekEnd: onSeekEnd,
        rangeStart: rangeStart,
      ),
    ),
    ),
  ));
}

TfSlider slider(WidgetTester t) => t.widget<TfSlider>(find.byType(TfSlider));

void main() {
  testWidgets('ready: cabecera, tiempo y play habilitado (golden)', (tester) async {
    int taps = 0;
    await pump(tester, onToggle: () => taps++);
    expect(find.text('Vista previa · 16:9'), findsOneWidget);
    expect(find.text('1:05 · Estrofa'), findsOneWidget);
    expect(find.textContaining('1:05 / 3:20', findRichText: true), findsOneWidget);
    expect(slider(tester).onChanged, isNotNull);
    await tester.tap(find.byKey(const ValueKey<String>('montage-play')));
    expect(taps, 1);
    await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('goldens/montage_preview_ready.png'));
  });

  testWidgets('playing: cambia el icono a pausa y sigue tocable', (tester) async {
    int taps = 0;
    await pump(tester, playing: true, onToggle: () => taps++);
    await tester.tap(find.byKey(const ValueKey<String>('montage-play')));
    expect(taps, 1);
  });

  testWidgets('preparing: play y slider deshabilitados (golden)', (tester) async {
    int taps = 0;
    await pump(tester, ready: false, onToggle: () => taps++);
    expect(slider(tester).onChanged, isNull);
    await tester.tap(find.byKey(const ValueKey<String>('montage-play')), warnIfMissed: false);
    expect(taps, 0);
    await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('goldens/montage_preview_preparing.png'));
  });

  testWidgets('aspecto: 16/9 en horizontal y 9/16 en vertical', (tester) async {
    await pump(tester);
    final double land = tester.getSize(find.byType(AspectRatio)).aspectRatio;
    expect(land, closeTo(16 / 9, 0.01));
    await pump(tester, portrait: true);
    final double port = tester.getSize(find.byType(AspectRatio)).aspectRatio;
    expect(port, closeTo(9 / 16, 0.01));
    expect(find.text('Vista previa · 9:16'), findsOneWidget);
  });

  testWidgets('rangeStart es el mínimo del slider', (tester) async {
    await pump(tester, rangeStart: const Duration(seconds: 10));
    expect(slider(tester).min, 10000);
    expect(slider(tester).max, 200000);
  });

  testWidgets('arrastrar el slider llama a onSeek y al soltar a onSeekEnd', (tester) async {
    final List<Duration> seeks = <Duration>[];
    final List<Duration> ends = <Duration>[];
    await pump(tester, onSeek: seeks.add, onSeekEnd: ends.add);
    final Finder s = find.byType(TfSlider);
    final Offset c = tester.getCenter(s);
    final TestGesture g = await tester.startGesture(c);
    await g.moveBy(const Offset(30, 0)); // el primer movimiento solo acepta el gesto
    await g.moveBy(const Offset(30, 0));
    await g.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(seeks, isNotEmpty);
    expect(seeks.last, greaterThan(const Duration(seconds: 100)));
    expect(ends, hasLength(1));
  });

  testWidgets('formato m:ss y sección en la cabecera', (tester) async {
    await pump(tester, position: const Duration(seconds: 2), duration: const Duration(seconds: 5));
    expect(find.text('0:02 · Estrofa'), findsOneWidget);
    expect(find.textContaining('0:02 / 0:05', findRichText: true), findsOneWidget);
  });

  testWidgets('el relleno del vídeo va recortado al radio del marco menos el borde', (tester) async {
    await pump(tester);
    final Finder fill = find.byWidgetPredicate((Widget w) => w is ColoredBox && w.color == TfColors.videoBg);
    expect(fill, findsOneWidget);
    final Finder clip = find.ancestor(
      of: fill,
      matching: find.byWidgetPredicate(
        (Widget w) => w is ClipRRect && w.borderRadius == BorderRadius.circular(TfRadius.card - TfStroke.hairline),
      ),
    );
    expect(clip, findsOneWidget);
  });

  testWidgets('columna estrecha: cabecera en dos líneas', (tester) async {
    await pump(tester, width: 260);
    final Offset a = tester.getTopLeft(find.text('Vista previa · 16:9'));
    final Offset b = tester.getTopLeft(find.text('1:05 · Estrofa'));
    expect(b.dy, greaterThan(a.dy));
    expect(b.dx, a.dx);
  });
}
