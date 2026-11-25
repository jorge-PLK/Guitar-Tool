import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/record_state.dart';
import 'package:toneforge/core/core_client.dart' show Json;
import 'package:toneforge/features/record/record_store.dart';
import 'package:toneforge/features/record/widgets/part_box.dart';
import 'package:toneforge/features/record/widgets/parts_panel.dart';
import 'package:toneforge/features/record/widgets/take_button.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_menu.dart';

import '../../support/harness.dart';

const String _t2 = '00000000-0000-0000-0000-0000000000a2';

Json _fx(String name) =>
    (json.decode(File('../Contract/fixtures/record/record.state.$name.event.json').readAsStringSync()) as Map)
        .cast<String, Object?>();

/// Fixture [name] con una 2.ª toma (no mejor, sin vídeo) en la primera parte.
RecordSnapshot _snap(String name, {String? selected}) {
  final Json j = Map<String, Object?>.of(_fx(name));
  final List<Object?> parts = List<Object?>.of(j['parts']! as List);
  final Json p0 = Map<String, Object?>.of((parts[0]! as Map).cast<String, Object?>());
  final List<Object?> takes = List<Object?>.of(p0['takes']! as List);
  final Json t1 = Map<String, Object?>.of((takes[0]! as Map).cast<String, Object?>());
  takes.add(<String, Object?>{...t1, 'id': _t2, 'number': 2, 'best': false, 'hasVideo': false});
  p0['takes'] = takes;
  parts[0] = p0;
  j['parts'] = parts;
  if (selected != null) j['selectedTakeId'] = selected;
  return RecordSnapshot.fromJson(j);
}

class _FakeStore extends RecordStore {
  _FakeStore(this.initial);
  final RecordState initial;
  final List<String> calls = <String>[];

  @override
  RecordState build() => initial;
  @override
  Future<void> selectPart(String partId) async => calls.add('selectPart:$partId');
  @override
  Future<void> selectTake(String? takeId) async => calls.add('selectTake:$takeId');
  @override
  Future<void> markBest(String takeId) async => calls.add('markBest:$takeId');
  @override
  Future<void> startPunch(String takeId) async => calls.add('startPunch:$takeId');
  @override
  Future<void> deleteTake(String takeId) async => calls.add('deleteTake:$takeId');
}

Future<_FakeStore> _pump(WidgetTester tester, RecordSnapshot s, {List<String>? log}) async {
  await tester.runAsync(loadTfFonts);
  setTestSurface(tester, const Size(400, 700));
  final _FakeStore store = _FakeStore(RecordState(snapshot: s, opened: true));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [recordStoreProvider.overrideWith(() => store)],
      child: tfNavApp(
        Localizations(
          locale: const Locale('es'),
          delegates: const <LocalizationsDelegate<dynamic>>[AppLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
          child: DefaultTextStyle(
            style: TfText.body().copyWith(color: TfColors.text),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 320,
                child: SingleChildScrollView(
                  child: PartsPanel(
                    onViewTake: (String id) => log?.add('view:$id'),
                    onAddPart: () => log?.add('add'),
                    onAdjustOffset: (String id) => log?.add('offset:$id'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return store;
}

BoxDecoration _boxOf(WidgetTester tester, Finder f) =>
    (tester.widget<Container>(find.ancestor(of: f, matching: find.byType(Container)).first)).decoration! as BoxDecoration;

Finder _chevron(int take) =>
    find.descendant(of: find.byType(TakeButton).at(take), matching: find.byType(TfIconView)).first;

Finder _play(int take) =>
    find.descendant(of: find.byType(TakeButton).at(take), matching: find.byType(TfIconView)).last;

void main() {
  testWidgets('parte activa en accentBg/accent, la otra en field', (tester) async {
    final _FakeStore s = await _pump(tester, _snap('idle'));
    final Finder boxes = find.byType(PartBox);
    expect(boxes, findsNWidgets(2));
    BoxDecoration d(int i) => tester
        .widget<Container>(find.descendant(of: boxes.at(i), matching: find.byType(Container)).first)
        .decoration! as BoxDecoration;
    expect(d(0).color, TfColors.accentBg);
    expect((d(0).border! as Border).top.color, TfColors.accent);
    expect(d(1).color, TfColors.field);
    expect(find.text('Hecha'), findsOneWidget);
    expect(find.text('Pendiente'), findsOneWidget);
    await tester.tap(boxes.at(1));
    expect(s.calls, ['selectPart:${_snap('idle').parts[1].id}']);
    await tester.tap(boxes.at(0));
    expect(s.calls.length, 1, reason: 'la parte activa no vuelve a elegirse');
  });

  testWidgets('toma mejor, seleccionada y ambas', (tester) async {
    final RecordSnapshot snap = _snap('take-best-selected');
    final _FakeStore s = await _pump(tester, snap);
    final String best = snap.parts[0].takes[0].id;
    expect(find.text('Toma 1 · mejor'), findsOneWidget);
    BoxDecoration d(String label) => _boxOf(tester, find.text(label));
    // Mejor y seleccionada: gana la selección en fondo y borde.
    expect(d('Toma 1 · mejor').color, TfColors.accentBg);
    expect((d('Toma 1 · mejor').border! as Border).top.width, TfStroke.thick);
    expect(tester.widget<Text>(find.text('Toma 1 · mejor')).style!.color, TfColors.ok);
    // Reposo.
    expect(d('Toma 2').color, TfColors.sidebar);
    await tester.tap(find.text('Toma 2'));
    expect(s.calls, ['selectTake:$_t2']);
    expect(best, isNot(_t2));
  });

  testWidgets('solo mejor: okBg y okBorder', (tester) async {
    await _pump(tester, _snap('idle'));
    final BoxDecoration d = _boxOf(tester, find.text('Toma 1 · mejor'));
    expect(d.color, TfColors.okBg);
    expect((d.border! as Border).top.color, TfColors.okBorder);
  });

  testWidgets('menú: marcar como mejor, punch-in y desfase llaman al store o al padre', (tester) async {
    final List<String> log = <String>[];
    final _FakeStore s = await _pump(tester, _snap('idle'), log: log);
    expect(find.byType(TfMenuPanel), findsNothing);
    await tester.tap(_chevron(1));
    await tester.pump();
    await tester.tap(find.text('Marcar como mejor'));
    await tester.pump();
    expect(s.calls, ['markBest:$_t2']);

    await tester.tap(_chevron(1));
    await tester.pump();
    await tester.tap(find.text('Punch-in').last);
    await tester.pump();
    expect(s.calls.last, 'startPunch:$_t2');

    // La toma 1 es la mejor: «Marcar como mejor» inactivo; la 1 tiene vídeo: desfase activo.
    await tester.tap(_chevron(0));
    await tester.pump();
    await tester.tap(find.text('Marcar como mejor'));
    await tester.pump();
    expect(s.calls.where((c) => c.startsWith('markBest')).length, 1);
    await tester.tap(find.text('Ajustar desfase…'));
    await tester.pump();
    expect(log.single, startsWith('offset:'));
  });

  testWidgets('borrar pide confirmación; cancelar no borra, confirmar sí', (tester) async {
    final _FakeStore s = await _pump(tester, _snap('idle'));
    Future<void> openDelete() async {
      await tester.tap(_chevron(1));
      await tester.pump();
      await tester.tap(find.text('Borrar…'));
      await tester.pump(const Duration(milliseconds: 300));
    }

    await openDelete();
    expect(find.text('¿Borrar la toma?'), findsOneWidget);
    expect(s.calls, isEmpty);
    await tester.tap(find.text('Cancelar'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(s.calls, isEmpty);

    await openDelete();
    await tester.tap(find.text('Borrar toma'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(s.calls, ['deleteTake:$_t2']);
  });

  testWidgets('callbacks: ▶ abre el visor y «Añadir parte» la hoja', (tester) async {
    final List<String> log = <String>[];
    final RecordSnapshot snap = _snap('idle');
    await _pump(tester, snap, log: log);
    await tester.tap(_play(0));
    expect(log, ['view:${snap.parts[0].takes[0].id}']);
    await tester.tap(find.text('Añadir parte'));
    expect(log.last, 'add');
  });

  testWidgets('cuenta atrás: la parte activa (con tomas) muestra «Grabando», no «Hecha»', (tester) async {
    await _pump(tester, _snap('counting'));
    expect(find.text('Grabando'), findsOneWidget);
    expect(find.text('Hecha'), findsNothing);
  });

  testWidgets('ajustando: vuelve «Hecha»', (tester) async {
    await _pump(tester, _snap('adjusting'));
    expect(find.text('Grabando'), findsNothing);
  });

  testWidgets('grabando: todo deshabilitado y solo la activa muestra «Grabando»', (tester) async {
    final List<String> log = <String>[];
    final _FakeStore s = await _pump(tester, _snap('recording'), log: log);
    expect(find.text('Grabando'), findsOneWidget);
    expect(find.text('Hecha'), findsNothing);
    expect(find.text('Pendiente'), findsOneWidget);
    await tester.tap(find.byType(PartBox).at(1));
    await tester.tap(find.text('Toma 2'));
    await tester.tap(_chevron(1));
    await tester.pump();
    await tester.tap(_play(0));
    await tester.tap(find.text('Añadir parte'));
    expect(find.byType(TfMenuPanel), findsNothing);
    expect(s.calls, isEmpty);
    expect(log, isEmpty);
  });

  testWidgets('status `recording` del núcleo pinta «Grabando» aunque la fase no lo implique (RV:236)', (tester) async {
    final Json j = Map<String, Object?>.of(_fx('idle'));
    final List<Object?> parts = List<Object?>.of(j['parts']! as List);
    parts[0] = <String, Object?>{...(parts[0]! as Map).cast<String, Object?>(), 'status': 'recording'};
    j['parts'] = parts;
    await _pump(tester, RecordSnapshot.fromJson(j));
    expect(find.text('Grabando'), findsOneWidget);
    expect(find.text('Hecha'), findsNothing);
  });

  testWidgets('«Sustituye: …» sale de `replaces` (RV:218); sin él, «Parte añadida»', (tester) async {
    final Json j = Map<String, Object?>.of(_fx('idle'));
    final List<Object?> parts = List<Object?>.of(j['parts']! as List);
    final Json p0 = (parts[0]! as Map).cast<String, Object?>();
    final String name = ((j['guitarRoles']! as List).first as Map)['name']! as String;
    final String role = ((j['guitarRoles']! as List).first as Map)['role']! as String;
    parts[0] = <String, Object?>{...p0, 'isLead': false, 'replaces': role};
    j['parts'] = parts;
    await _pump(tester, RecordSnapshot.fromJson(j));
    expect(find.text('Sustituye: $name'), findsOneWidget);
  });

  testWidgets('sin `replaces` la parte dice «Parte añadida»', (tester) async {
    final Json j = Map<String, Object?>.of(_fx('idle'));
    final List<Object?> parts = List<Object?>.of(j['parts']! as List);
    final Json p0 = (parts[0]! as Map).cast<String, Object?>();
    parts[0] = <String, Object?>{...p0, 'isLead': true}..remove('replaces');
    j['parts'] = parts;
    await _pump(tester, RecordSnapshot.fromJson(j));
    expect(find.text('Parte añadida'), findsWidgets);
    expect(find.textContaining('Sustituye'), findsNothing);
  });
}
