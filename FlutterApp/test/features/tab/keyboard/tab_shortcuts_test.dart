import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/tab/tab_shortcuts.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/tokens.dart';

import '../../../support/harness.dart';
import '../tab_test_support.dart';

late MockCore core;
final FocusNode _fieldFocus = FocusNode();
final TextEditingController _fieldText = TextEditingController();
late String _platform;

Future<void> _boot(
  WidgetTester tester, {
  bool editMode = true,
  Map<String, Object?> extra = const {},
  TargetPlatform platform = TargetPlatform.macOS,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  _platform = platform == TargetPlatform.macOS ? 'macos' : 'windows';
  setTestSurface(tester, const Size(600, 400));
  core = (await tester.runAsync(loadCore))!;
  final c = makeContainer(core);
  c.listen(tabStoreProvider, (_, _) {});
  c.read(selectedProjectProvider.notifier).select(projectId);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Actions(
          actions: {DismissIntent: DoNothingAction()},
          child: TabShortcuts(
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
      ),
    ),
  );
  await tester.runAsync(settle);
  core.emit('tab.state', {...fixture('tab.open.result.json'), 'editMode': editMode, ...extra});
  await tester.runAsync(settle);
  await tester.pump();
}

List<String> get _methods => [for (final m in core.calls) m.method];

List<Map<Object?, Object?>> get _edits => [
  for (final m in core.calls)
    if (m.method == 'tab.edit') (m.params! as Map).cast<Object?, Object?>(),
];

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey k, {
  String? ch,
  List<LogicalKeyboardKey> mods = const [],
}) async {
  for (final m in mods) {
    await tester.sendKeyDownEvent(m, platform: _platform);
  }
  await tester.sendKeyEvent(k, character: ch, platform: _platform);
  for (final m in mods.reversed) {
    await tester.sendKeyUpEvent(m, platform: _platform);
  }
  await tester.runAsync(settle);
  await tester.pump();
}

void main() {
  setUpAll(findFixtures);
  setUp(_fieldText.clear);

  testWidgets('flechas, Retroceso, Supr, cifras y letras mandan key en edición', (tester) async {
    await _boot(tester);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.arrowLeft, mods: [LogicalKeyboardKey.shiftLeft]);
    await _press(tester, LogicalKeyboardKey.backspace);
    await _press(tester, LogicalKeyboardKey.delete);
    await _press(tester, LogicalKeyboardKey.digit5, ch: '5');
    await _press(tester, LogicalKeyboardKey.keyP, ch: 'p');
    await _press(tester, LogicalKeyboardKey.keyD, ch: 'D', mods: [LogicalKeyboardKey.shiftLeft]);
    await _press(tester, LogicalKeyboardKey.semicolon, ch: ';');
    final keys = [for (final e in _edits) e['key']];
    expect(keys, ['ArrowUp', 'ArrowLeft', 'Backspace', 'Delete', '5', 'p', 'D', ';']);
    expect(_edits.every((e) => e['op'] == 'key'), isTrue);
    expect(_edits[1]['shift'], isTrue);
    expect(_edits[0].containsKey('ctrl') && _edits[0]['ctrl'] == true, isFalse);
  });

  testWidgets('en lectura no se manda nada', (tester) async {
    await _boot(tester, editMode: false);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.digit5, ch: '5');
    await _press(tester, LogicalKeyboardKey.keyP, ch: 'p');
    await _press(tester, LogicalKeyboardKey.escape);
    expect(_methods, isNot(contains('tab.edit')));
  });

  testWidgets('Esc con tramo en lectura manda key Escape', (tester) async {
    await _boot(
      tester,
      editMode: false,
      extra: {
        'span': {'startTick': 0, 'endTick': 960},
      },
    );
    await _press(tester, LogicalKeyboardKey.escape);
    expect(_edits.single['op'], 'key');
    expect(_edits.single['key'], 'Escape');
  });

  testWidgets('Esc en edición sin tramo también va por key', (tester) async {
    await _boot(tester);
    await _press(tester, LogicalKeyboardKey.escape);
    expect(_edits.single['key'], 'Escape');
  });

  testWidgets('macOS: ⌘Z y ⇧⌘Z mandan ctrl=true; Ctrl+Y no hace nada', (tester) async {
    await _boot(tester);
    await _press(tester, LogicalKeyboardKey.keyZ, ch: 'z', mods: [LogicalKeyboardKey.metaLeft]);
    await _press(
      tester,
      LogicalKeyboardKey.keyZ,
      ch: 'Z',
      mods: [LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.shiftLeft],
    );
    expect(_edits.length, 2);
    expect(_edits[0]['ctrl'], isTrue);
    expect(_edits[0]['shift'], isNot(true));
    expect(_edits[1]['ctrl'], isTrue);
    expect(_edits[1]['shift'], isTrue);
    await _press(tester, LogicalKeyboardKey.keyY, ch: 'y', mods: [LogicalKeyboardKey.controlLeft]);
    await _press(tester, LogicalKeyboardKey.keyY, ch: 'y', mods: [LogicalKeyboardKey.metaLeft]);
    expect(_edits.length, 2);
  });

  testWidgets('⌥Y manda key y con alt; ⌘A no se manda', (tester) async {
    await _boot(tester);
    await _press(tester, LogicalKeyboardKey.keyY, ch: '¥', mods: [LogicalKeyboardKey.altLeft]);
    expect(_edits.single['key'], 'y');
    expect(_edits.single['alt'], isTrue);
    await _press(tester, LogicalKeyboardKey.keyA, ch: 'a', mods: [LogicalKeyboardKey.metaLeft]);
    expect(_edits.length, 1);
  });

  testWidgets('Windows: Ctrl+Z manda ctrl, Ctrl+Y manda redo directo', (tester) async {
    await _boot(tester, platform: TargetPlatform.windows);
    await _press(tester, LogicalKeyboardKey.keyZ, ch: 'z', mods: [LogicalKeyboardKey.controlLeft]);
    expect(_edits.single['op'], 'key');
    expect(_edits.single['ctrl'], isTrue);
    await _press(tester, LogicalKeyboardKey.keyY, ch: 'y', mods: [LogicalKeyboardKey.controlLeft]);
    expect(_edits.last['op'], 'redo');
    expect(_edits.length, 2);
  });

  testWidgets('Espacio alterna play/pause sin repetir ni con modificadores', (tester) async {
    await _boot(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space, platform: _platform);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space, platform: _platform);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space, platform: _platform);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space, platform: _platform);
    await tester.runAsync(settle);
    expect(_methods.where((m) => m == 'study.play').length, 1);
    expect(_methods, isNot(contains('tab.edit')));
    core.emit('study.position', {'seconds': 1.0, 'playing': true});
    await tester.runAsync(settle);
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.space);
    expect(_methods, contains('study.pause'));
    final before = core.calls.length;
    await _press(tester, LogicalKeyboardKey.space, mods: [LogicalKeyboardKey.shiftLeft]);
    await _press(tester, LogicalKeyboardKey.space, mods: [LogicalKeyboardKey.metaLeft]);
    expect(core.calls.length, before);
  });

  testWidgets('Espacio funciona también en lectura', (tester) async {
    await _boot(tester, editMode: false);
    await _press(tester, LogicalKeyboardKey.space);
    expect(_methods, contains('study.play'));
  });

  testWidgets('con un campo de texto enfocado no se manda nada', (tester) async {
    await _boot(tester);
    _fieldFocus.requestFocus();
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.digit5, ch: '5');
    await _press(tester, LogicalKeyboardKey.space);
    await _press(tester, LogicalKeyboardKey.escape);
    expect(_methods, isNot(contains('tab.edit')));
    expect(_methods, isNot(contains('study.play')));
  });

  testWidgets('con la hoja de Songsterr abierta no se manda nada', (tester) async {
    await _boot(tester);
    core.emit('tab.songsterr.state', fixture('tab.songsterr.state.event.json'));
    await tester.runAsync(settle);
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.space);
    expect(_methods, isNot(contains('tab.edit')));
    expect(_methods, isNot(contains('study.play')));
  });

  testWidgets('teclas no conocidas se ignoran (Tab, Intro, F1, Ctrl+letra)', (tester) async {
    await _boot(tester);
    for (final k in [LogicalKeyboardKey.tab, LogicalKeyboardKey.enter, LogicalKeyboardKey.f1]) {
      await _press(tester, k, ch: k == LogicalKeyboardKey.tab ? '\t' : null);
    }
    await _press(tester, LogicalKeyboardKey.keyA, ch: 'a', mods: [LogicalKeyboardKey.controlLeft]);
    expect(_methods, isNot(contains('tab.edit')));
  });
}
