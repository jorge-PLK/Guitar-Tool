import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/playlist.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/library/playlist_store.dart';
import 'package:toneforge/features/library/sheets/import_sheet.dart';
import 'package:toneforge/features/library/sheets/playlist_pick_view.dart';
import 'package:toneforge/features/library/sheets/playlist_status_views.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_checkbox.dart';

import '../../support/harness.dart';

class _FakePlaylist extends PlaylistStore {
  _FakePlaylist(this.initial);

  final PlaylistSnapshot initial;
  final calls = <String>[];

  @override
  PlaylistState build() => PlaylistState(snapshot: initial, sheetOpen: true);

  void put(PlaylistSnapshot s) => state = state.copyWith(snapshot: s);

  @override
  Future<CoreError?> select(String id, bool selected) async {
    calls.add('select $id $selected');
    return null;
  }

  @override
  Future<CoreError?> selectAll() async {
    calls.add('selectAll');
    return null;
  }

  @override
  Future<CoreError?> selectNone() async {
    calls.add('selectNone');
    return null;
  }

  @override
  Future<CoreError?> continue_() async {
    calls.add('continue');
    return null;
  }

  @override
  Future<CoreError?> cancel() async {
    calls.add('cancel');
    return null;
  }

  @override
  void closeSheet() => calls.add('closeSheet');

  @override
  Future<PlaylistCloseOutcome> close({bool force = false}) async {
    calls.add('close $force');
    return (error: null, result: null);
  }
}

late _FakePlaylist _store;
late BuildContext _ctx;

Future<Map<String, Object?>> _fixture(WidgetTester tester, String step) async {
  final text = await tester.runAsync(() async {
    final src = (await DirectoryFixtureSource.find())!;
    return src.read('playlist/playlist.changed.$step.event.json');
  });
  return (json.decode(text!) as Map).cast<String, Object?>();
}

PlaylistSnapshot _snap(Map<String, Object?> j) => PlaylistSnapshot.fromJson(j);

Map<String, Object?> _withItems(Map<String, Object?> j, void Function(List<Map<String, Object?>> items) edit) {
  final copy = (json.decode(json.encode(j)) as Map).cast<String, Object?>();
  final items = [for (final i in copy['items']! as List) (i as Map).cast<String, Object?>()];
  edit(items);
  copy['items'] = items;
  return copy;
}

Map<String, Object?> _totals(Map<String, Object?> j, {int? selected, int? inLibrary}) {
  final copy = (json.decode(json.encode(j)) as Map).cast<String, Object?>();
  final t = (copy['totals']! as Map).cast<String, Object?>();
  if (selected != null) t['selected'] = selected;
  if (inLibrary != null) t['inLibrary'] = inLibrary;
  copy['totals'] = t;
  return copy;
}

Future<void> _open(WidgetTester tester, Map<String, Object?> j) async {
  await tester.runAsync(loadTfFonts);
  setTestSurface(tester, const Size(1100, 760));
  final core = (await tester.runAsync(() async => MockCore.load((await DirectoryFixtureSource.find())!)))!;
  _store = _FakePlaylist(_snap(j));
  final c = ProviderContainer(
    overrides: [coreClientProvider.overrideWithValue(core), playlistStoreProvider.overrideWith(() => _store)],
  );
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: WidgetsApp(
        color: TfColors.bg,
        debugShowCheckedModeBanner: false,
        locale: const Locale('es'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) =>
            PageRouteBuilder<T>(settings: s, pageBuilder: (ctx, a, b2) => b(ctx)),
        home: ColoredBox(
          color: TfColors.bg,
          child: DefaultTextStyle(
            style: TfText.body().copyWith(color: TfColors.text),
            child: Center(
              child: Builder(
                builder: (ctx) {
                  _ctx = ctx;
                  return ImportSheetBody(resumePlaylist: true, parent: ctx, onClose: () {});
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _put(WidgetTester tester, Map<String, Object?> j) async {
  _store.put(_snap(j));
  await tester.pump(const Duration(milliseconds: 100));
}

AppLocalizations get _l => AppLocalizations.of(_ctx);

TfPrimaryButton _primary(WidgetTester tester) => tester.widget<TfPrimaryButton>(find.byType(TfPrimaryButton));

void main() {
  testWidgets('enruta por step', (tester) async {
    await _open(tester, await _fixture(tester, 'loading'));
    expect(find.byType(PlaylistLoadingView), findsOneWidget);
    expect(find.text(_l.library_plIndLoading), findsOneWidget);
    await _put(tester, await _fixture(tester, 'tracks'));
    expect(find.byType(PlaylistPickView), findsOneWidget);
    await _put(tester, await _fixture(tester, 'searching'));
    expect(find.byType(PlaylistSearchingView), findsOneWidget);
    await _put(tester, await _fixture(tester, 'error'));
    expect(find.byType(PlaylistErrorView), findsOneWidget);
  });

  testWidgets('leyendo: Cancelar cancela y descarta', (tester) async {
    await _open(tester, await _fixture(tester, 'loading'));
    await tester.tap(find.text(_l.library_plCancel));
    await tester.pump();
    expect(_store.calls, ['cancel', 'close true']);
  });

  testWidgets('elegir temas: resumen, marcar y desmarcar llama select', (tester) async {
    final j = _totals(await _fixture(tester, 'tracks'), selected: 1);
    await _open(tester, j);
    final total = _snap(j).totals.total;
    expect(find.text(_l.library_plSummary(total, 1)), findsOneWidget);
    expect(find.text('Mi lista'), findsOneWidget);
    final first = _snap(j).items.first;
    await tester.tap(find.byType(TfCheckbox).first);
    await tester.tap(find.text(first.title));
    expect(_store.calls, ['select ${first.id} ${!first.selected}', 'select ${first.id} ${!first.selected}']);
  });

  testWidgets('Marcar todos y Ninguno', (tester) async {
    await _open(tester, await _fixture(tester, 'tracks'));
    await tester.tap(find.text(_l.library_plSelectAll));
    await tester.tap(find.text(_l.library_plSelectNone));
    expect(_store.calls, ['selectAll', 'selectNone']);
  });

  testWidgets('botón principal: N y texto según continueIsSearch', (tester) async {
    final j = await _fixture(tester, 'tracks');
    await _open(tester, _totals(j, selected: 0));
    expect(find.text(_l.library_plSearch(0)), findsOneWidget);
    expect(_primary(tester).onPressed, isNull);
    await _put(tester, _totals(j, selected: 2));
    expect(find.text(_l.library_plSearch(2)), findsOneWidget);
    expect(_primary(tester).onPressed, isNotNull);
    await tester.tap(find.text(_l.library_plSearch(2)));
    expect(_store.calls, ['continue']);
    final yt = _totals(j, selected: 3)..['source'] = 'youtube';
    await _put(tester, yt);
    expect(find.text(_l.library_plDownload(3)), findsOneWidget);
    expect(find.text(_l.library_plSearch(3)), findsNothing);
  });

  testWidgets('chips, tope de 100 y Cerrar con cola viva', (tester) async {
    final base = _totals(await _fixture(tester, 'tracks'), selected: 1, inLibrary: 1);
    final j = _withItems(base, (items) {
      items[0]['status'] = 'inLibrary';
      items[1]['possible'] = {'id': 'X', 'title': 'Tema B (remaster)'};
    })..['mayBeTruncated'] = true;
    j['isLive'] = true;
    await _open(tester, j);
    expect(find.text(_l.library_plQInLibrary), findsOneWidget);
    expect(find.text(_l.library_plChipMaybe), findsOneWidget);
    expect(find.text(_l.library_plCap), findsOneWidget);
    final total = _snap(j).totals.total;
    expect(find.text(_l.library_plSummary(total, 1) + _l.library_plSummaryInLibrary(1)), findsOneWidget);
    await tester.tap(find.text(_l.library_plQInLibrary));
    expect(_store.calls, isEmpty);
    await tester.tap(find.text(_l.library_importClose));
    await tester.pump();
    expect(_store.calls, ['closeSheet']);
  });

  testWidgets('buscando: Buscando X de N y Cancelar', (tester) async {
    final j = await _fixture(tester, 'searching');
    await _open(tester, j);
    final s = _snap(j);
    expect(find.text(_l.library_plSearchingN((s.searchDone ?? 0) + 1, s.searchTotal ?? 0)), findsOneWidget);
    expect(find.text(_l.library_plNothingYet), findsOneWidget);
    await tester.tap(find.text(_l.library_plCancel));
    expect(_store.calls, ['cancel']);
    await expectLater(find.byType(ImportSheetBody), matchesGoldenFile('goldens/playlist_searching.png'));
  });

  testWidgets('error de lista: título, detalle y sus dos botones', (tester) async {
    final j = await _fixture(tester, 'error');
    await _open(tester, j);
    final e = _snap(j).error!;
    expect(find.text(e.title), findsOneWidget);
    expect(find.text(e.detail), findsOneWidget);
    await tester.tap(find.text(_l.library_importOtherLink));
    await tester.pump();
    expect(_store.calls, ['close true']);
    await tester.tap(find.text(_l.library_importClose));
    await tester.pump();
    expect(_store.calls, ['close true', 'close false']);
  });

  testWidgets('golden de elegir temas', (tester) async {
    final base = _totals(await _fixture(tester, 'tracks'), selected: 2, inLibrary: 1);
    final j = _withItems(base, (items) {
      items[0]['status'] = 'inLibrary';
      items[1]['selected'] = true;
      items[2]['possible'] = {'id': 'X', 'title': 'Tema C'};
    });
    await _open(tester, j);
    await expectLater(find.byType(ImportSheetBody), matchesGoldenFile('goldens/playlist_pick.png'));
  });
}
