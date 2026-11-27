import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart' show Json;
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/montage/montage_store.dart';
import 'package:toneforge/features/montage/montage_timeline.dart';
import 'package:toneforge/features/montage/montage_timeline_mapping.dart';
import 'package:toneforge/features/montage/widgets/montage_timeline_painter.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

import '../../support/harness.dart';

Json fx(String n) =>
    (json.decode(File('../Contract/fixtures/montage/montage.$n.json').readAsStringSync()) as Map).cast<String, Object?>();

const _pid = '00000000-0000-0000-0000-000000000003';

class Rig {
  Rig(this.core, this.c);
  final MockCore core;
  final ProviderContainer c;
  List<String> get methods => core.calls.map((m) => m.method).toList();
}

Json twoLanes() {
  final j = fx('open.result');
  final lanes = (j["lanes"] as List).cast<Map<String, Object?>>();
  final second = Map<String, Object?>.from(lanes.first)
    ..['id'] = '00000000-0000-0000-0000-000000000002'
    ..['takeId'] = '00000000-0000-0000-0000-000000000005'
    ..['partName'] = 'Bajo';
  return {...j, 'lanes': [...lanes, second]};
}

Future<Rig> pump(WidgetTester t, {String open = 'open.result', Json? snapshot}) async {
  await t.runAsync(loadTfFonts);
  setTestSurface(t, const Size(1100, 420));
  final core = MockCore()
    ..result('montage.open', snapshot ?? fx(open))
    ..result('montage.seek', snapshot ?? fx(open))
    ..result('montage.addCut', fx('addCut.result'))
    ..result('montage.removeCut', fx(open))
    ..result('montage.moveLane', snapshot ?? fx(open))
    ..result('montage.moveCut', fx(open))
    ..result('montage.snapCut', fx('snapCut.result'))
    ..result('montage.setCutPart', fx(open))
    ..result('montage.rotateTake', fx(open));
  final c = ProviderContainer(overrides: [coreClientProvider.overrideWithValue(core)]);
  addTearDown(c.dispose);
  c.listen(montageStoreProvider, (_, _) {});
  await t.runAsync(() => c.read(montageStoreProvider.notifier).open(_pid));
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: WidgetsApp(
      color: TfColors.bg,
      debugShowCheckedModeBanner: false,
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) => PageRouteBuilder<T>(settings: s, pageBuilder: (a, _, _) => b(a)),
      home: DefaultTextStyle(
        style: TfText.body().copyWith(color: TfColors.text),
        child: RepaintBoundary(
          key: const ValueKey('shot'),
          child: ColoredBox(
            color: TfColors.bg,
            child: Padding(padding: const EdgeInsets.all(16), child: Align(alignment: Alignment.topLeft, child: MontageTimeline(onOpenFraming: (_) {}))),
          ),
        ),
      ),
    ),
  ));
  await t.pump();
  return Rig(core, c);
}

Future<void> settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
  await t.pump();
}

Offset areaPoint(WidgetTester t, double dx, double dy) => t.getTopLeft(find.byType(MontageTimelineArea)) + Offset(dx, dy);

// El Draggable solo recibe el gesto sobre contenido (asa y nombre), no sobre el hueco del Spacer.
Offset handle(WidgetTester t, Finder f) => t.getTopLeft(f) + Offset(6, t.getSize(f).height / 2);

void main() {
  testWidgets('listo: golden y arrastre llama a seek y seekEnd', (t) async {
    final r = await pump(t);
    await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('goldens/montage_timeline.png'));
    final g = await t.startGesture(areaPoint(t, 100, 60));
    await g.moveBy(const Offset(30, 0));
    await g.up();
    await settle(t);
    expect(r.methods, contains('montage.seek'));
    expect(r.c.read(montageStoreProvider).snapshot, isNotNull);
  });

  testWidgets('plano unico: golden, clic en hueco anade corte y abre menu; eliminar', (t) async {
    final r = await pump(t, open: 'open.single.result');
    await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('goldens/montage_timeline_single.png'));
    // Carril Plano: tras banda (8) + seccion (24) + 2 separaciones de 6 -> y = 50..80.
    await t.tapAt(areaPoint(t, 20, 65));
    await settle(t);
    expect(r.methods, contains('montage.addCut'));
    await t.tap(find.byKey(const ValueKey('montage-add-cut')));
    await settle(t);
    expect(r.methods.where((m) => m == 'montage.addCut').length, 2);
  });

  testWidgets('clic en marca abre el menu (golden); eliminar llama removeCut', (t) async {
    final r = await pump(t, open: 'open.single.result');
    final snap = r.c.read(montageStoreProvider).snapshot!;
    final w = t.getSize(find.byType(MontageTimelineArea)).width;
    final mark = MontageTimelineGeometry(montageTimelineData(snap), w).cutMarkRect(0).center;
    await t.tapAt(areaPoint(t, mark.dx, mark.dy));
    await settle(t);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('montage-cut-delete')), findsOneWidget);
    expect(find.text('Desde 0:03 manda'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('montage-cut-delete')));
    await settle(t);
    expect(r.methods, contains('montage.removeCut'));
    expect(find.byKey(const ValueKey('montage-cut-delete')), findsNothing);
  });

  testWidgets('arrastrar una marca la pinta en el tiempo de snapCut y al soltar llama a moveCut', (t) async {
    final r = await pump(t, open: 'open.single.result');
    r.core.handle('montage.snapCut', (_) => {'time': 6.5});
    final snap = r.c.read(montageStoreProvider).snapshot!;
    final w = t.getSize(find.byType(MontageTimelineArea)).width;
    final mark = MontageTimelineGeometry(montageTimelineData(snap), w).cutMarkRect(0).center;
    final g = await t.startGesture(areaPoint(t, mark.dx, mark.dy));
    await g.moveBy(const Offset(20, 0));
    await settle(t);
    double painted() => t
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<MontageTimelinePainter>()
        .single
        .data
        .cuts[0]
        .time;
    expect(r.methods, contains('montage.snapCut'));
    expect(painted(), 6.5);
    await g.up();
    await settle(t);
    expect(r.methods, contains('montage.moveCut'));
    expect(painted(), isNot(6.5));
  });

  testWidgets('reordenar carril llama a moveLane; girar llama a rotateTake', (t) async {
    final r = await pump(t, snapshot: twoLanes());
    final lanes = r.c.read(montageStoreProvider).snapshot!.lanes;
    expect(lanes.length, greaterThan(1));
    final from = find.byKey(ValueKey('montage-lane-${lanes[0].id}'));
    final to = find.byKey(ValueKey('montage-lane-${lanes[1].id}'));
    final g = await t.startGesture(handle(t, from));
    await t.pump(const Duration(milliseconds: 50));
    await g.moveBy(const Offset(0, 20));
    await t.pump();
    final target = handle(t, to);
    for (var i = 1; i <= 5; i++) {
      await g.moveTo(Offset.lerp(handle(t, from), target, i / 5)!);
      await t.pump();
    }
    await g.up();
    await t.pump();
    await settle(t);
    expect(r.methods, contains('montage.moveLane'));
    await t.tap(find.byKey(ValueKey('montage-rotate-${lanes[0].takeId}')));
    await settle(t);
    expect(r.methods, contains('montage.rotateTake'));
  });

  testWidgets('el cursor se mueve con la posicion sin reconstruir las etiquetas', (t) async {
    final r = await pump(t);
    final before = t.widget(find.byKey(ValueKey('montage-lane-${r.c.read(montageStoreProvider).snapshot!.lanes[0].id}')));
    r.core.emit('montage.position', fx('position.playing.event'));
    await settle(t);
    final after = t.widget(find.byKey(ValueKey('montage-lane-${r.c.read(montageStoreProvider).snapshot!.lanes[0].id}')));
    expect(identical(before, after), isTrue);
  });
}
