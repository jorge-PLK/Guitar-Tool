import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/tab/tab_edit_bar.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';

import '../../../support/harness.dart';

/// Store de Tablatura con estado fijo que anota las llamadas `tab.edit` (sin núcleo).
class FakeTabStore extends TabStore {
  FakeTabStore(this.initial);

  final TabStoreState initial;
  final List<Object?> calls = <Object?>[];

  @override
  TabStoreState build() => initial;

  @override
  Future<TabState?> edit(TabEditParams p) async {
    calls.add(p.toJson());
    return null;
  }
}

TabTrackInfo track(
  String id, {
  TabTrackKind kind = TabTrackKind.guitar,
}) =>
    TabTrackInfo(
      id: id,
      name: id,
      kind: kind,
      origin: TabOrigin.stem,
      transcription: TabTranscription.ready,
      noteCount: 10,
      muted: false,
      solo: false,
      dimmed: false,
      listening: false,
      tuning: kind == TabTrackKind.drums
          ? null
          : const TabTuningInfo(preset: TabTuningPreset.standard, name: 'Estándar', strings: <int>[]),
      synth: null,
    );

TabState tabState(
  List<TabTrackInfo> tracks, {
  String? selected,
  TabSelectionInfo? selection,
  bool canUndo = false,
  bool canRedo = false,
}) =>
    TabState(
      projectId: 'p',
      phase: TabPhase.ready,
      tracks: tracks,
      notices: const <String>[],
      canUndo: canUndo,
      canRedo: canRedo,
      editMode: false,
      graceMode: false,
      listenMode: TabListenMode.stems,
      anySolo: false,
      revision: 1,
      selectedTrack: selected,
      source: TabSource.automatic,
      selection: selection,
    );

/// Monta [TabEditBar] con idioma español y un store falso; devuelve el store.
Future<FakeTabStore> pumpBar(WidgetTester tester, TabState? tab) async {
  setTestSurface(tester, const Size(1200, 400));
  final FakeTabStore store = FakeTabStore(TabStoreState(tab: tab));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [tabStoreProvider.overrideWith(() => store)],
      child: WidgetsApp(
        color: TfColors.bg,
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        debugShowCheckedModeBanner: false,
        pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) => PageRouteBuilder<T>(
          settings: s,
          pageBuilder: (BuildContext c, Animation<double> a, Animation<double> b2) => b(c),
        ),
        home: const Align(alignment: Alignment.topLeft, child: TabEditBar()),
      ),
    ),
  );
  await tester.pump();
  return store;
}

const TabSelectionInfo noteSel = TabSelectionInfo(track: 'bass', beat: 1, tick: 0, hasNote: true);
const TabSelectionInfo restSel = TabSelectionInfo(track: 'bass', beat: 1, tick: 0, hasNote: false);

void main() {
  group('TabEditBar', () {
    testWidgets('Deshacer y Rehacer deshabilitados sin canUndo/canRedo', (tester) async {
      final FakeTabStore store = await pumpBar(
        tester,
        tabState(<TabTrackInfo>[track('bass')], selected: 'bass'),
      );
      await tester.tap(find.text('Deshacer'));
      await tester.tap(find.text('Rehacer'));
      await tester.pump();
      expect(store.calls, isEmpty);
    });

    testWidgets('Deshacer y Rehacer llaman a edit con canUndo/canRedo', (tester) async {
      final FakeTabStore store = await pumpBar(
        tester,
        tabState(<TabTrackInfo>[track('bass')], selected: 'bass', canUndo: true, canRedo: true),
      );
      await tester.tap(find.text('Deshacer'));
      await tester.tap(find.text('Rehacer'));
      await tester.pump();
      expect(store.calls, <Object?>[
        <String, Object?>{'op': 'undo'},
        <String, Object?>{'op': 'redo'},
      ]);
    });

    testWidgets('pista de batería: seis piezas, deshabilitadas sin selección', (tester) async {
      final FakeTabStore none = await pumpBar(
        tester,
        tabState(<TabTrackInfo>[track('drums', kind: TabTrackKind.drums)], selected: 'drums'),
      );
      for (final String label in <String>['Bombo', 'Caja', 'Charles', 'Charles abierto', 'Tom', 'Platos']) {
        expect(find.text(label), findsOneWidget);
        await tester.tap(find.text(label));
      }
      await tester.pump();
      expect(none.calls, isEmpty);
    });

    testWidgets('pista de batería: «Charles abierto» manda piece openHiHat', (tester) async {
      final FakeTabStore store = await pumpBar(
        tester,
        tabState(
          <TabTrackInfo>[track('drums', kind: TabTrackKind.drums)],
          selected: 'drums',
          selection: restSel,
        ),
      );
      await tester.tap(find.text('Charles abierto'));
      await tester.pump();
      expect(store.calls, <Object?>[
        <String, Object?>{'op': 'hit', 'piece': 'openHiHat'},
      ]);
    });

    testWidgets('melódica: cuatro botones deshabilitados sin nota', (tester) async {
      final FakeTabStore store = await pumpBar(
        tester,
        tabState(<TabTrackInfo>[track('bass')], selected: 'bass', selection: restSel),
      );
      for (final String label in <String>['Añadir nota', '–', '+', 'Borrar']) {
        await tester.tap(find.text(label));
      }
      await tester.pump();
      expect(store.calls, isEmpty);
    });

    testWidgets('melódica: cuatro botones habilitados con nota, cada uno manda su op', (tester) async {
      final FakeTabStore store = await pumpBar(
        tester,
        tabState(<TabTrackInfo>[track('bass')], selected: 'bass', selection: noteSel),
      );
      await tester.tap(find.text('Añadir nota'));
      await tester.tap(find.text('–'));
      await tester.tap(find.text('+'));
      await tester.tap(find.text('Borrar'));
      await tester.pump();
      expect(store.calls, <Object?>[
        <String, Object?>{'op': 'addNote'},
        <String, Object?>{'op': 'duration', 'sign': -1},
        <String, Object?>{'op': 'duration', 'sign': 1},
        <String, Object?>{'op': 'delete'},
      ]);
    });
  });
}
