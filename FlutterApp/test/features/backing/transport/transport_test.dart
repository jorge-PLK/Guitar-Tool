import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/backing/widgets/info_row.dart';
import 'package:toneforge/features/backing/widgets/loop_marking.dart';
import 'package:toneforge/features/backing/widgets/transport_row.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_slider.dart';

import '../../../support/harness.dart';

const String _id = '00000000-0000-0000-0000-000000000005';

late MockCore core;
late ProviderContainer container;

Json _transport(Json open) => (open['transport']! as Map).cast<String, Object?>();

Future<void> pumpRows(WidgetTester tester, {void Function(Json open)? tweak}) async {
  await tester.runAsync(loadTfFonts);
  final src = (await tester.runAsync(() => DirectoryFixtureSource.find()))!;
  core = (await tester.runAsync(() => MockCore.load(src)))!;
  final path = (await tester.runAsync(() async => (await src.list()).firstWhere((p) => p.endsWith('study.open.result.json'))))!;
  final open = (json.decode((await tester.runAsync(() => src.read(path)))!) as Map).cast<String, Object?>();
  tweak?.call(open);
  core.result('study.open', open);
  for (final String m in <String>['study.setCapo', 'study.setTranspose', 'study.setRate']) {
    core.result(m, open['transport']);
  }
  setTestSurface(tester, const Size(1100, 1400));
  container = ProviderContainer(overrides: [
    coreClientProvider.overrideWithValue(core),
    launchOptionsProvider.overrideWithValue(const LaunchOptions()),
  ]);
  addTearDown(container.dispose);
  container.read(selectedProjectProvider.notifier).select(_id);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: WidgetsApp(
      color: TfColors.bg,
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) => PageRouteBuilder<T>(
        settings: s,
        pageBuilder: (BuildContext c, Animation<double> a, Animation<double> b2) => b(c),
      ),
      home: const Align(
        alignment: Alignment.topLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            InfoRow(),
            TransportRow(),
            SizedBox(width: 400, child: CoalescedPositionBar()),
          ],
        ),
      ),
    ),
  ));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

List<String> get _methods => <String>[for (final m in core.calls) m.method];
Json _params(String method) => (core.calls.lastWhere((m) => m.method == method).params! as Map).cast();

Future<void> _emitPosition(WidgetTester tester, double s, {bool playing = false}) async {
  core.emit('study.position', <String, Object?>{'seconds': s, 'playing': playing});
  await _settle(tester);
}

TextStyle _styleOf(WidgetTester tester, String text) => tester.widget<Text>(find.text(text)).style!;

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.tap(f);
  await _settle(tester);
}

bool _hasIcon(TfIcon i) => find.byWidgetPredicate((w) => w is TfIconView && w.icon == i).evaluate().isNotEmpty;

void main() {
  testWidgets('play llama y cambia a pausa; pausa llama study.pause', (tester) async {
    await pumpRows(tester);
    expect(_hasIcon(TfIcon.playFill), isTrue);
    await _tap(tester, find.byKey(const ValueKey<String>('transport_play')));
    expect(_methods, contains('study.play'));
    expect(_hasIcon(TfIcon.pauseFill), isTrue);
    await _tap(tester, find.byKey(const ValueKey<String>('transport_play')));
    expect(_methods, contains('study.pause'));
  });

  testWidgets('el reloj formatea m:ss / m:ss', (tester) async {
    await pumpRows(tester, tweak: (o) {
      o['duration'] = 200;
      _transport(o)['duration'] = 200;
    });
    await _emitPosition(tester, 75.9);
    expect(find.textContaining('1:15 / 3:20', findRichText: true), findsOneWidget);
  });

  testWidgets('Inicio pasa a «Inicio m:ss» en accent y habilita Fin; Fin crea el bucle', (tester) async {
    await pumpRows(tester);
    expect(find.text('Inicio'), findsOneWidget);
    await _emitPosition(tester, 2);
    await _tap(tester, find.text('Inicio'));
    expect(_styleOf(tester, 'Inicio 0:02').color, TfColors.accent);
    await _emitPosition(tester, 5);
    await _tap(tester, find.text('Fin'));
    expect(_params('study.setLoop'), <String, Object?>{'start': 2.0, 'end': 5.0});
    expect(find.text('Inicio'), findsOneWidget);
  });

  testWidgets('Fin deshabilitado sin inicio ni bucle', (tester) async {
    await pumpRows(tester);
    await _emitPosition(tester, 5);
    await _tap(tester, find.text('Fin'));
    expect(_methods, isNot(contains('study.setLoop')));
  });

  testWidgets('píldora visible con bucle y su X llama clearLoop', (tester) async {
    await pumpRows(tester, tweak: (o) => _transport(o)['loop'] = <String, Object?>{'start': 1.0, 'end': 3.0});
    expect(find.text('Bucle: libre · 0:01–0:03'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey<String>('loop_clear')));
    expect(_params('study.setLoop'), isEmpty);
  });

  testWidgets('sin bucle no hay píldora', (tester) async {
    await pumpRows(tester);
    expect(find.textContaining('Bucle:'), findsNothing);
  });

  testWidgets('tempo con paso 5: teclado → setRate = %/100', (tester) async {
    await pumpRows(tester);
    expect(find.text('100 %'), findsOneWidget);
    final Finder slider = find.byWidgetPredicate((w) => w is TfSlider && w.max == 200);
    await tester.tapAt(tester.getTopLeft(slider) + Offset(tester.getSize(slider).width * 0.5, 10));
    await _settle(tester);
    final double rate = (_params('study.setRate')['rate']! as num).toDouble();
    expect((rate * 100) % 5, closeTo(0, 1e-9));
    expect(rate, inInclusiveRange(0.5, 2.0));
  });

  testWidgets('metrónomo deshabilitado sin beats', (tester) async {
    await pumpRows(tester, tweak: (o) {
      (o['analysis']! as Map)['beats'] = <double>[];
      ((o['transport']! as Map)['metronome']! as Map)['available'] = false;
    });
    await _tap(tester, find.text('Metrónomo'));
    expect(_methods, isNot(contains('study.setMetronome')));
  });

  testWidgets('metrónomo con beats llama setMetronome', (tester) async {
    await pumpRows(tester);
    await _tap(tester, find.text('Metrónomo'));
    expect(_params('study.setMetronome')['on'], true);
  });

  testWidgets('transponer, capo y afinación fina llaman su método', (tester) async {
    await pumpRows(tester, tweak: (o) => _transport(o)['capo'] = 3);
    expect(find.text('0 semitonos'), findsOneWidget);
    expect(find.text('Traste 3'), findsOneWidget);
    await _tap(tester, find.text('Traste 3'));
    await _tap(tester, find.text('Sin capo').last);
    expect(_params('study.setCapo')['capo'], 0);
    await _tap(tester, find.text('0 semitonos'));
    await tester.ensureVisible(find.text('+2').last);
    await _settle(tester);
    await _tap(tester, find.text('+2').last);
    expect(_params('study.setTranspose')['semitones'], 2);
    expect(find.text('0 cents'), findsOneWidget);
    final Finder fine = find.byWidgetPredicate((w) => w is TfSlider && w.max == 50);
    await tester.tapAt(tester.getTopLeft(fine) + Offset(tester.getSize(fine).width * 0.75, 10));
    await _settle(tester);
    expect((_params('study.setTranspose')['fineCents']! as num), greaterThan(0));
  });

  testWidgets('tonalidad muestra el nombre y llama setKeyShown', (tester) async {
    await pumpRows(tester);
    expect(find.text('Do mayor'), findsOneWidget);
    expect(find.text('125 BPM'), findsNothing);
    await _tap(tester, find.byKey(const ValueKey<String>('key_menu')));
    await _tap(tester, find.text('Re mayor'));
    expect(_params('study.setKey'), <String, Object?>{
      'shown': <String, Object?>{'tonic': 'D', 'mode': 'maj'},
    });
  });

  testWidgets('tonalidad deshabilitada sin análisis', (tester) async {
    await pumpRows(tester, tweak: (o) => (o['analysis']! as Map)['state'] = 'missing');
    await _tap(tester, find.byKey(const ValueKey<String>('key_menu')));
    expect(find.text('Re mayor'), findsNothing);
  });

  testWidgets('seek coalescido: ráfaga → primera inmediata y final', (tester) async {
    await pumpRows(tester);
    final Finder bar = find.byType(CoalescedPositionBar);
    final Offset o = tester.getTopLeft(bar) + const Offset(0, 11);
    final TestGesture g = await tester.startGesture(o + const Offset(40, 0));
    await g.moveTo(o + const Offset(80, 0));
    await g.moveTo(o + const Offset(160, 0));
    await g.moveTo(o + const Offset(200, 0));
    await tester.pump(const Duration(milliseconds: 5));
    expect(_methods.where((m) => m == 'study.seek').length, 1);
    await g.up();
    await tester.pump(const Duration(milliseconds: 200));
    final List<MockCall> seeks = core.calls.where((m) => m.method == 'study.seek').toList();
    expect(seeks.length, 2);
    final double last = ((seeks.last.params! as Map)['seconds']! as num).toDouble();
    expect(last, closeTo(200 / 400 * 8, 0.3));
  });
}
