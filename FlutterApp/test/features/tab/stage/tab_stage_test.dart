import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/tab/songsterr_store.dart';
import 'package:toneforge/features/tab/tab_stage.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/widgets/tf_accent_bar.dart';

import '../../../support/harness.dart';
import '../tab_test_support.dart';

class _FakeTab extends TabStore {
  _FakeTab(this.initial, this.log);
  final TabStoreState initial;
  final List<String> log;

  @override
  TabStoreState build() => initial;

  @override
  Future<TabState?> setSource(TabSource source) async {
    log.add('setSource:${source.wire}');
    return null;
  }
}

class _FakeSongsterr extends SongsterrStore {
  _FakeSongsterr(this.log);
  final List<String> log;

  @override
  SongsterrStoreState build() => const SongsterrStoreState();

  @override
  Future<SongsterrSheetState?> open() async {
    log.add('songsterr.open');
    return null;
  }
}

TabTrackInfo track(String id, TabTranscription t, {double? progress}) => TabTrackInfo(
      id: id,
      name: 'Pista $id',
      kind: TabTrackKind.guitar,
      origin: TabOrigin.stem,
      transcription: t,
      noteCount: 0,
      muted: false,
      solo: false,
      dimmed: false,
      listening: false,
      progress: progress,
    );

TabStoreState stateOf(TabPhase phase, {List<TabTrackInfo> tracks = const [], String? error}) =>
    TabStoreState(
      tab: TabState(
        projectId: projectId,
        phase: phase,
        error: error,
        tracks: tracks,
        notices: const [],
        canUndo: false,
        canRedo: false,
        editMode: false,
        graceMode: false,
        listenMode: TabListenMode.stems,
        anySolo: false,
        revision: 1,
      ),
    );

const _canvasKey = ValueKey<String>('canvas');

Future<(List<String>, MockCore)> pump(
  WidgetTester tester,
  TabStoreState s, {
  String? webError,
}) async {
  setTestSurface(tester, const Size(800, 500));
  final log = <String>[];
  final core = (await tester.runAsync(loadCore))!;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      coreClientProvider.overrideWithValue(core),
      tabStoreProvider.overrideWith(() => _FakeTab(s, log)),
      songsterrStoreProvider.overrideWith(() => _FakeSongsterr(log)),
    ],
    child: tfNavApp(
      Localizations(
        locale: const Locale('es'),
        delegates: const [AppLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
        child: DefaultTextStyle(
          style: const TextStyle(),
          child: TabStage(canvas: const SizedBox.expand(key: _canvasKey), webError: webError),
        ),
      ),
    ),
  ));
  await tester.pump();
  return (log, core);
}

double canvasOpacity(WidgetTester tester) =>
    tester.widget<Opacity>(find.byKey(const ValueKey<String>('stage-canvas-opacity'))).opacity;

bool boxOpaque(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(find.byKey(const ValueKey<String>('phase-box')));
  return (box.decoration as BoxDecoration).color != null;
}

void main() {
  setUpAll(() async {
    await findFixtures();
    await loadTfFonts();
  });

  for (final (phase, title) in <(TabPhase, String)>[
    (TabPhase.waitingAnalysis, 'Esperando el análisis del tema'),
    (TabPhase.empty, 'No hay pistas que transcribir'),
    (TabPhase.choosingSource, 'Elige la fuente de la tablatura'),
    (TabPhase.failed, 'No se pudo transcribir'),
  ]) {
    testWidgets('$phase: título, lienzo oculto pero montado, caja opaca', (tester) async {
      await pump(tester, stateOf(phase, error: 'boom'));
      expect(find.text(title), findsOneWidget);
      expect(find.byKey(_canvasKey), findsOneWidget);
      expect(canvasOpacity(tester), 0);
      expect(boxOpaque(tester), isTrue);
    });
  }

  testWidgets('failed muestra el mensaje y no tiene botones', (tester) async {
    await pump(tester, stateOf(TabPhase.failed, error: 'boom'));
    expect(find.text('boom'), findsOneWidget);
  });

  testWidgets('waitingAnalysis: Analizar llama a study.analyze', (tester) async {
    final (_, core) = await pump(tester, stateOf(TabPhase.waitingAnalysis));
    final container = ProviderScope.containerOf(tester.element(find.byType(TabStage)));
    container.listen(studyStoreProvider, (_, _) {});
    container.read(selectedProjectProvider.notifier).select(projectId);
    await tester.runAsync(settle);
    await tester.tap(find.text('Analizar'));
    await tester.pump();
    expect(core.calls.map((c) => c.method), contains('study.analyze'));
  });

  testWidgets('choosingSource: los dos botones llaman a su método', (tester) async {
    final (log, _) = await pump(tester, stateOf(TabPhase.choosingSource));
    await tester.tap(find.text('Buscar en Songsterr'));
    await tester.tap(find.text('Transcribir automáticamente'));
    await tester.pump();
    expect(log, ['songsterr.open', 'setSource:automatic']);
  });

  testWidgets('working sin pistas: overlay opaco, lienzo oculto, barras por pista', (tester) async {
    await pump(
      tester,
      stateOf(TabPhase.working, tracks: [
        track('a', TabTranscription.queued),
        track('b', TabTranscription.transcribing, progress: 0.4),
      ]),
    );
    expect(find.text('Transcribiendo…'), findsOneWidget);
    expect(boxOpaque(tester), isTrue);
    expect(canvasOpacity(tester), 0);
    expect(find.text('Pista a'), findsOneWidget);
    final bars = tester.widgetList<TfAccentBar>(find.byType(TfAccentBar)).toList();
    expect(bars.map((b) => b.value), [null, 0.4]);
  });

  testWidgets('working con pistas: lienzo visible y overlay transparente', (tester) async {
    await pump(
      tester,
      stateOf(TabPhase.working, tracks: [
        track('a', TabTranscription.ready),
        track('b', TabTranscription.queued),
      ]),
    );
    expect(find.text('Transcribiendo…'), findsOneWidget);
    expect(canvasOpacity(tester), 1);
    expect(boxOpaque(tester), isFalse);
  });

  testWidgets('ready: lienzo visible y sin overlay', (tester) async {
    await pump(tester, stateOf(TabPhase.ready));
    expect(canvasOpacity(tester), 1);
    expect(find.byKey(const ValueKey<String>('phase-box')), findsNothing);
  });

  testWidgets('ready: el lienzo no está bajo ningún recorte ni absorbe el puntero (WKWebView recibe el ratón)',
      (tester) async {
    await pump(tester, stateOf(TabPhase.ready));
    final canvas = find.byKey(_canvasKey);
    final stage = find.byType(TabStage);
    // Solo cuenta lo que cuelga del escenario (el MaterialApp de prueba trae sus propios recortes).
    for (final type in <Type>[ClipRRect, ClipRect, ClipPath, AbsorbPointer, BackdropFilter]) {
      final inside = find.descendant(of: stage, matching: find.byType(type));
      expect(find.descendant(of: inside, matching: canvas), findsNothing, reason: '$type envuelve al lienzo');
    }
    final ignore = tester.widget<IgnorePointer>(
        find.descendant(of: stage, matching: find.byType(IgnorePointer)).first);
    expect(ignore.ignoring, isFalse);
    expect(find.byKey(const ValueKey<String>('phase-box')), findsNothing);
  });

  testWidgets('ready con webError: genérico y detalle en danger, sin caja', (tester) async {
    await pump(tester, stateOf(TabPhase.ready), webError: 'font load failed');
    expect(find.text('No se pudo mostrar la tablatura.'), findsOneWidget);
    expect(find.text('font load failed'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('phase-box')), findsNothing);
    expect(canvasOpacity(tester), 1);
  });
}
