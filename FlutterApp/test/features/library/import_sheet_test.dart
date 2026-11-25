import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/link_import.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/library/library_metrics.dart';
import 'package:toneforge/features/library/link_import_store.dart';
import 'package:toneforge/features/library/sheets/import_banner.dart';
import 'package:toneforge/features/library/sheets/import_empty_view.dart';
import 'package:toneforge/features/library/sheets/import_sheet.dart';
import 'package:toneforge/features/library/sheets/spotify_track_row.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';

import '../../support/harness.dart';

class _FakeLinkStore extends LinkImportStore {
  _FakeLinkStore(this.initial);

  final LinkImportState initial;
  int submits = 0;
  int resets = 0;
  String? chosen;

  @override
  LinkImportState build() => initial;

  void put(LinkImportState s) => state = s;

  @override
  void reset() => resets++;

  @override
  Future<void> submit() async => submits++;

  @override
  Future<void> chooseSpotifyTrack(LinkSpotifyTrack track) async => chosen = track.id;

  @override
  Future<void> openSpotify(String url, {String? fallback}) async {}
}

LinkSpotifyTrack _track(String id, String name, {int? year = 1991}) => LinkSpotifyTrack.fromJson({
  'id': id,
  'name': name,
  'artists': ['Metallica', 'Otro'],
  'album': 'Black Album',
  'year': ?year,
  'durationText': '5:31',
  'trackURL': 'https://open.spotify.com/track/$id',
  'appURL': 'spotify:track:$id',
});

late _FakeLinkStore _store;
late BuildContext _ctx;

Future<void> _open(WidgetTester tester, LinkImportState state) async {
  await tester.runAsync(loadTfFonts);
  setTestSurface(tester, const Size(1100, 760));
  final core = (await tester.runAsync(() async => MockCore.load((await DirectoryFixtureSource.find())!)))!;
  _store = _FakeLinkStore(state);
  final c = ProviderContainer(
    overrides: [coreClientProvider.overrideWithValue(core), linkImportStoreProvider.overrideWith(() => _store)],
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
            child: Builder(
              builder: (ctx) {
                _ctx = ctx;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    ),
  );
  unawaited(showImportSheet(_ctx));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _put(WidgetTester tester, LinkImportState s) async {
  _store.put(s);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

AppLocalizations get _l => AppLocalizations.of(_ctx);

double _sheetWidth(WidgetTester tester) =>
    tester.getSize(find.descendant(of: find.byType(ImportSheetBody), matching: find.byType(SizedBox)).first).width;

bool _goEnabled(WidgetTester tester) =>
    tester.widget<TfPrimaryButton>(find.byType(TfPrimaryButton)).onPressed != null;

void main() {
  testWidgets('Importar deshabilitado con el campo vacío y con trabajo en curso', (tester) async {
    await _open(tester, const LinkImportState());
    expect(_goEnabled(tester), isFalse);
    await _put(tester, const LinkImportState(text: 'https://youtu.be/x'));
    expect(_goEnabled(tester), isTrue);
    await _put(tester, const LinkImportState(text: 'https://youtu.be/x', passRunning: true));
    expect(_goEnabled(tester), isFalse);
    await _put(tester, const LinkImportState(text: 'abc', searching: true));
    expect(_goEnabled(tester), isFalse);
  });

  testWidgets('Esc cierra en la vacía', (tester) async {
    await _open(tester, const LinkImportState());
    expect(find.byType(ImportEmptyView), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ImportSheetBody), findsNothing);
    expect(_store.resets, 2);
  });

  testWidgets('Esc no cierra mientras !canCancel', (tester) async {
    await _open(tester, const LinkImportState(screen: LinkImportScreen.working, workPhase: LinkWorkPhase.importing));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ImportSheetBody), findsOneWidget);
  });

  testWidgets('Intro envía y el ancho es 620 en vacía y 560 en otra pantalla', (tester) async {
    await _open(tester, const LinkImportState(text: 'https://youtu.be/x'));
    expect(_sheetWidth(tester), LibraryMetrics.importSheetEmptyWidth);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(_store.submits, greaterThan(0));
    await _put(tester, const LinkImportState(screen: LinkImportScreen.preparing));
    expect(_sheetWidth(tester), LibraryMetrics.importSheetWidth);
    expect(find.text(_l.library_importTitleLink), findsOneWidget);
  });

  testWidgets('resultados de Spotify: filas y Elegir', (tester) async {
    await _open(
      tester,
      LinkImportState(
        text: 'master',
        spotifyQuery: 'master',
        spotifyTracks: [_track('a', 'Master of Puppets'), _track('b', 'One', year: null)],
      ),
    );
    expect(find.byType(SpotifyTrackRow), findsNWidgets(2));
    expect(find.text('Master of Puppets'), findsOneWidget);
    expect(find.text('Metallica, Otro'), findsNWidgets(2));
    expect(find.text('Black Album · 1991'), findsOneWidget);
    expect(find.text('Black Album'), findsOneWidget);
    await tester.tap(find.text(_l.library_importChoose).first);
    expect(_store.chosen, 'a');
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(ImportSheetBody), matchesGoldenFile('goldens/import_sheet_spotify.png'));
  });

  testWidgets('vacía: ayuda y golden', (tester) async {
    await _open(tester, const LinkImportState());
    expect(find.text(_l.library_importSupported), findsOneWidget);
    expect(find.byType(ImportBanner), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(ImportSheetBody), matchesGoldenFile('goldens/import_sheet_empty.png'));
  });

  testWidgets('error de Spotify: banner y ayuda', (tester) async {
    await _open(tester, const LinkImportState(text: 'metallica one'));
    await _put(tester, const LinkImportState(text: 'metallica one', spotifyError: CoreError('offline', 'Sin conexión')));
    expect(find.byType(ImportBanner), findsOneWidget);
    expect(find.text(_l.library_importSupported), findsOneWidget);
    await expectLater(find.byType(ImportSheetBody), matchesGoldenFile('goldens/import_spotify_error.png'));
  });

  testWidgets('duplicado cierra y abre la alerta', (tester) async {
    await _open(tester, const LinkImportState());
    await _put(tester, const LinkImportState(duplicateOf: 'p1'));
    expect(find.text(_l.library_duplicateTitle), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.byType(ImportSheetBody), findsNothing);
    expect(find.text(_l.library_duplicateTitle), findsNothing);
  });

  testWidgets('hecho sin avisos cierra; con avisos no', (tester) async {
    await _open(tester, const LinkImportState());
    await _put(tester, const LinkImportState(screen: LinkImportScreen.done, notices: ['aviso']));
    expect(find.byType(ImportSheetBody), findsOneWidget);
    await _put(tester, const LinkImportState(screen: LinkImportScreen.empty));
    await _put(tester, const LinkImportState(screen: LinkImportScreen.done));
    expect(find.byType(ImportSheetBody), findsNothing);
  });
}
