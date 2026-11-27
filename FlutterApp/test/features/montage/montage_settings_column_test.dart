import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart' show Json;
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/montage/montage_settings_column.dart';
import 'package:toneforge/features/montage/montage_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_checkbox.dart';

import '../../support/harness.dart';

const String _pid = '00000000-0000-0000-0000-000000000003';
const Key _root = ValueKey<String>('root');

Json fx(String name) =>
    (json.decode(File('../Contract/fixtures/montage/montage.$name.json').readAsStringSync()) as Map).cast<String, Object?>();

/// Snapshot con los códecs ofrecidos sustituidos.
Json withCodecs(Json s, List<String> codecs) {
  final Json ex = (s['export'] as Map).cast<String, Object?>();
  final Json opts = (ex['options'] as Map).cast<String, Object?>();
  return {
    ...s,
    'export': {
      ...ex,
      'options': {...opts, 'codecs': codecs},
    },
  };
}

Future<MockCore> pump(WidgetTester t, {String open = 'open.result', Json? snapshot}) async {
  await t.runAsync(loadTfFonts);
  setTestSurface(t, const Size(520, 700));
  final MockCore core = MockCore()
    ..result('montage.open', snapshot ?? fx(open))
    ..result('montage.close', <String, Object?>{});
  for (final String m in <String>[
    'setExport',
    'setCaption',
    'setShowPartLabels',
    'setKeepVideoAspect',
    'setCutGaps',
  ]) {
    core.result('montage.$m', snapshot ?? fx(open));
  }
  final ProviderContainer c = ProviderContainer(overrides: [coreClientProvider.overrideWithValue(core)]);
  addTearDown(c.dispose);
  await c.read(montageStoreProvider.notifier).open(_pid);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: RepaintBoundary(
      key: _root,
      child: WidgetsApp(
        color: TfColors.bg,
        debugShowCheckedModeBanner: false,
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) =>
            PageRouteBuilder<T>(settings: s, pageBuilder: (c, a, b2) => b(c)),
        home: DefaultTextStyle(
          style: TfText.body().copyWith(color: TfColors.text),
          child: const ColoredBox(
            color: TfColors.bg,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Align(alignment: Alignment.topLeft, child: SizedBox(width: 380, child: MontageSettingsColumn())),
            ),
          ),
        ),
      ),
    ),
  ));
  await t.pump();
  return core;
}

Finder key(String k) => find.byKey(ValueKey<String>(k));
bool enabled(WidgetTester t, String k) => t.widget<TfCheckbox>(key(k)).onChanged != null;
List<String> methods(MockCore c) => <String>[for (final MockCall m in c.calls) m.method];

const List<String> _boxes = <String>[
  'montage-normalize',
  'montage-limiter',
  'montage-caption',
  'montage-part-names',
  'montage-keep-aspect',
  'montage-cut-gaps',
  'montage-track-wavs',
];

void main() {
  testWidgets('estado por defecto: filas, Formato visible con 2 códecs (golden)', (t) async {
    await pump(t);
    expect(find.text('Exportación'), findsOneWidget);
    expect(find.text('Formato'), findsOneWidget);
    expect(find.text('Contenedor'), findsOneWidget);
    expect(find.text('Resolución'), findsOneWidget);
    expect(find.text('Fotogramas'), findsOneWidget);
    expect(find.text('HEVC'), findsWidgets);
    expect(find.text('MOV'), findsWidgets);
    expect(find.text('1080p'), findsWidgets);
    expect(find.text('30 fps'), findsWidgets);
    expect(find.text('Volumen normalizado a -14 LUFS'), findsOneWidget);
    await expectLater(find.byKey(_root), matchesGoldenFile('goldens/montage_settings_column.png'));
  });

  testWidgets('fila Formato oculta con un solo códec', (t) async {
    await pump(t, snapshot: withCodecs(fx('open.result'), ['h264']));
    expect(find.text('Formato'), findsNothing);
    expect(key('montage-codec'), findsNothing);
    expect(find.text('Contenedor'), findsOneWidget);
  });

  testWidgets('mantener aspecto: deshabilitada en lado a lado, habilitada en portrait', (t) async {
    await pump(t);
    expect(enabled(t, 'montage-keep-aspect'), isFalse);
    expect(enabled(t, 'montage-caption'), isTrue);
  });

  testWidgets('mantener aspecto habilitada con estado portrait', (t) async {
    await pump(t, open: 'open.portrait.result');
    expect(enabled(t, 'montage-keep-aspect'), isTrue);
  });

  testWidgets('limitador deshabilitado sin normalizar', (t) async {
    final Json s = fx('open.result');
    final Json ex = (s['export'] as Map).cast<String, Object?>();
    await pump(t, snapshot: {...s, 'export': {...ex, 'normalize': false}});
    expect(enabled(t, 'montage-limiter'), isFalse);
    expect(enabled(t, 'montage-normalize'), isTrue);
  });

  testWidgets('cada casilla llama a su acción', (t) async {
    final MockCore core = await pump(t, open: 'open.portrait.result');
    for (final String k in _boxes) {
      await t.tap(key(k));
      await t.pump();
    }
    final List<String> m = methods(core);
    expect(m.where((e) => e == 'montage.setExport').length, 3);
    expect(m, containsAll(<String>['montage.setCaption', 'montage.setShowPartLabels', 'montage.setKeepVideoAspect', 'montage.setCutGaps']));
    final List<Object?> sent = <Object?>[for (final MockCall c in core.calls.where((c) => c.method == 'montage.setExport')) c.params];
    expect(sent.toString(), allOf(contains('normalize'), contains('limiter'), contains('trackWAVs')));
  });

  testWidgets('cada picker llama a setExport', (t) async {
    final MockCore core = await pump(t);
    Future<void> choose(String k, String current, String option) async {
      await t.tap(key(k));
      await t.pump();
      await t.tap(find.text(option).last);
      await t.pump();
    }

    await choose('montage-codec', 'HEVC', 'H.264');
    await choose('montage-container', 'MOV', 'MP4');
    await choose('montage-resolution', '1080p', '720p');
    await choose('montage-fps', '30 fps', '60 fps');
    final List<String> sent = <String>[for (final MockCall c in core.calls.where((c) => c.method == 'montage.setExport')) c.params.toString()];
    expect(sent.length, 4);
    expect(sent[0], contains('h264'));
    expect(sent[1], contains('mp4'));
    expect(sent[2], contains('720'));
    expect(sent[3], contains('60'));
  });

  testWidgets('popover Transiciones: abre y muestra las filas (golden)', (t) async {
    await pump(t);
    expect(find.text('Muelle · 0,5 s'), findsNothing);
    await t.tap(key('montage-transitions-info'));
    await t.pump();
    expect(find.text('Transiciones'), findsOneWidget);
    expect(find.text('Recolocación'), findsOneWidget);
    expect(find.text('Muelle · 0,5 s'), findsOneWidget);
    expect(find.text('Esquinas'), findsOneWidget);
    await expectLater(find.byKey(_root), matchesGoldenFile('goldens/montage_settings_transitions.png'));
  });

  testWidgets('exporting: todo deshabilitado', (t) async {
    final MockCore core = await pump(t, open: 'open.exporting.result');
    for (final String k in _boxes) {
      expect(enabled(t, k), isFalse, reason: k);
    }
    final int before = find.text('MP4').evaluate().length;
    await t.tap(key('montage-container'));
    await t.pump();
    expect(find.text('MP4').evaluate().length, before);
    expect(methods(core), isNot(contains('montage.setExport')));
  });
}
