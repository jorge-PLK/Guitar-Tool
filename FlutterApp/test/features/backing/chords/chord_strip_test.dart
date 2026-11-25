import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/backing/widgets/chord_strip.dart';
import 'package:toneforge/theme/tokens.dart';

import 'chords_support.dart';

/// El nombre también sale en la tarjeta del diagrama: solo el de la tira.
Finder inStrip(String name) => find.descendant(of: find.byType(ChordStrip), matching: find.text(name));

BoxDecoration boxOf(WidgetTester t, String name) {
  final chip = find.ancestor(of: inStrip(name), matching: find.byKey(const ValueKey('chord-chip-box')));
  return (t.widget<Container>(chip).decoration! as BoxDecoration);
}

Color? textColor(WidgetTester t, String name) => t.widget<Text>(inStrip(name)).style!.color;

MockCall call(ChordsRig r, String m) => r.core.calls.lastWhere((c) => c.method == m);

void main() {
  testWidgets('estados del chip: actual, en bucle, pasado y futuro', (tester) async {
    await pumpChords(tester, tweak: (o) {
      fourChords(o, position: 2.5);
      (o['transport']! as Map)['loop'] = <String, Object?>{'start': 4.0, 'end': 6.0};
    });
    // Pasado: Cm. Actual: Cm(maj7). En bucle: G. Futuro: Am.
    expect(boxOf(tester, 'Cm(maj7)').color, TfColors.accent);
    expect(textColor(tester, 'Cm(maj7)'), TfColors.accentInk);
    expect(boxOf(tester, 'G').border, isNotNull);
    expect((boxOf(tester, 'G').border! as Border).top.color, TfColors.accent);
    expect(boxOf(tester, 'G').color, isNot(TfColors.field));
    expect(boxOf(tester, 'Am').color, TfColors.field);
    expect(textColor(tester, 'Am'), TfColors.text);
    expect(boxOf(tester, 'Cm').color, TfColors.field);
    expect(textColor(tester, 'Cm'), isNot(TfColors.text));
  });

  testWidgets('el número de compás solo sale en el acorde que abre compás', (tester) async {
    await pumpChords(tester, tweak: fourChords);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsNothing);
  });

  testWidgets('la tira mide 79 de alto', (tester) async {
    await pumpChords(tester, tweak: fourChords);
    expect(tester.getSize(find.byType(ChordStrip)).height, ChordStripLayout.height);
    expect(ChordStripLayout.height, 79);
  });

  testWidgets('clic en un chip salta a su inicio', (tester) async {
    final r = await pumpChords(tester, tweak: fourChords);
    await tester.tap(inStrip('G'));
    await settleFrames(tester);
    expect(r.methods, contains('study.seek'));
    expect((call(r, 'study.seek').params! as Map)['seconds'], 4);
  });

  testWidgets('arrastre entre chips fija el bucle por acordes', (tester) async {
    final r = await pumpChords(tester, tweak: fourChords);
    final g = await tester.startGesture(tester.getCenter(inStrip('Cm')));
    final to = tester.getCenter(inStrip('G'));
    await g.moveTo(Offset(to.dx - 20, to.dy));
    await g.moveTo(to);
    await g.up();
    await settleFrames(tester);
    final p = call(r, 'study.setLoop').params! as Map;
    expect(p['start'], 0);
    expect(p['end'], 6);
    expect(p['snap'], 'chord');
    expect(p['name'], es.backing_loopNameChords);
    expect(es.backing_loopNameChords, 'acordes');
    expect(r.methods, isNot(contains('study.seek')));
  });
}
