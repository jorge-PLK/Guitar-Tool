import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/features/tab/tab_loop_menu.dart';

import 'transport_support.dart';

Json _params(Rig r, String method) => (r.calls(method).last.params! as Map).cast<String, Object?>();

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('tab_loop_menu')));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('sin bucle: etiqueta «Bucle» y solo «Sin bucle» + secciones', (tester) async {
    await pumpTransport(tester, const TabLoopMenu());
    expect(find.text(es.tab_loop), findsOneWidget);
    await _open(tester);
    expect(find.text(es.tab_loopNone), findsOneWidget);
    expect(find.text(es.tab_loopSelection), findsNothing);
    expect(find.text(es.tab_loopBar(3)), findsNothing);
    expect(find.text('Intro'), findsOneWidget);
    expect(find.text('Solo'), findsOneWidget);
  });

  testWidgets('con bucle con nombre y libre', (tester) async {
    await pumpTransport(tester, const TabLoopMenu(), tweak: (open) {
      (open['transport']! as Map)['loop'] = {'start': 65.0, 'end': 130.0, 'name': 'Intro'};
    });
    expect(find.text(es.tab_loopActive('Intro', '1:05', '2:10')), findsOneWidget);
  });

  testWidgets('bucle sin nombre dice «libre»', (tester) async {
    await pumpTransport(tester, const TabLoopMenu(), tweak: (open) {
      (open['transport']! as Map)['loop'] = {'start': 1.0, 'end': 3.0};
    });
    expect(find.text(es.tab_loopActive(es.tab_loopFree, '0:01', '0:03')), findsOneWidget);
  });

  testWidgets('el bucle del tramo se muestra con el texto de ARB', (tester) async {
    await pumpTransport(tester, const TabLoopMenu(), tweak: (open) {
      (open['transport']! as Map)['loop'] = {'start': 1.0, 'end': 3.0, 'name': 'Selección'};
    });
    expect(find.text(es.tab_loopActive(es.tab_loopSelection, '0:01', '0:03')), findsOneWidget);
  });

  testWidgets('«Sin bucle» limpia tramo y bucle', (tester) async {
    final r = await pumpTransport(tester, const TabLoopMenu());
    await _open(tester);
    await tester.tap(find.text(es.tab_loopNone));
    await tester.pump();
    expect(r.tab.spans, [TabSpanAction.clear]);
    expect(r.tab.keepAnchors, [true]);
    expect(r.calls('study.setLoop'), hasLength(1));
    expect(_params(r, 'study.setLoop').containsKey('start'), isFalse);
  });

  testWidgets('«Selección» solo con tramo y aplica el bucle del tramo', (tester) async {
    final r = await pumpTransport(tester, const TabLoopMenu(),
        tab: tabWith(span: const TabSpanInfo(startTick: 0, endTick: 48)));
    await _open(tester);
    await tester.tap(find.text(es.tab_loopSelection));
    await tester.pump();
    expect(r.tab.spans, [TabSpanAction.apply]);
  });

  testWidgets('«Compás n» solo con compás seleccionado y envía su rango', (tester) async {
    final r = await pumpTransport(tester, const TabLoopMenu(),
        tab: tabWith(
            selection: const TabSelectionInfo(
                track: 't', beat: 0, tick: 0, hasNote: false, barRange: TabBarRange(bar: 2, start: 4.0, end: 6.0))));
    await _open(tester);
    await tester.tap(find.text(es.tab_loopBar(3)));
    await tester.pump();
    final p = _params(r, 'study.setLoop');
    expect([p['start'], p['end'], p['name']], [4.0, 6.0, es.tab_loopBarName(3)]);
  });

  testWidgets('una sección envía setLoop con su nombre', (tester) async {
    final r = await pumpTransport(tester, const TabLoopMenu());
    await _open(tester);
    await tester.tap(find.text('Solo'));
    await tester.pump();
    final p = _params(r, 'study.setLoop');
    expect([p['start'], p['end'], p['name']], [2.0, 4.0, 'Solo']);
  });
}
