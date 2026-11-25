import 'dart:convert';
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/record/record_store.dart';
import 'package:toneforge/features/record/widgets/record_bar.dart';
import 'package:toneforge/features/record/widgets/status_lines.dart';
import 'package:toneforge/l10n/app_localizations.dart';

import '../../support/harness.dart';

Json fx(String path) =>
    (json.decode(File('../Contract/fixtures/$path.json').readAsStringSync()) as Map).cast<String, Object?>();

Json state(String name) => fx('record/record.state.$name.event');

Future<MockCore> pump(WidgetTester tester, String variant, {bool? calibrated, double width = 800}) async {
  if (width != 800) await tester.runAsync(loadTfFonts); // métricas reales solo en el test de ancho
  tester.view.physicalSize = const Size(900, 400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final MockCore core = MockCore()
    ..result('study.open', <String, Object?>{})
    ..result('record.open', state(variant))
    ..result('audio.settings', fx('audio/audio.settings.result'))
    ..result('audio.setMeters', fx('audio/audio.setMeters.result'))
    ..result('record.start', state('counting'))
    ..result('record.stop', state('idle'))
    ..result('record.setCountIn', state(variant))
    ..result('record.setPunch', state(variant));
  final ProviderContainer c = ProviderContainer(overrides: [coreClientProvider.overrideWithValue(core)]);
  addTearDown(c.dispose);
  await tester.runAsync(() async {
    c.listen(recordStoreProvider, (_, _) {});
    await c.read(recordStoreProvider.notifier).open('p1');
    if (calibrated != null) {
      core.emit('audio.state', {...fx('audio/audio.state.event'), 'calibrationValid': calibrated});
      await pumpEventQueue();
    }
  });
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: Localizations(
      locale: const Locale('es'),
      delegates: AppLocalizations.localizationsDelegates,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: const Column(children: [RecordBar(), RecordStatusLines()])),
        ),
      ),
    ),
  ));
  await tester.pump();
  return core;
}

double opacity(WidgetTester tester) =>
    tester.widget<Opacity>(find.descendant(of: find.byType(RecordButton), matching: find.byType(Opacity))).opacity;

List<String> methods(MockCore core) => [for (final m in core.calls) m.method];

void main() {
  testWidgets('idle: Grabar al 100 % y pulsar envía record.start', (tester) async {
    final core = await pump(tester, 'idle');
    expect(find.text('Grabar'), findsOneWidget);
    expect(opacity(tester), 1);
    expect(find.textContaining('/ '), findsOneWidget);
    await tester.tap(find.byType(RecordButton));
    await tester.pump();
    expect(methods(core), contains('record.start'));
  });

  for (final String v in ['counting', 'recording']) {
    testWidgets('$v: Parar al 100 % y pulsar envía record.stop', (tester) async {
      final core = await pump(tester, v);
      expect(find.text('Parar'), findsOneWidget);
      expect(opacity(tester), 1);
      await tester.tap(find.byType(RecordButton));
      await tester.pump();
      expect(methods(core), contains('record.stop'));
    });
  }

  for (final String v in ['finishing', 'adjusting']) {
    testWidgets('$v: botón al 0,4 y sin acción', (tester) async {
      final core = await pump(tester, v);
      expect(opacity(tester), 0.4);
      await tester.tap(find.byType(RecordButton));
      await tester.pump();
      expect(methods(core), isNot(contains('record.start')));
      expect(methods(core), isNot(contains('record.stop')));
    });
  }

  testWidgets('bloqueado por código: botón al 0,4 y texto de record_block_punchNoMarks', (tester) async {
    final core = await pump(tester, 'punch-armed-no-marks');
    expect(opacity(tester), 0.4);
    expect(find.text('Marca la entrada y la salida del punch-in en la línea de tiempo.'), findsOneWidget);
    await tester.tap(find.byType(RecordButton));
    await tester.pump();
    expect(methods(core), isNot(contains('record.start')));
  });

  testWidgets('sin calibrar: aviso y botón activo', (tester) async {
    await pump(tester, 'idle', calibrated: false);
    expect(find.textContaining('Sin calibrar'), findsOneWidget);
    expect(opacity(tester), 1);
  });

  testWidgets('ancho justo: la etiqueta de desfase ocupa el hueco libre y no se trunca con «…»', (tester) async {
    await pump(tester, 'camera-live', width: 560);
    final Finder label = find.textContaining('Desfase de la cámara');
    expect(label, findsOneWidget);
    final RenderParagraph p = tester.renderObject<RenderParagraph>(label);
    expect(p.didExceedMaxLines, isFalse);
    // El hueco libre es ~ todo el sobrante, no la mitad: la etiqueta supera los 100 px.
    expect(tester.getSize(label).width, greaterThan(150));
  });

  testWidgets('calibrado: sin aviso', (tester) async {
    await pump(tester, 'idle', calibrated: true);
    expect(find.textContaining('Sin calibrar'), findsNothing);
  });

  testWidgets('ocupado: opciones deshabilitadas, no llaman al store', (tester) async {
    final core = await pump(tester, 'recording');
    await tester.tap(find.text('Cuenta de 1 compás'));
    await tester.tap(find.text('Punch-in'));
    await tester.pump();
    expect(methods(core), isNot(contains('record.setCountIn')));
    expect(methods(core), isNot(contains('record.setPunch')));
  });

  testWidgets('opciones: casilla llama al store al cambiar; el montaje inicial no llama', (tester) async {
    final core = await pump(tester, 'idle');
    expect(methods(core), isNot(contains('record.setCountIn')));
    await tester.tap(find.text('Cuenta de 1 compás'));
    await tester.pump();
    expect(methods(core).where((m) => m == 'record.setCountIn').length, 1);
  });
}
