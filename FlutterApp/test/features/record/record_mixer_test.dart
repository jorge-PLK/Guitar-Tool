import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/record/mixer_store.dart';
import 'package:toneforge/features/record/record_store.dart';
import 'package:toneforge/features/record/widgets/record_mixer.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_fader.dart';
import 'package:toneforge/widgets/tf_slider.dart';
import 'package:toneforge/widgets/tf_toggle_button.dart';

import '../../support/harness.dart';

Json fx(String path) =>
    (json.decode(File('../Contract/fixtures/$path.json').readAsStringSync()) as Map).cast<String, Object?>();

Map<String, Object?> chan(String id, String name, {bool forced = false}) => {
      'forcedMuted': forced,
      'gainDB': -3,
      'id': id,
      'kind': id,
      'muted': false,
      'name': name,
      'solo': false,
    };

/// Abre Grabar con un mix de dos canales: «Bajo» normal y «Guitarra» forzada a silencio.
Future<(MockCore, ProviderContainer)> open({String? launchState}) async {
  final core = MockCore()
    ..result('study.open', <String, Object?>{})
    ..result('audio.settings', fx('audio/audio.settings.result'))
    ..result('record.open', fx('record/record.open.result'))
    ..result('audio.setMeters', fx('audio/audio.setMeters.result'))
    ..result('record.setMaster', fx('record/record.state.base.result'))
    ..result('record.setMix', fx('record/record.setMix.result'));
  final c = ProviderContainer(overrides: [
    coreClientProvider.overrideWithValue(core),
    if (launchState != null) launchOptionsProvider.overrideWithValue(LaunchOptions(state: launchState)),
  ]);
  addTearDown(c.dispose);
  c.listen(recordStoreProvider, (_, _) {});
  c.listen(mixerStoreProvider, (_, _) {});
  await c.read(recordStoreProvider.notifier).open('p1');
  final base = fx('record/record.state.base.result');
  final mix = Map<String, Object?>.of((base['mix'] as Map).cast<String, Object?>())
    ..['channels'] = [chan('bass', 'Bajo'), chan('guitar', 'Guitarra', forced: true)];
  core.emit('record.state', {...base, 'mix': mix});
  await pumpEventQueue();
  return (core, c);
}

Future<void> pumpMixer(WidgetTester tester, ProviderContainer c, {ValueChanged<bool>? onExpanded}) async {
  setTestSurface(tester, const Size(1100, 700));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: WidgetsApp(
        color: TfColors.bg,
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) =>
            PageRouteBuilder<T>(settings: s, pageBuilder: (c, _, _) => b(c)),
        home: Align(alignment: Alignment.topLeft, child: RecordMixer(onExpandedChanged: onExpanded)),
      ),
    ),
  );
  await tester.pump();
}

Finder toggle(String semantic) =>
    find.byWidgetPredicate((w) => w is TfToggleButton && w.semanticLabel == semantic);

Future<void> expand(WidgetTester tester) async {
  await tester.tap(find.text('Expandir'));
  await tester.pump();
}

void main() {
  testWidgets('plegado por defecto: Master, Tu guitarra y canales compactos', (tester) async {
    final (_, c) = (await tester.runAsync(open))!;
    await pumpMixer(tester, c);
    expect(find.text('Expandir'), findsOneWidget);
    expect(find.text('Master'), findsOneWidget);
    expect(find.text('Tu guitarra'), findsOneWidget);
    expect(find.text('Bajo'), findsOneWidget);
    expect(find.byType(TfFader), findsNothing);
  });

  testWidgets('--state mixer-expanded arranca desplegado y avisa al padre', (tester) async {
    final (_, c) = (await tester.runAsync(() => open(launchState: 'mixer-expanded')))!;
    final calls = <bool>[];
    await pumpMixer(tester, c, onExpanded: calls.add);
    await tester.pump();
    expect(find.text('Plegar'), findsOneWidget);
    expect(find.byType(TfFader), findsNWidgets(3));
    expect(calls, [true]);
  });

  testWidgets('expandir muestra faders y avisa al padre; plegar vuelve', (tester) async {
    final (_, c) = (await tester.runAsync(open))!;
    final calls = <bool>[];
    await pumpMixer(tester, c, onExpanded: calls.add);
    await expand(tester);
    expect(find.text('Plegar'), findsOneWidget);
    expect(find.byType(TfFader), findsNWidgets(3)); // Master + 2 canales
    expect(find.text('Entrada'), findsOneWidget);
    await tester.tap(find.text('Plegar'));
    await tester.pump();
    expect(find.byType(TfFader), findsNothing);
    expect(calls, [true, false]);
  });

  testWidgets('Master compacto: imán a 0 dB cuando |v| < 1,5', (tester) async {
    final (core, c) = (await tester.runAsync(open))!;
    await pumpMixer(tester, c);
    final Rect r = tester.getRect(find.byType(RecordMixer));
    expect(r.width, greaterThan(0));
    // Ancho 40, pomo 16: 0,5 dB cae en dx = 8 + 22 = 30 del deslizador.
    final Offset left = tester.getTopLeft(find.byType(TfSlider));
    await tester.tapAt(left + const Offset(30, 10));
    await tester.pump();
    expect((core.calls.last.params! as Map)['gainDB'], 0);
  });

  testWidgets('mute y solo llaman al store', (tester) async {
    final (core, c) = (await tester.runAsync(open))!;
    await pumpMixer(tester, c);
    await tester.tap(toggle('Silenciar Bajo'));
    await tester.pump();
    expect(core.calls.last.params, {'channel': 'bass', 'mute': true});
    await tester.tap(toggle('Solo Bajo'));
    await tester.pump();
    expect(core.calls.last.params, {'channel': 'bass', 'solo': true});
  });

  testWidgets('canal forcedMuted: M y S deshabilitados', (tester) async {
    final (core, c) = (await tester.runAsync(open))!;
    await pumpMixer(tester, c);
    final int n = core.calls.length;
    expect(tester.widget<TfToggleButton>(toggle('Activar Guitarra')).onPressed, isNull);
    expect(tester.widget<TfToggleButton>(toggle('Solo Guitarra')).onPressed, isNull);
    await tester.tap(toggle('Solo Guitarra'), warnIfMissed: false);
    await tester.pump();
    expect(core.calls.length, n);
  });

  testWidgets('doble clic en un fader = 0 dB', (tester) async {
    final (core, c) = (await tester.runAsync(open))!;
    await pumpMixer(tester, c);
    await expand(tester);
    final Finder fader = find.byType(TfFader).at(1); // canal «Bajo»
    await tester.tap(fader);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(fader);
    await tester.pump(const Duration(milliseconds: 100)); // vacía el temporizador del doble toque
    expect(core.calls.last.params, {'channel': 'bass', 'gainDB': 0.0});
  });
}
