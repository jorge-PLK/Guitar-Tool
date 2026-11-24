import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/record/record_store.dart';
import 'package:toneforge/features/record/widgets/punch_timeline.dart';
import 'package:toneforge/features/record/widgets/punch_timeline_painter.dart';
import 'package:toneforge/l10n/app_localizations.dart';

Json fx(String path) =>
    (json.decode(File('../Contract/fixtures/$path.json').readAsStringSync()) as Map).cast<String, Object?>();

/// Snapshot base de 100 s con downbeats cada 10 s y dos secciones.
Json snapshot({num? entry, num? exit}) {
  final base = fx('record/record.state.punch-armed-marks.event');
  return {
    ...base,
    'phase': 'idle',
    'duration': 100,
    'barSeconds': 10,
    'downbeats': [for (var i = 0; i <= 10; i++) i * 10.0],
    'sections': [
      {'id': 's1', 'name': 'Intro', 'paletteIndex': 0, 'solo': false, 'start': 0, 'end': 40},
      {'id': 's2', 'name': 'Estrofa', 'paletteIndex': 1, 'solo': false, 'start': 40, 'end': 100},
    ],
    'punch': {
      'enabled': true,
      'ready': entry != null && exit != null,
      'in': ?entry,
      'out': ?exit,
    },
  };
}

class PunchRig {
  PunchRig(this.core, this.c);
  final MockCore core;
  final ProviderContainer c;
  List<Map<String, Object?>> get punchCalls => [
        for (final m in core.calls)
          if (m.method == 'record.setPunch') (m.params as Map).cast<String, Object?>(),
      ];
}

Future<PunchRig> pumpTimeline(WidgetTester tester, {num? entry, num? exit, num? position}) async {
  tester.view.physicalSize = const Size(632, 220);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var cur = snapshot(entry: entry, exit: exit);
  final core = MockCore()
    ..result('study.open', <String, Object?>{})
    ..result('record.open', cur)
    ..result('audio.settings', fx('audio/audio.settings.result'))
    ..result('audio.setMeters', fx('audio/audio.setMeters.result'))
    ..handle('record.setPunch', (p) {
      cur = snapshot(entry: (p['in'] as num?) ?? (cur['punch'] as Map)['in'] as num?, exit: (p['out'] as num?) ?? (cur['punch'] as Map)['out'] as num?);
      return cur;
    });
  final c = ProviderContainer(overrides: [coreClientProvider.overrideWithValue(core)]);
  addTearDown(c.dispose);
  await tester.runAsync(() async {
    c.listen(recordStoreProvider, (_, _) {});
    await c.read(recordStoreProvider.notifier).open('p1');
  });
  if (position != null) {
    core.emit('record.position', {'phase': 'idle', 'playing': false, 'seconds': position});
    await tester.runAsync(pumpEventQueue);
  }
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: Localizations(
      locale: const Locale('es'),
      delegates: AppLocalizations.localizationsDelegates,
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(child: SizedBox(width: 632, child: PunchTimeline())),
        ),
      ),
    ),
  ));
  await tester.pump();
  return PunchRig(core, c);
}

Finder zone() => find.byWidgetPredicate((w) => w is CustomPaint && w.painter is PunchTimelinePainter);

/// Punto de la zona (600 px de ancho útil, 100 s: 6 px por segundo).
Offset at(WidgetTester tester, double seconds) => tester.getTopLeft(zone()) + Offset(seconds * 6, 27);

void main() {
  testWidgets('sin marcas: pinta y resume con guiones (golden)', (tester) async {
    await pumpTimeline(tester);
    expect(find.text('Entrada — · Salida —'), findsOneWidget);
    await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('goldens/punch_timeline_empty.png'));
  });

  testWidgets('con marcas y cabezal (golden)', (tester) async {
    await pumpTimeline(tester, entry: 20, exit: 62.5, position: 35);
    expect(find.text('Entrada 0:20,0 · Salida 1:02,5'), findsOneWidget);
    await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('goldens/punch_timeline_marks.png'));
  });

  testWidgets('clic marca la entrada y luego la salida, con imán al compás', (tester) async {
    final rig = await pumpTimeline(tester);
    await tester.tapAt(at(tester, 33));
    await tester.pump();
    expect(rig.punchCalls.single, {'in': 30.0, 'free': false});
    await tester.pump();
    await tester.tapAt(at(tester, 71));
    await tester.pump();
    expect(rig.punchCalls.last, {'out': 70.0, 'free': false});
  });

  testWidgets('con Alt no hay imán', (tester) async {
    final rig = await pumpTimeline(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.tapAt(at(tester, 33));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    final call = rig.punchCalls.single;
    expect(call['free'], isTrue);
    expect(call['in'] as num, closeTo(33, 0.01));
  });

  testWidgets('arrastre: mueve la salida (la más cercana) y fija el asa hasta soltar', (tester) async {
    final rig = await pumpTimeline(tester, entry: 20, exit: 60);
    final g = await tester.startGesture(at(tester, 58));
    await g.moveTo(at(tester, 84));
    await g.moveTo(at(tester, 22)); // sigue siendo la salida: cruza la entrada y se intercambian
    await g.up();
    await tester.pump();
    final outs = [for (final m in rig.punchCalls) m['out']];
    expect(rig.punchCalls.first, {'out': 60.0, 'free': false});
    expect(outs, [60.0, 80.0, 20.0]);
  });

  testWidgets('arrastre de la entrada más allá de la salida la deja sin salida', (tester) async {
    final rig = await pumpTimeline(tester, entry: 20, exit: 60);
    final g = await tester.startGesture(at(tester, 18));
    await g.moveTo(at(tester, 80));
    await tester.pump();
    expect(rig.punchCalls.last, {'in': 80.0, 'free': false});
    expect(find.textContaining('Salida —'), findsOneWidget); // reflejo local mientras se arrastra
    await g.up();
  });
}
