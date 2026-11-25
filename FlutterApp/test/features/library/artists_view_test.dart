import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/library/library_prefs.dart';
import 'package:toneforge/features/library/library_store.dart';
import 'package:toneforge/features/library/widgets/artist_avatar.dart';
import 'package:toneforge/features/library/widgets/artist_grid.dart';
import 'package:toneforge/features/library/widgets/artist_tile.dart';
import 'package:toneforge/features/library/widgets/artists_view.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

import '../../support/harness.dart';

class _MemoryPrefs implements LibraryPrefs {
  final Map<String, String> values = {};

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async => values[key] = value;
}

Json _project(String id, String title, {String? artist}) => {
  'id': id,
  'title': title,
  'artist': ?artist,
  'folderName': title,
  'duration': 1,
  'sampleRate': 44100,
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': '2026-01-01T00:00:00Z',
  'separationState': 'none',
  'separationError': null,
  'stemCount': 0,
  'takeCount': 0,
  'rigCount': 0,
  'hasAnalysis': false,
  'guitars': <String>[],
};

// PNG de 1x1 píxel.
const _png =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

final _projects = [
  _project('1', 'Enter Sandman', artist: 'Metallica'),
  _project('2', 'One', artist: 'Metallica'),
  _project('3', 'Hysteria', artist: 'Muse'),
  _project('4', 'Wonderwall', artist: 'Oasis'),
  _project('5', 'Tema suelto'),
];

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Size size = const Size(900, 700),
  List<Json>? projects,
  String? photo,
}) async {
  await tester.runAsync(loadTfFonts);
  setTestSurface(tester, size);
  final core = await tester.runAsync(() async => MockCore.load((await DirectoryFixtureSource.find())!));
  core!.result('library.list', {'projects': projects ?? _projects, 'skipped': <Object>[]});
  core.result('library.artistPhoto', {'photo': photo});
  final c = ProviderContainer(
    overrides: [coreClientProvider.overrideWithValue(core), libraryPrefsProvider.overrideWithValue(_MemoryPrefs())],
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
        pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) => PageRouteBuilder<T>(
          settings: s,
          pageBuilder: (ctx, a, b2) => b(ctx),
        ),
        home: RepaintBoundary(
          key: k5Boundary,
          child: ColoredBox(
            color: TfColors.bg,
            child: DefaultTextStyle(
              style: TfText.body().copyWith(color: TfColors.text),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: TfSpace.s40, vertical: TfSpace.s32),
                child: ArtistsView(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(() async => pumpEventQueue());
  await tester.pump();
  await tester.pump();
  return c;
}

void main() {
  test('iniciales: dos primeras palabras y «?» si no hay', () {
    expect(artistInitials('Metallica'), 'M');
    expect(artistInitials('pink floyd'), 'PF');
    expect(artistInitials('  the   rolling stones '), 'TR');
    expect(artistInitials(''), '?');
    expect(artistInitials('   '), '?');
  });

  test('color estable por nombre plegado', () {
    expect(artistAvatar('Metallica'), const Color(0xFF798046));
    expect(artistAvatar('METALLICA'), artistAvatar('metallica'));
    expect(artistAvatar('Épica'), artistAvatar('epica'));
  });

  test('delegado 160-220: columnas y ancho coherentes', () {
    for (final w in [160.0, 300.0, 500.0, 900.0, 1200.0, 1800.0]) {
      final n = ArtistGridDelegate.columnsFor(w);
      final tile = ArtistGridDelegate.tileWidthFor(w, n);
      expect(tile, inInclusiveRange(artistTileMinWidth, artistTileMaxWidth), reason: 'w=$w');
      expect(n * tile + (n - 1) * artistGridColumnGap, lessThanOrEqualTo(w + 0.001), reason: 'w=$w');
      // Una columna más ya no cabría con el mínimo.
      expect((n + 1) * artistTileMinWidth + n * artistGridColumnGap, greaterThan(w), reason: 'w=$w');
    }
    expect(ArtistGridDelegate.columnsFor(500), 2);
    expect(ArtistGridDelegate.columnsFor(900), 5);
    expect(ArtistGridDelegate.columnsFor(1200), 6);
    expect(ArtistGridDelegate.columnsFor(100), 1);
  });

  testWidgets('cuadrícula: recuadros, plural y «Sin artista» al final', (tester) async {
    await _pump(tester);
    expect(find.byType(ArtistTile), findsNWidgets(4));
    expect(find.text('2 temas'), findsOneWidget);
    expect(find.text('1 tema'), findsNWidgets(3));
    expect(find.text('Sin artista'), findsOneWidget);
    final last = tester.widgetList<ArtistTile>(find.byType(ArtistTile)).last;
    expect(last.name, '');
    expect(find.text('M'), findsNWidgets(2));
    expect(find.text('O'), findsOneWidget);
  });

  testWidgets('abrir un artista muestra la barra y «‹ Artistas» vuelve', (tester) async {
    final c = await _pump(tester);
    await tester.tap(find.text('Metallica'));
    await tester.pump();
    expect(c.read(libraryStoreProvider).openArtist, 'Metallica');
    expect(find.byType(ArtistTile), findsNothing);
    expect(find.text('Artistas'), findsOneWidget);
    expect(find.text('Metallica'), findsOneWidget);
    await tester.tap(find.text('Artistas'));
    await tester.pump();
    expect(c.read(libraryStoreProvider).openArtist, isNull);
    expect(find.byType(ArtistTile), findsNWidgets(4));
  });

  testWidgets('«Sin artista» abre con ese título en la barra', (tester) async {
    final c = await _pump(tester);
    await tester.tap(find.text('Sin artista'));
    await tester.pump();
    expect(c.read(libraryStoreProvider).openArtist, '');
    expect(find.text('Sin artista'), findsOneWidget);
    expect(find.text('Artistas'), findsOneWidget);
  });

  testWidgets('la foto del artista sustituye a las iniciales', (tester) async {
    await _pump(tester, photo: _png);
    expect(find.byType(Image), findsNWidgets(3));
  });

  testWidgets('golden de la cuadrícula', (tester) async {
    await _pump(tester, size: const Size(900, 700));
    await expectLater(find.byKey(k5Boundary), matchesGoldenFile('goldens/artists_grid.png'));
  });
}
