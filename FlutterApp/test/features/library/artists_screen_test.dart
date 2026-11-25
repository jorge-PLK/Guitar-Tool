import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/library/library_logic.dart';
import 'package:toneforge/features/library/library_prefs.dart';
import 'package:toneforge/features/library/library_screen.dart';
import 'package:toneforge/features/library/library_store.dart';
import 'package:toneforge/features/library/widgets/artist_tile.dart';
import 'package:toneforge/features/library/widgets/song_row.dart';
import 'package:toneforge/features/library/widgets/song_table.dart';
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

final _projects = [
  _project('1', 'Enter Sandman', artist: 'Metallica'),
  _project('2', 'One', artist: 'Metallica'),
  _project('3', 'Hysteria', artist: 'Muse'),
  _project('4', 'Wonderwall', artist: 'Oasis'),
  _project('5', 'Tema suelto'),
];

/// Monta la `LibraryScreen` completa (un único scroll de página) con grouping = artists.
Future<ProviderContainer> _pump(WidgetTester tester) async {
  await tester.runAsync(loadTfFonts);
  setTestSurface(tester, const Size(1440, 900));
  final core = await tester.runAsync(() async => MockCore.load((await DirectoryFixtureSource.find())!));
  core!.result('library.list', {'projects': _projects, 'skipped': <Object>[]});
  core.result('library.artistPhoto', {'photo': null});
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
        pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) =>
            PageRouteBuilder<T>(settings: s, pageBuilder: (ctx, a, b2) => b(ctx)),
        home: ColoredBox(
          color: TfColors.bg,
          child: DefaultTextStyle(
            style: TfText.body().copyWith(color: TfColors.text),
            child: const LibraryScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(() async => pumpEventQueue());
  await tester.pump();
  await tester.pump();
  await c.read(libraryStoreProvider.notifier).setGrouping(LibraryGrouping.artists);
  await tester.pump();
  await tester.pump();
  return c;
}

void main() {
  testWidgets('LibraryScreen en artistas: se ven los recuadros y no hay excepción', (tester) async {
    await _pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(ArtistTile), findsNWidgets(4));
  });

  testWidgets('LibraryScreen con artista abierto: se ve la tabla y no hay excepción', (tester) async {
    final c = await _pump(tester);
    c.read(libraryStoreProvider.notifier).openArtistGroup('Metallica');
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(ArtistTile), findsNothing);
    expect(find.byType(SongTable), findsOneWidget);
    expect(find.byType(SongRow), findsNWidgets(2));
  });
}
