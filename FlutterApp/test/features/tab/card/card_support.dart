import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';

import '../../../support/harness.dart';

/// Store de Tablatura con estado fijo que anota las llamadas (sin núcleo).
class FakeTabStore extends TabStore {
  FakeTabStore(this.initial);

  final TabStoreState initial;
  final List<String> calls = <String>[];

  @override
  TabStoreState build() => initial;

  void set(TabStoreState s) => state = s;

  @override
  Future<TabState?> selectTrack(String track) async {
    calls.add('select:$track');
    return null;
  }

  @override
  Future<TabState?> toggleMute(String track) async {
    calls.add('mute:$track');
    return null;
  }

  @override
  Future<TabState?> toggleSolo(String track) async {
    calls.add('solo:$track');
    return null;
  }

  @override
  Future<TabState?> setListening(String track, {required bool on}) async {
    calls.add('listen:$track:$on');
    return null;
  }

  @override
  Future<TabState?> setAllListening({required bool on}) async {
    calls.add('listenAll:$on');
    return null;
  }

  @override
  Future<TabState?> edit(TabEditParams p) async {
    calls.add('edit:${p.toJson()}');
    return null;
  }
}

TabTrackInfo track(
  String id, {
  String? name,
  TabTrackKind kind = TabTrackKind.guitar,
  TabTranscription transcription = TabTranscription.ready,
  bool muted = false,
  bool solo = false,
  bool dimmed = false,
  bool listening = false,
  TabTuningInfo? tuning = const TabTuningInfo(preset: TabTuningPreset.standard, name: 'Estándar', strings: <int>[]),
  TabSynth? synth,
}) =>
    TabTrackInfo(
      id: id,
      name: name ?? id,
      kind: kind,
      origin: TabOrigin.stem,
      transcription: transcription,
      noteCount: 10,
      muted: muted,
      solo: solo,
      dimmed: dimmed,
      listening: listening,
      tuning: kind == TabTrackKind.drums ? null : tuning,
      synth: synth,
    );

TabState tabState(
  List<TabTrackInfo> tracks, {
  String? selected,
  TabListenMode mode = TabListenMode.stems,
  TabSource source = TabSource.automatic,
  TabSelectionInfo? selection,
  String? header,
}) =>
    TabState(
      projectId: 'p',
      phase: TabPhase.ready,
      tracks: tracks,
      notices: const <String>[],
      canUndo: false,
      canRedo: false,
      editMode: false,
      graceMode: false,
      listenMode: mode,
      anySolo: false,
      revision: 1,
      selectedTrack: selected,
      source: source,
      selection: selection,
      header: header,
    );

/// Monta [child] con idioma, Overlay y un store falso; devuelve el store.
Future<FakeTabStore> pumpCard(
  WidgetTester tester,
  Widget child, {
  TabState? tab,
  String? flash,
  Size size = const Size(900, 600),
}) async {
  setTestSurface(tester, size);
  final FakeTabStore store = FakeTabStore(TabStoreState(tab: tab, flash: flash));
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
        home: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  );
  await tester.pump();
  return store;
}
