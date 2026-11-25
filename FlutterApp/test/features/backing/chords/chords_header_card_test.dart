import 'package:flutter_test/flutter_test.dart';

import 'chords_support.dart';

void overrides(Json o, int n) {
  o['chordOverrides'] = <Object?>[
    for (var i = 0; i < n; i++) <String, Object?>{'start': i * 2.0, 'end': i * 2.0 + 2, 'index': 3},
  ];
}

void main() {
  group('cabecera', () {
    testWidgets('sin bucle ni edición: solo Editar y Expandir', (tester) async {
      await pumpChords(tester, tweak: fourChords);
      expect(find.text(es.backing_editChords), findsOneWidget);
      expect(find.text(es.backing_expand), findsOneWidget);
      expect(find.text(es.backing_markSection), findsNothing);
      expect(find.text(es.backing_apply), findsNothing);
      expect(find.text(es.backing_dragHintWin), findsOneWidget);
    });

    testWidgets('con bucle: marcar sección y solo', (tester) async {
      await pumpChords(tester, tweak: (o) {
        fourChords(o);
        (o['transport']! as Map)['loop'] = <String, Object?>{'start': 0.0, 'end': 2.0};
      });
      expect(find.text(es.backing_markSection), findsOneWidget);
      expect(find.text(es.backing_markSolo), findsOneWidget);
    });

    testWidgets('secciones sin aplicar: Descartar y Aplicar', (tester) async {
      final r = await pumpChords(tester, tweak: (o) {
        fourChords(o);
        o['unappliedSections'] = true;
      });
      expect(find.text(es.backing_discard), findsOneWidget);
      await tester.tap(find.text(es.backing_apply));
      await settleFrames(tester);
      expect(r.methods, contains('study.applySections'));
    });

    testWidgets('edición: «Quitar todas (n)» llama a study.clearChordOverrides', (tester) async {
      final r = await pumpChords(tester, tweak: (o) {
        fourChords(o);
        overrides(o, 2);
        (o['transport']! as Map)['loop'] = <String, Object?>{'start': 0.0, 'end': 2.0};
      });
      expect(find.text(es.backing_clearOverrides(2)), findsNothing);
      await tester.tap(find.text(es.backing_editChords));
      await settleFrames(tester);
      expect(find.text(es.backing_editModeHint), findsOneWidget);
      expect(find.text(es.backing_markSection), findsNothing);
      await tester.tap(find.text(es.backing_clearOverrides(2)));
      await settleFrames(tester);
      expect(r.methods, contains('study.clearChordOverrides'));
    });

    testWidgets('Expandir/Plegar persiste por tema', (tester) async {
      final r = await pumpChords(tester, tweak: fourChords);
      await tester.tap(find.text(es.backing_expand));
      await settleFrames(tester);
      expect(r.prefs.data['00000000-0000-0000-0000-000000000002'], isTrue);
      expect(find.text(es.backing_collapse), findsOneWidget);
      await tester.tap(find.text(es.backing_collapse));
      await settleFrames(tester);
      expect(r.prefs.data['00000000-0000-0000-0000-000000000002'], isFalse);
    });
  });

  group('tarjeta', () {
    testWidgets('sin acorde actual: «—»', (tester) async {
      await pumpChords(tester, tweak: (o) {
        fourChords(o);
        (o['transport']! as Map)['position'] = 20.0;
      });
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('acorde actual, siguiente y capo', (tester) async {
      await pumpChords(tester, tweak: (o) {
        fourChords(o, position: 0.5);
        (o['transport']! as Map)['capo'] = 3;
      });
      expect(find.text(es.backing_nextChord('Cm(maj7)')), findsOneWidget);
      expect(find.text(es.backing_capoShown(3)), findsOneWidget);
      expect(find.text('—'), findsNothing);
    });

    testWidgets('sin capo no hay línea de capo', (tester) async {
      await pumpChords(tester, tweak: fourChords);
      expect(find.text(es.backing_capoShown(0)), findsNothing);
    });
  });
}
