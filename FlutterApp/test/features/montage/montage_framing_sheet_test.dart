import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart' show CoreError, Json;
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/library/library_store.dart';
import 'package:toneforge/features/montage/montage_framing_controls.dart';
import 'package:toneforge/features/montage/montage_framing_sheet.dart';
import 'package:toneforge/features/montage/montage_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_slider.dart';
import 'package:toneforge/widgets/tf_switch.dart';

import '../../support/harness.dart';

const String _pid = '00000000-0000-0000-0000-000000000003';
const String _take = '00000000-0000-0000-0000-000000000002';

Json _fx(String name) =>
    (json.decode(File('../Contract/fixtures/montage/montage.$name.json').readAsStringSync()) as Map<Object?, Object?>).cast<String, Object?>();

/// `open.result` con el análisis ya terminado (sin indicador de progreso).
Json _readyFixed() {
  final Json j = _fx('open.result');
  final List<Object?> framing = (j['framing']! as List).cast<Object?>();
  j['framing'] = <Object?>[
    <String, Object?>{...(framing.first! as Map<Object?, Object?>).cast<String, Object?>(), 'status': 'ready', 'progress': 1},
  ];
  return j;
}

class _FakeLibrary extends LibraryStore {
  @override
  LibraryState build() => const LibraryState(projectsFolder: '/Users/x/Projects');
}

class _Ctx {
  _Ctx(this.core, this.container);
  final MockCore core;
  final ProviderContainer container;
  List<MockCall> calls(String m) => core.calls.where((MockCall c) => c.method == m).toList();
}

Future<_Ctx> _pump(WidgetTester t, {Json? open, bool withFrame = true}) async {
  final MockCore core = MockCore()
    ..result('montage.open', open ?? _readyFixed())
    ..result('montage.close', <String, Object?>{})
    ..result('montage.setFraming', open ?? _readyFixed())
    ..result('montage.resetFraming', open ?? _readyFixed())
    ..result('montage.reanalyze', open ?? _readyFixed());
  if (withFrame) {
    core.result('montage.framingFrame', _fx('framingFrame.result'));
  } else {
    core.failWith('montage.framingFrame', const CoreError('no-frame', 'sin imagen'));
  }
  final ProviderContainer c = ProviderContainer(overrides: [
    coreClientProvider.overrideWithValue(core),
    libraryStoreProvider.overrideWith(_FakeLibrary.new),
  ]);
  addTearDown(c.dispose);
  c.listen(montageStoreProvider, (_, _) {});
  await t.runAsync(loadTfFonts);
  await t.runAsync(() => c.read(montageStoreProvider.notifier).open(_pid));
  setTestSurface(t, const Size(1000, 900));
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: WidgetsApp(
      color: TfColors.bg,
      debugShowCheckedModeBanner: false,
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) =>
          PageRouteBuilder<T>(settings: s, pageBuilder: (ctx, a, b2) => b(ctx)),
      home: DefaultTextStyle(
        style: TfText.body().copyWith(color: TfColors.text, decoration: TextDecoration.none),
        child: Align(
          alignment: Alignment.topCenter,
          child: RepaintBoundary(
            key: const ValueKey<String>('sheet'),
            child: MontageFramingSheet(
              takeId: _take,
              frameBuilder: (_) => const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: <Color>[Color(0xFF2B3A55), Color(0xFF6B4E71)]),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  return _Ctx(core, c);
}

Future<void> _settle(WidgetTester t, {int ms = 100}) async {
  await t.pump(Duration(milliseconds: ms));
  for (int i = 0; i < 4; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await t.pump();
  }
}

Rect _area(WidgetTester t) => t.getRect(find.byType(FramingFrameArea));

Json _manualBox(_Ctx x) => ((x.calls('montage.setFraming').last.params! as Map<Object?, Object?>)['manualBox'] as Map<Object?, Object?>).cast<String, Object?>();

void main() {
  testWidgets('abre y pide el fotograma en la mitad de la presencia', (t) async {
    final _Ctx x = await _pump(t);
    expect(find.text('Encuadre · Guitarra'), findsOneWidget);
    expect(x.calls('montage.framingFrame'), isEmpty);
    await _settle(t);
    final List<MockCall> req = x.calls('montage.framingFrame');
    expect(req.length, 1);
    expect(req.single.params, {'takeId': _take, 'time': 3.5});
    expect(find.text('Sin imagen en este instante'), findsNothing);
    expect(find.text('Caja automática: arrástrala para moverla; el punto de la esquina la escala.'), findsOneWidget);
    await expectLater(find.byKey(const ValueKey<String>('sheet')), matchesGoldenFile('goldens/encuadre-fijo.png'));
  });

  testWidgets('debounce: varias pasadas del deslizador de instante, una sola petición', (t) async {
    final _Ctx x = await _pump(t);
    await _settle(t);
    final Finder slider = find.byType(TfSlider).first;
    await t.drag(slider, const Offset(40, 0));
    await t.drag(slider, const Offset(-90, 0));
    await t.drag(slider, const Offset(30, 0));
    await t.pump(const Duration(milliseconds: 40));
    expect(x.calls('montage.framingFrame').length, 1);
    await _settle(t);
    expect(x.calls('montage.framingFrame').length, 2);
  });

  testWidgets('arrastre de la caja envía setFraming con manualBox', (t) async {
    final _Ctx x = await _pump(t);
    await _settle(t);
    final Rect a = _area(t);
    await t.dragFrom(a.topLeft + Offset(a.width * 0.3, a.height * 0.3), Offset(a.width * 0.1, a.height * 0.1));
    await _settle(t);
    final Json b = _manualBox(x);
    expect(b['x'] as double, closeTo(0.2, 0.01));
    expect(b['y'] as double, closeTo(0.2, 0.01));
    expect(b['width'], 0.5);
    expect((x.calls('montage.setFraming').last.params! as Map<Object?, Object?>)['takeId'], _take);
  });

  testWidgets('arrastre desde el punto escala y respeta el lado mínimo 0,05', (t) async {
    final _Ctx x = await _pump(t);
    await _settle(t);
    final Rect a = _area(t);
    final Offset handle = a.topLeft + Offset(a.width * 0.6, a.height * 0.6);
    await t.dragFrom(handle, Offset(a.width * 0.1, 0));
    await _settle(t);
    Json b = _manualBox(x);
    expect(b['x'], 0.1);
    expect(b['width'] as double, closeTo(0.6, 0.01));
    expect(b['height'] as double, closeTo(0.6, 0.01));

    await t.dragFrom(handle, Offset(-a.width * 0.9, 0));
    await _settle(t);
    b = _manualBox(x);
    expect(b['width'] as double, closeTo(FramingBoxMath.minSide, 1e-9));
    expect(b['height'] as double, closeTo(FramingBoxMath.minSide, 1e-9));
  });

  test('FramingBoxMath: mover acota al fotograma y escalar conserva la proporción', () {
    const Rect box = Rect.fromLTWH(0.1, 0.1, 0.5, 0.5);
    expect(FramingBoxMath.moved(box, 2, -2), const Rect.fromLTWH(0.5, 0, 0.5, 0.5));
    final Rect r = FramingBoxMath.resized(box, 5, 16 / 9);
    expect(r.width, closeTo(0.9, 1e-9));
    expect(r.height, closeTo(0.9, 1e-9));
  });

  testWidgets('el interruptor pasa a «seguir» y la hoja muestra zoom y desplazamiento', (t) async {
    final _Ctx x = await _pump(t);
    await _settle(t);
    await t.tap(find.byType(TfSwitch));
    await _settle(t);
    expect(x.calls('montage.setFraming').last.params, {'takeId': _take, 'mode': 'follow'});
  });

  testWidgets('modo seguir: sliders, ayuda y golden', (t) async {
    final _Ctx x = await _pump(t, open: _fx('open.framing-follow.result'));
    await _settle(t);
    expect(find.text('Zoom'), findsOneWidget);
    expect(find.text('×1.40'), findsOneWidget);
    expect(find.text('+0.10'), findsOneWidget);
    expect(find.text('-0.10'), findsOneWidget);
    expect(find.textContaining('El recorte sigue la trayectoria'), findsOneWidget);
    expect(
      find.byWidgetPredicate((Widget w) => w is Semantics && w.properties.label == 'Zoom, con valor ×1.40'),
      findsOneWidget,
    );
    await expectLater(find.byKey(const ValueKey<String>('sheet')), matchesGoldenFile('goldens/encuadre-seguir.png'));

    // Arrastre sobre el fotograma: desplaza el recorte.
    final Rect a = _area(t);
    await t.dragFrom(a.center, Offset(a.width * 0.1, 0));
    await _settle(t);
    final Map<Object?, Object?> p = x.calls('montage.setFraming').last.params! as Map<Object?, Object?>;
    expect((p['followOffset'] as Map<Object?, Object?>)['x'] as double, closeTo(0.2, 0.01));
  });

  testWidgets('Restablecer y Reanalizar llaman al store', (t) async {
    final _Ctx x = await _pump(t);
    await _settle(t);
    await t.tap(find.text('Restablecer'));
    await _settle(t);
    expect(x.calls('montage.resetFraming').single.params, {'takeId': _take});
    await t.tap(find.text('Reanalizar'));
    await _settle(t);
    expect(x.calls('montage.reanalyze').single.params, {'takeId': _take});
    expect(find.byType(TfPrimaryButton), findsOneWidget);
  });

  testWidgets('sin imagen muestra el texto', (t) async {
    await _pump(t, withFrame: false);
    await _settle(t);
    expect(find.text('Sin imagen en este instante'), findsOneWidget);
  });
}
