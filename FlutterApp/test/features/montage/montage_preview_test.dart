import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/features/montage/montage_preview.dart';
import 'package:toneforge/widgets/tf_slider.dart';

Future<void> pump(
  WidgetTester tester, {
  bool ready = true,
  bool playing = false,
  bool portrait = false,
  VoidCallback? onToggle,
  ValueChanged<Duration>? onSeek,
  ValueChanged<Duration>? onSeekEnd,
}) async {
  tester.view.physicalSize = const Size(420, 560);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: RepaintBoundary(
      child: MontagePreviewColumn(
        textureId: null,
        frameSize: null,
        portrait: portrait,
        canvasLabel: portrait ? '9:16' : '16:9',
        sectionLabel: 'Estrofa',
        position: const Duration(seconds: 65),
        duration: const Duration(seconds: 200),
        playing: playing,
        ready: ready,
        onTogglePlay: onToggle ?? () {},
        onSeek: onSeek ?? (_) {},
        onSeekEnd: onSeekEnd,
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
    expect(find.text('01:05 · Estrofa'), findsOneWidget);
    expect(find.text('01:05 / 03:20'), findsOneWidget);
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
}
