import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/frame_channel.dart';
import 'package:toneforge/core/frame_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/record/record_store.dart';
import 'package:toneforge/features/record/sheets/offset_sheet.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_checkbox.dart';
import 'package:toneforge/widgets/tf_video_surface.dart';

import '../../support/harness.dart';

Json fx(String path) =>
    (json.decode(File('../Contract/fixtures/$path.json').readAsStringSync()) as Map).cast<String, Object?>();

Json snapshot({bool isNew = false}) {
  final j = Map<String, Object?>.of(fx('record/record.adjustOffset.result'));
  j['offset'] = {...(j['offset']! as Map).cast<String, Object?>(), 'isNew': isNew};
  return j;
}

Future<MockCore> openSheet(WidgetTester tester, {bool isNew = false, bool openFails = false}) async {
  setTestSurface(tester, const Size(900, 1000));
  final core = MockCore()
    ..result('study.open', <String, Object?>{})
    ..result('record.open', snapshot(isNew: isNew))
    ..result('audio.settings', fx('audio/audio.settings.result'))
    ..result('audio.setMeters', fx('audio/audio.setMeters.result'))
    ..result('takeview.openOffset', fx('takeview/takeview.openOffset.result'))
    ..result('takeview.close', <String, Object?>{})
    ..result('takeview.pause', fx('takeview/takeview.pause.result'))
    ..result('takeview.seek', fx('takeview/takeview.seek.result'))
    ..result('takeview.play', {...fx('takeview/takeview.openOffset.result'), 'playing': true})
    ..result('record.setOffset', snapshot(isNew: isNew))
    ..result('record.finishOffset', fx('record/record.state.adjusting.event'));
  if (openFails) core.failWith('takeview.openOffset', const CoreError('open-failed', 'sin audio'));
  late ProviderContainer c;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      coreClientProvider.overrideWithValue(core),
      frameChannelProvider(FrameChannelId.take).overrideWithValue(null),
    ],
    child: WidgetsApp(
      color: TfColors.bg,
      debugShowCheckedModeBanner: false,
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) =>
          PageRouteBuilder<T>(settings: s, pageBuilder: (c, a, b2) => b(c)),
      home: DefaultTextStyle(
        style: const TextStyle(),
        child: Builder(
          builder: (context) {
            c = ProviderScope.containerOf(context);
            return GestureDetector(
              key: const ValueKey('open'),
              behavior: HitTestBehavior.opaque,
              onTap: () => showOffsetSheet(context),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    ),
  ));
  await tester.runAsync(() => c.read(recordStoreProvider.notifier).open('p1'));
  await tester.tap(find.byKey(const ValueKey('open')));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return core;
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

List<Object?> paramsOf(MockCore core, String m) => [for (final x in core.calls) if (x.method == m) x.params];
int count(MockCore c, String m) => c.calls.where((x) => x.method == m).length;

void main() {
  testWidgets('listo: abre takeview.openOffset, vídeo, rótulos de toma existente y casilla marcada', (t) async {
    final core = await openSheet(t);
    expect(count(core, 'takeview.openOffset'), 1);
    expect(find.text('Ajustar desfase'), findsOneWidget);
    expect(find.byType(TfVideoSurface), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
    expect(find.text('Fotograma = 33,3 ms'), findsOneWidget);
    expect(find.text('Guardar como desfase por defecto de esta cámara (Cámara simulada)'), findsOneWidget);
    expect(t.widget<TfCheckbox>(find.byKey(const ValueKey('offset-default'))).value, isTrue);
    expect(t.widget<TfSecondaryButton>(find.byKey(const ValueKey('offset-play'))).onPressed, isNotNull);
  });

  testWidgets('toma nueva: rótulos «Descartar toma» / «Guardar toma»', (t) async {
    await openSheet(t, isNew: true);
    expect(find.text('Descartar toma'), findsOneWidget);
    expect(find.text('Guardar toma'), findsOneWidget);
  });

  testWidgets('error al abrir: texto de error y reproducción deshabilitada', (t) async {
    await openSheet(t, openFails: true);
    expect(find.text('No se pudo abrir la toma (sin audio).'), findsOneWidget);
    expect(t.widget<TfSecondaryButton>(find.byKey(const ValueKey('offset-play'))).onPressed, isNull);
    expect(t.widget<TfSecondaryButton>(find.byKey(const ValueKey('offset-restart'))).onPressed, isNull);
  });

  testWidgets('pasos envían setOffset (fotograma, ms)', (t) async {
    final core = await openSheet(t);
    await t.tap(find.text('+1 ms'));
    await settle(t);
    await t.tap(find.text('−1 fotograma'));
    await settle(t);
    expect(paramsOf(core, 'record.setOffset'), [
      {'deltaMs': 1},
      {'frames': -1},
    ]);
  });

  testWidgets('reproducir y «Al principio» van por el visor', (t) async {
    final core = await openSheet(t);
    await t.tap(find.byKey(const ValueKey('offset-play')));
    await settle(t);
    expect(count(core, 'takeview.play'), 1);
    await t.tap(find.byKey(const ValueKey('offset-restart')));
    await settle(t);
    expect(paramsOf(core, 'takeview.seek').last, {'seconds': 0});
  });

  testWidgets('Guardar: takeview.close y luego finishOffset {save, makeDefault}', (t) async {
    final core = await openSheet(t);
    await t.tap(find.byKey(const ValueKey('offset-save')));
    await settle(t);
    final order = [for (final c in core.calls) c.method];
    expect(order.indexOf('takeview.close'), lessThan(order.indexOf('record.finishOffset')));
    expect(paramsOf(core, 'record.finishOffset'), [
      {'save': true, 'makeDefault': true}
    ]);
    expect(find.text('Ajustar desfase'), findsNothing);
  });

  testWidgets('Cancelar: finishOffset con save=false y makeDefault=false; casilla desmarcada no se envía', (t) async {
    final core = await openSheet(t);
    await t.tap(find.byKey(const ValueKey('offset-cancel')));
    await settle(t);
    expect(paramsOf(core, 'record.finishOffset'), [
      {'save': false, 'makeDefault': false}
    ]);
  });

  testWidgets('desmarcar la casilla: Guardar envía makeDefault=false', (t) async {
    final core = await openSheet(t);
    await t.tap(find.byKey(const ValueKey('offset-default')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('offset-save')));
    await settle(t);
    expect(paramsOf(core, 'record.finishOffset'), [
      {'save': true, 'makeDefault': false}
    ]);
  });
}
