import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/chord_chip.dart';
import 'package:toneforge/features/backing/widgets/chord_editor.dart';

import 'chords_support.dart';

/// Cuatro acordes de 2 s con pulsos cada 1 s; el segundo (2...4, índice 7 = Cm(maj7)) tiene corrección.
void tweak(Json open, {double position = 3, bool override = true}) {
  fourChords(open, position: position);
  final a = (open['analysis']! as Map).cast<String, Object?>();
  a['beats'] = <Object?>[for (int i = 0; i < 8; i++) i.toDouble()];
  open['chordOverrides'] = override
      ? <Object?>[
          <String, Object?>{'start': 2.0, 'end': 4.0, 'index': 7},
        ]
      : <Object?>[];
}

Finder inEditor(Finder f) => find.descendant(of: find.byType(ChordEditor), matching: f);
Map last(ChordsRig r, String m) => r.core.calls.lastWhere((x) => x.method == m).params! as Map;
int count(ChordsRig r, String m) => r.core.calls.where((x) => x.method == m).length;

Future<ChordsRig> pumpEditing(WidgetTester t, {double position = 3, bool override = true}) async {
  final ChordsRig rig = await pumpChords(
    t,
    size: const Size(1100, 900),
    tweak: (o) => tweak(o, position: position, override: override),
  );
  rig.container.read(studyStoreProvider.notifier).setEditMode(true);
  await settleFrames(t);
  await t.tap(find.byType(ChordChip).at(1));
  await settleFrames(t);
  return rig;
}

void main() {
  testWidgets('la hoja solo se abre en modo edición', (t) async {
    final ChordsRig rig = await pumpChords(t, tweak: tweak);
    await t.tap(find.byType(ChordChip).at(1));
    await settleFrames(t);
    expect(find.byType(ChordEditor), findsNothing);
    rig.container.read(studyStoreProvider.notifier).setEditMode(true);
    await settleFrames(t);
    await t.tap(find.byType(ChordChip).at(1));
    await settleFrames(t);
    expect(find.byType(ChordEditor), findsOneWidget);
    expect(inEditor(find.text(es.backing_chordSheetTitle)), findsOneWidget);
    expect(inEditor(find.text(es.backing_chordMajor)), findsOneWidget);
    rig.container.read(studyStoreProvider.notifier).setEditMode(false);
    await settleFrames(t);
    expect(find.byType(ChordEditor), findsNothing);
  });

  testWidgets('raíz y calidad escriben el índice y la hoja sigue abierta', (t) async {
    final ChordsRig rig = await pumpEditing(t);
    await t.tap(inEditor(find.text('D')));
    await settleFrames(t);
    expect(last(rig, 'study.setChord'), containsPair('index', 2 * 14 + 7));
    await t.tap(inEditor(find.text('maj7')));
    await settleFrames(t);
    final Map p = last(rig, 'study.setChord');
    expect(p, containsPair('index', 2 * 14 + 8));
    expect(p, containsPair('start', 2.0));
    expect(p, containsPair('end', 4.0));
    expect(find.byType(ChordEditor), findsOneWidget);
  });

  testWidgets('N escribe sin acorde', (t) async {
    final ChordsRig rig = await pumpEditing(t);
    await t.tap(inEditor(find.text(es.backing_chordNone)));
    await settleFrames(t);
    expect(last(rig, 'study.setChord'), containsPair('index', 169));
    expect(find.byType(ChordEditor), findsOneWidget);
  });

  testWidgets('partir en el pulso más cercano al cursor', (t) async {
    final ChordsRig rig = await pumpEditing(t, position: 3.2);
    await t.tap(inEditor(find.text(es.backing_chordSplit)));
    await settleFrames(t);
    expect(last(rig, 'study.splitChord'), containsPair('at', 3.0));
  });

  testWidgets('partir deshabilitado fuera del tramo o pegado a un extremo', (t) async {
    final ChordsRig out = await pumpEditing(t, position: 0.5);
    await t.tap(inEditor(find.text(es.backing_chordSplit)));
    await settleFrames(t);
    expect(count(out, 'study.splitChord'), 0);
  });

  testWidgets('partir deshabilitado si el pulso cae en un extremo', (t) async {
    final ChordsRig rig = await pumpEditing(t, position: 2.4);
    await t.tap(inEditor(find.text(es.backing_chordSplit)));
    await settleFrames(t);
    expect(count(rig, 'study.splitChord'), 0);
  });

  testWidgets('quitar corrección con overrides que solapan', (t) async {
    final ChordsRig rig = await pumpEditing(t);
    await t.tap(inEditor(find.text(es.backing_chordRemoveOverride)));
    await settleFrames(t);
    final Map p = last(rig, 'study.removeChordOverrides');
    expect(p, containsPair('start', 2.0));
    expect(p, containsPair('end', 4.0));
  });

  testWidgets('quitar corrección deshabilitado sin overrides', (t) async {
    final ChordsRig rig = await pumpEditing(t, override: false);
    await t.tap(inEditor(find.text(es.backing_chordRemoveOverride)));
    await settleFrames(t);
    expect(count(rig, 'study.removeChordOverrides'), 0);
  });
}
