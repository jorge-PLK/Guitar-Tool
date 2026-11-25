import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/backing/backing_shortcuts.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/section_selection.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/tokens.dart';

import '../../../support/harness.dart';

const String _id = '00000000-0000-0000-0000-000000000005';

late MockCore core;
late ProviderContainer container;
final FocusNode _fieldFocus = FocusNode();
final TextEditingController _fieldText = TextEditingController();

Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<void> _pump(WidgetTester tester) async {
  final src = (await tester.runAsync(() => DirectoryFixtureSource.find()))!;
  core = (await tester.runAsync(() => MockCore.load(src)))!;
  final path = (await tester.runAsync(
      () async => (await src.list()).firstWhere((p) => p.endsWith('study.open.result.json'))))!;
  final open = (json.decode((await tester.runAsync(() => src.read(path)))!) as Map).cast<String, Object?>();
  core.result('study.open', open);
  for (final String m in <String>['study.play', 'study.pause']) {
    core.result(m, open['transport']);
  }
  setTestSurface(tester, const Size(600, 400));
  container = ProviderContainer(overrides: [
    coreClientProvider.overrideWithValue(core),
    launchOptionsProvider.overrideWithValue(const LaunchOptions()),
  ]);
  addTearDown(container.dispose);
  container.read(selectedProjectProvider.notifier).select(_id);
  container.read(studyStoreProvider);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: BackingShortcuts(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            child: EditableText(
              controller: _fieldText,
              focusNode: _fieldFocus,
              style: const TextStyle(color: TfColors.text),
              cursorColor: TfColors.accent,
              backgroundCursorColor: TfColors.muted,
            ),
          ),
        ),
      ),
    ),
  ));
  await _settle(tester);
}

List<String> get _methods => <String>[for (final m in core.calls) m.method];

Future<void> _emitPlaying(WidgetTester tester, bool playing) async {
  core.emit('study.position', <String, Object?>{'seconds': 1.0, 'playing': playing});
  await _settle(tester);
}

Future<void> _space(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.space);
  await _settle(tester);
}

void main() {
  setUp(_fieldText.clear);

  testWidgets('Espacio reproduce y, sonando, pausa', (tester) async {
    await _pump(tester);
    await _space(tester);
    expect(_methods, contains('study.play'));
    expect(_methods, isNot(contains('study.pause')));
    await _emitPlaying(tester, true);
    await _space(tester);
    expect(_methods, contains('study.pause'));
  });

  testWidgets('Espacio con modificador no dispara', (tester) async {
    await _pump(tester);
    for (final LogicalKeyboardKey mod in <LogicalKeyboardKey>[
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.metaLeft,
    ]) {
      await tester.sendKeyDownEvent(mod);
      await _space(tester);
      await tester.sendKeyUpEvent(mod);
    }
    expect(_methods, isNot(contains('study.play')));
  });

  testWidgets('la auto-repetición se ignora', (tester) async {
    await _pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await _settle(tester);
    expect(_methods.where((m) => m == 'study.play').length, 1);
  });

  const String section = '00000000-0000-0000-0000-000000000003';

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await _settle(tester);
  }

  testWidgets('Supr y Retroceso borran la sección seleccionada y la deseleccionan', (tester) async {
    for (final LogicalKeyboardKey k in <LogicalKeyboardKey>[
      LogicalKeyboardKey.delete,
      LogicalKeyboardKey.backspace,
    ]) {
      await _pump(tester);
      container.read(sectionSelectionProvider.notifier).select(section);
      await key(tester, k);
      final calls = core.calls.where((c) => c.method == 'study.deleteSection').toList();
      expect(calls.length, 1);
      expect((calls.single.params! as Map)['id'], section);
      expect(container.read(sectionSelectionProvider), isNull);
    }
  });

  testWidgets('Esc deselecciona sin borrar', (tester) async {
    await _pump(tester);
    container.read(sectionSelectionProvider.notifier).select(section);
    await key(tester, LogicalKeyboardKey.escape);
    expect(container.read(sectionSelectionProvider), isNull);
    expect(_methods, isNot(contains('study.deleteSection')));
  });

  testWidgets('sin selección, Supr y Esc no hacen nada', (tester) async {
    await _pump(tester);
    await key(tester, LogicalKeyboardKey.delete);
    await key(tester, LogicalKeyboardKey.escape);
    expect(_methods, isNot(contains('study.deleteSection')));
  });

  testWidgets('Supr y Esc no actúan con el foco en un campo de texto', (tester) async {
    await _pump(tester);
    container.read(sectionSelectionProvider.notifier).select(section);
    _fieldFocus.requestFocus();
    await _settle(tester);
    await key(tester, LogicalKeyboardKey.delete);
    await key(tester, LogicalKeyboardKey.escape);
    expect(_methods, isNot(contains('study.deleteSection')));
    expect(container.read(sectionSelectionProvider), section);
  });

  testWidgets('no se dispara con el foco en un campo de texto', (tester) async {
    await _pump(tester);
    _fieldFocus.requestFocus();
    await _settle(tester);
    expect(primaryFocusIsTextInput(), isTrue);
    await _space(tester);
    expect(_methods, isNot(contains('study.play')));
    expect(_methods, isNot(contains('study.pause')));
  });
}
