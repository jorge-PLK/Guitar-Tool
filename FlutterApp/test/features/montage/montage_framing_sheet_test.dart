import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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

/// Núcleo cuyas respuestas de `montage.framingFrame` se resuelven a mano.
class _GatedCore extends MockCore {
  final List<({double time, Completer<void> done})> reqs = <({double time, Completer<void> done})>[];
  int _inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<T> call<T>(String method, Object? params, T Function(Json) decode) async {
    if (method != 'montage.framingFrame') return super.call(method, params, decode);
    final Completer<void> c = Completer<void>();
    reqs.add((time: ((params! as Map<Object?, Object?>)['time']! as num).toDouble(), done: c));
    maxInFlight = math.max(maxInFlight, ++_inFlight);
    try {
      await c.future;
    } finally {
      _inFlight--;
    }
    return super.call(method, params, decode);
  }
}

Future<void> _flush(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
  await t.pump();
}

Future<_Ctx> _pump(WidgetTester t, {Json? open, bool withFrame = true, MockCore? core0}) async {
  final MockCore core = (core0 ?? MockCore())
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
    await _settle(t);
    final List<MockCall> req = x.calls('montage.framingFrame');
    expect(req.length, 1);
    expect(req.single.params, {'takeId': _take, 'time': 3.5});
    expect(find.text('Sin imagen en este instante'), findsNothing);
    expect(find.text('Caja automática: arrástrala para moverla; el punto de la esquina la escala.'), findsOneWidget);
    await expectLater(find.byKey(const ValueKey<String>('sheet')), matchesGoldenFile('goldens/encuadre-fijo.png'));
  });

  testWidgets('instante en vivo: una petición en vuelo y al resolver se pide solo el último instante', (t) async {
    final _GatedCore core = _GatedCore();
    await _pump(t, core0: core);
    await _flush(t);
    expect(core.reqs.length, 1); // la inicial, al abrir
    core.reqs[0].done.complete();
    await _flush(t);

    final TestGesture g = await t.startGesture(t.getCenter(find.byType(TfSlider).first));
    await g.moveBy(const Offset(40, 0)); // supera la holgura del gesto
    await g.moveBy(const Offset(5, 0));
    await t.pump();
    await _flush(t);
    expect(core.reqs.length, 2); // la primera pasada pide al instante
    await g.moveBy(const Offset(-90, 0));
    await t.pump();
    await g.moveBy(const Offset(30, 0));
    await t.pump();
    await _flush(t);
    expect(core.reqs.length, 2); // nada en paralelo mientras la primera vuela
    expect(core.maxInFlight, 1);
    final double last = t.widget<TfSlider>(find.byType(TfSlider).first).value;
    expect(core.reqs[1].time, isNot(closeTo(last, 1e-9)));

    core.reqs[1].done.complete();
    await _flush(t);
    expect(core.reqs.length, 3);
    expect(core.reqs[2].time, closeTo(last, 1e-9));
    await g.up();
    core.reqs[2].done.complete();
    await _flush(t);
    expect(core.reqs.length, 3);
    expect(core.maxInFlight, 1);
  });

  testWidgets('respuesta tras cerrar la hoja: sin excepción ni setState', (t) async {
    final _GatedCore core = _GatedCore();
    await _pump(t, core0: core);
    await _flush(t);
    expect(core.reqs.length, 1);
    await t.pumpWidget(const SizedBox());
    core.reqs[0].done.complete();
    await _flush(t);
    expect(t.takeException(), isNull);
  });

  testWidgets('un error en una petición no bloquea la siguiente', (t) async {
    final _GatedCore core = _GatedCore();
    await _pump(t, core0: core);
    await _flush(t);
    core.reqs[0].done.completeError(const CoreError('no-frame', 'sin imagen'));
    await _flush(t);
    expect(find.text('Sin imagen en este instante'), findsOneWidget);

    await t.drag(find.byType(TfSlider).first, const Offset(40, 0));
    await _flush(t);
    expect(core.reqs.length, 2);
    core.reqs[1].done.complete();
    await _flush(t);
    expect(find.text('Sin imagen en este instante'), findsNothing);
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

  testWidgets('modo seguir: cambiar el zoom mueve la caja al valor de framingBox', (t) async {
    final _Ctx x = await _pump(t, open: _fx('open.framing-follow.result'));
    x.core.result('montage.framingBox', _fx('framingBox.framing-follow.result'));
    await _settle(t);
    await t.drag(find.byType(TfSlider).at(1), const Offset(30, 0));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await t.pump();
    final List<MockCall> q = x.calls('montage.framingBox');
    expect(q, isNotEmpty);
    final Map<Object?, Object?> p = q.first.params! as Map<Object?, Object?>;
    expect(p['takeId'], _take);
    expect(p['followZoom'], isNotNull);
    final FramingFrameArea area = t.widget<FramingFrameArea>(find.byType(FramingFrameArea));
    expect(area.box.width, closeTo(0.2, 1e-9));
    expect(area.box.left, closeTo(0.4225, 1e-9));
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

  Json withStatus(String status, double progress, {int? samples, int? detected, String? error}) {
    final Json j = _fx('open.result');
    final Map<String, Object?> f = ((j['framing']! as List).first! as Map<Object?, Object?>).cast<String, Object?>();
    f
      ..remove('samples')
      ..remove('detected')
      ..remove('error');
    j['framing'] = <Object?>[
      <String, Object?>{
        ...f,
        'status': status,
        'progress': progress,
        'samples': ?samples,
        'detected': ?detected,
        'error': ?error,
      },
    ];
    return j;
  }

  bool reanalyzeEnabled(WidgetTester t) => t
      .widget<TfSecondaryButton>(find.widgetWithText(TfSecondaryButton, 'Reanalizar'))
      .onPressed != null;

  final Map<String, (Json, String, bool)> cases = <String, (Json, String, bool)>{
    'queued': (withStatus('pending', 0), 'En cola para analizar la guitarra…', true),
    'analyzing': (withStatus('analyzing', 0.42), 'Analizando la guitarra… 42 %', false),
    'ready con detecciones': (
      withStatus('ready', 1, samples: 20, detected: 17),
      'Guitarra detectada en 17 de 20 muestras.',
      true,
    ),
    'ready sin detección': (
      withStatus('ready', 1, samples: 20, detected: 0),
      'Sin detección: se usa el fotograma entero, centrado. Puedes colocar la caja a mano.',
      true,
    ),
    'failed': (withStatus('failed', 0, error: 'sin vídeo'), 'No se pudo analizar la toma (sin vídeo).', true),
  };
  for (final MapEntry<String, (Json, String, bool)> e in cases.entries) {
    testWidgets('estado del análisis: ${e.key}', (t) async {
      await _pump(t, open: e.value.$1);
      await _settle(t);
      expect(find.text(e.value.$2), findsOneWidget);
      expect(reanalyzeEnabled(t), e.value.$3);
    });
  }

  testWidgets('sin imagen muestra el texto', (t) async {
    await _pump(t, withFrame: false);
    await _settle(t);
    expect(find.text('Sin imagen en este instante'), findsOneWidget);
  });
}
