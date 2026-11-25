import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/features/tab/songsterr_choosing.dart';
import 'package:toneforge/features/tab/songsterr_preview.dart';
import 'package:toneforge/features/tab/songsterr_sheet.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_web_view.dart';

import '../../../support/fake_web_view.dart';
import '../../../support/harness.dart';
import '../tab_test_support.dart';
import 'songsterr_sheet_test.dart' show Rig, boot;

const _slot = ValueKey<String>('songsterr-preview-slot');
const _fixture = 'tab.songsterr.state.result.results.json';
const _url7 = 'https://www.songsterr.com/a/wsa/song-tab-s7';

Finder _secondary(String label) => find.widgetWithText(TfSecondaryButton, label);
Finder _primaryIn(Finder scope) =>
    find.descendant(of: scope, matching: find.byType(TfPrimaryButton));

List<String> _loads(FakeWebViewFactory f) =>
    [for (final c in f.created) ...c.calls.where((e) => e.startsWith('loadUrl:'))];

Future<void> _emit(WidgetTester tester, Rig rig, Map<String, Object?> patch) async {
  rig.core.emit('tab.songsterr.state', {...fixture(_fixture), ...patch});
  await tester.runAsync(settle);
  await tester.pump();
}

Future<Rig> _open(WidgetTester tester, FakeWebViewFactory web,
    {Size size = const Size(1500, 800)}) async {
  final rig = await boot(tester, size: size, web: web);
  await tester.tap(_secondary('Vista previa'));
  await tester.pump();
  return rig;
}

void main() {
  setUpAll(() async {
    await loadTfFonts();
    await findFixtures();
  });

  testWidgets('aparece al abrir la vista previa y carga la URL de la canción marcada',
      (tester) async {
    final web = FakeWebViewFactory();
    await boot(tester, web: web);
    expect(find.byType(SongsterrPreview), findsNothing);
    expect(web.created, isEmpty);
    await tester.tap(_secondary('Vista previa'));
    await tester.pump();
    expect(find.byType(SongsterrPreview), findsOneWidget);
    expect(find.text('Vista previa'), findsOneWidget);
    expect(find.byType(TfWebView), findsOneWidget);
    expect(_loads(web), ['loadUrl:$_url7']);
    expect(web.created.single.config.userAgent, songsterrPreviewUserAgent);
  });

  testWidgets('no recarga si la URL no cambia y sí si cambia', (tester) async {
    final web = FakeWebViewFactory();
    final rig = await _open(tester, web);
    await _emit(tester, rig, {});
    expect(_loads(web), ['loadUrl:$_url7']);
    final selected = Map<String, Object?>.from(fixture(_fixture)['selected'] as Map);
    await _emit(tester, rig, {
      'selected': {...selected, 'previewUrl': 'https://www.songsterr.com/a/wsa/otra-tab-s9'},
    });
    expect(_loads(web), ['loadUrl:$_url7', 'loadUrl:https://www.songsterr.com/a/wsa/otra-tab-s9']);
    expect(web.created, hasLength(1));
  });

  testWidgets('Cerrar quita el panel y libera el WebView', (tester) async {
    final web = FakeWebViewFactory();
    await _open(tester, web);
    await tester.tap(_secondary('Cerrar'));
    await tester.pump();
    expect(find.byType(SongsterrPreview), findsNothing);
    expect(find.byKey(_slot), findsNothing);
    expect(web.created.single.calls, contains('dispose'));
  });

  testWidgets('Usar esta del panel llama a use', (tester) async {
    final web = FakeWebViewFactory();
    final rig = await _open(tester, web);
    final button = _primaryIn(find.byType(SongsterrPreview));
    expect(tester.widget<TfPrimaryButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.runAsync(settle);
    expect(rig.methods, contains('tab.songsterr.use'));
  });

  testWidgets('sin canción elegida Usar esta está deshabilitado y no carga', (tester) async {
    final web = FakeWebViewFactory();
    await boot(
      tester,
      web: web,
      child: SizedBox(
        width: 640,
        height: 400,
        child: SongsterrPreview(selected: null, onClose: () {}),
      ),
    );
    expect(tester.widget<TfPrimaryButton>(find.byType(TfPrimaryButton)).onPressed, isNull);
    expect(_loads(web), isEmpty);
  });

  testWidgets('desaparece en working y en pairing', (tester) async {
    final web = FakeWebViewFactory();
    final rig = await _open(tester, web);
    await _emit(tester, rig, {'stage': 'working', 'workingText': 'x'});
    expect(find.byType(SongsterrPreview), findsNothing);
    await _emit(tester, rig, {});
    expect(find.byType(SongsterrPreview), findsOneWidget);
    await _emit(tester, rig, fixture('tab.songsterr.state.result.pairing.json'));
    expect(find.byType(SongsterrPreview), findsNothing);
  });

  testWidgets('ancho de la hoja a 1440 (1320) y a 1100', (tester) async {
    final web = FakeWebViewFactory();
    await _open(tester, web, size: const Size(1440, 800));
    expect(tester.getSize(find.byType(SongsterrSheet)).width, 1320);
    expect(tester.getSize(find.byType(SongsterrChoosing)).width, 612);
    expect(tester.getSize(find.byType(SongsterrPreview)).width, 640);
  });

  testWidgets('a 1100 la lista conserva 612 y la vista previa ocupa el resto', (tester) async {
    final web = FakeWebViewFactory();
    await _open(tester, web, size: const Size(1100, 800));
    final w = tester.getSize(find.byType(SongsterrSheet)).width;
    expect(w, songsterrSheetWidth(1100, preview: true));
    expect(tester.getSize(find.byType(SongsterrChoosing)).width, 612);
    expect(tester.getSize(find.byType(SongsterrPreview)).width, w - 48 - 612 - 20);
  });
}
