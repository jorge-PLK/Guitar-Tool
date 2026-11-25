import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/jobs.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/library/library_prefs.dart';
import 'package:toneforge/features/library/library_screen.dart';
import 'package:toneforge/features/library/library_store.dart';
import 'package:toneforge/features/library/widgets/importing_row.dart';
import 'package:toneforge/features/library/widgets/library_empty.dart';
import 'package:toneforge/features/library/widgets/playlist_indicator.dart';
import 'package:toneforge/features/library/widgets/song_row.dart';
import 'package:toneforge/features/library/widgets/song_table.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_chip.dart';
import 'package:toneforge/widgets/tf_list_row.dart';
import 'package:toneforge/widgets/tf_song_cover.dart';

import '../../support/harness.dart';

class _MemoryPrefs implements LibraryPrefs {
  final Map<String, String> values = {};

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async => values[key] = value;
}

Json _project(String id, String title, {String? artist, String state = 'none', int takes = 0, String? error}) => {
  'id': id,
  'title': title,
  'artist': ?artist,
  'folderName': title,
  'duration': 1,
  'sampleRate': 44100,
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': '2026-01-01T00:00:00Z',
  'separationState': state,
  'separationError': error,
  'stemCount': 0,
  'takeCount': takes,
  'rigCount': 0,
  'hasAnalysis': false,
  'guitars': <String>[],
};

final _projects = [
  _project('1', 'Enter Sandman', artist: 'Metallica', state: 'done', takes: 3),
  _project('2', 'One', artist: 'Metallica', state: 'queued'),
  _project('3', 'Hysteria', artist: 'Muse', state: 'running'),
  _project('4', 'Wonderwall', artist: 'Oasis', state: 'failed', error: 'Sin memoria'),
  _project('5', 'Tema suelto'),
];

late MockCore _core;
late ProviderContainer _c;

Future<void> _pump(WidgetTester tester, Widget child, {List<Json>? projects, bool load = true, Json? appInfo}) async {
  await tester.runAsync(loadTfFonts);
  setTestSurface(tester, const Size(1100, 700));
  _core = (await tester.runAsync(() async => MockCore.load((await DirectoryFixtureSource.find())!)))!;
  _core.result('library.list', {'projects': projects ?? _projects, 'skipped': <Object>[]});
  if (appInfo != null) _core.result('app.info', appInfo);
  _c =ProviderContainer(
    overrides: [coreClientProvider.overrideWithValue(_core), libraryPrefsProvider.overrideWithValue(_MemoryPrefs())],
  );
  addTearDown(_c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _c,
      child: WidgetsApp(
        color: TfColors.bg,
        debugShowCheckedModeBanner: false,
        locale: const Locale('es'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) =>
            PageRouteBuilder<T>(settings: s, pageBuilder: (ctx, a, b2) => b(ctx)),
        home: RepaintBoundary(
          key: k5Boundary,
          child: ColoredBox(
            color: TfColors.bg,
            child: DefaultTextStyle(style: TfText.body().copyWith(color: TfColors.text), child: child),
          ),
        ),
      ),
    ),
  );
  if (load) {
    await tester.runAsync(() async => pumpEventQueue());
    await tester.pump();
    await tester.pump();
  }
}

Future<void> _emitPlaylist(WidgetTester tester, String step, String indicator) async {
  final raw = (await tester.runAsync(() async {
    final src = (await DirectoryFixtureSource.find())!;
    return src.read('playlist/playlist.changed.$step.event.json');
  }))!;
  final j = (json.decode(raw) as Map).cast<String, Object?>();
  j['indicator'] = indicator;
  _core.emit('playlist.changed', j);
  await tester.runAsync(() async => pumpEventQueue());
  await tester.pump();
}

void main() {
  testWidgets('portada: con cover y carpeta usa FileImage; sin cover, placeholder', (tester) async {
    await _pump(
      tester,
      const LibraryScreen(),
      projects: [
        {..._project('1', 'Con portada'), 'cover': 'Con portada/source/cover.jpg'},
        _project('2', 'Sin portada'),
      ],
      appInfo: {'projectsFolder': '/tmp/tf', 'proposedProjectsFolder': null},
    );
    final covers = tester.widgetList<TfSongCover>(find.byType(TfSongCover)).toList();
    expect(covers, hasLength(2));
    expect(covers[0].image, isA<FileImage>());
    expect((covers[0].image! as FileImage).file.path, '/tmp/tf/Con portada/source/cover.jpg');
    expect(covers[1].image, isNull);
  });

  testWidgets('nada antes de loaded', (tester) async {
    await _pump(tester, const LibraryScreen(), load: false);
    expect(find.byType(SongTable), findsNothing);
    expect(find.byType(LibraryEmpty), findsNothing);
  });

  testWidgets('tabla: columnas 70/150/170, tomas, chips y artista', (tester) async {
    await _pump(tester, const LibraryScreen());
    expect(find.byType(SongRow), findsNWidgets(5));
    expect(find.text('TEMA / ARTISTA'), findsOneWidget);
    expect(find.text('Hysteria'), findsOneWidget);
    expect(find.text('Muse'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(4));
    expect(find.text('3'), findsOneWidget);
    expect(find.text('En cola'), findsOneWidget);
    expect(find.text('Separado'), findsOneWidget);
    expect(find.text('Separando 0 %'), findsOneWidget);
    expect(find.text('Error'), findsOneWidget);
    expect(find.text('Importado'), findsOneWidget);
    final kinds = tester.widgetList<TfChip>(find.byType(TfChip)).map((c) => c.kind).toSet();
    expect(kinds, {TfChipKind.ok, TfChipKind.working, TfChipKind.neutral, TfChipKind.error});
    final gap = tester.getRect(find.text('ESTADO')).left - tester.getRect(find.text('TOMAS')).left;
    expect(gap, SongColumns.takes);
    final table = tester.getRect(find.byType(SongTable));
    expect(table.right - tester.getRect(find.text('ESTADO')).left - TfSpace.s20, SongColumns.state + SongColumns.actions);
  });

  testWidgets('showArtist:false oculta el artista', (tester) async {
    await _pump(
      tester,
      Consumer(
        builder: (c, ref, _) =>
            SongTable(tracks: ref.watch(libraryStoreProvider).entries, showArtist: false),
      ),
    );
    expect(find.text('Enter Sandman'), findsOneWidget);
    expect(find.text('Metallica'), findsNothing);
  });

  testWidgets('seleccionar una fila actualiza selectedProjectProvider', (tester) async {
    await _pump(tester, const LibraryScreen());
    await tester.tap(find.text('Hysteria'));
    await tester.pump();
    expect(_c.read(selectedProjectProvider), '3');
    final row = tester.widgetList<TfListRow>(find.byType(TfListRow)).firstWhere((r) => r.selected);
    expect(row.selected, isTrue);
  });

  testWidgets('vacío tras loaded y sin resultados', (tester) async {
    await _pump(tester, const LibraryScreen(), projects: <Json>[]);
    expect(find.text('Todavía no hay temas'), findsOneWidget);
  });

  testWidgets('sin resultados de búsqueda', (tester) async {
    await _pump(tester, const LibraryScreen());
    _c.read(libraryStoreProvider.notifier).setQuery('zzz');
    await tester.pump();
    expect(find.text('Ningún tema coincide con «zzz»'), findsOneWidget);
    expect(find.byType(SongTable), findsNothing);
  });

  testWidgets('fila de importación', (tester) async {
    const job = JobInfo(id: 'import-1', title: 'riff.wav', stage: JobStage.importStage, state: JobState.running, text: '', fraction: 0.4);
    await _pump(tester, const ImportingRow(job: job));
    expect(find.text('riff.wav'), findsOneWidget);
    expect(find.text('Importando 40 %'), findsOneWidget);
  });

  testWidgets('indicador: oculto sin lista y texto traducido por paso', (tester) async {
    await _pump(tester, const PlaylistIndicator());
    expect(find.byType(Text), findsNothing);
    await _emitPlaylist(tester, 'searching', 'crudo');
    expect(find.text('crudo'), findsNothing);
    expect(find.textContaining('Buscando'), findsOneWidget);
    await _emitPlaylist(tester, 'running', 'crudo');
    expect(find.textContaining('Importando'), findsOneWidget);
    await _emitPlaylist(tester, 'stopped', 'crudo');
    expect(find.text('Importación detenida'), findsOneWidget);
  });

  testWidgets('golden lista con temas', (tester) async {
    await _pump(tester, const LibraryScreen());
    await expectLater(find.byKey(k5Boundary), matchesGoldenFile('goldens/library_list.png'));
  });

  testWidgets('golden lista vacía', (tester) async {
    await _pump(tester, const LibraryScreen(), projects: <Json>[]);
    await expectLater(find.byKey(k5Boundary), matchesGoldenFile('goldens/library_list_empty.png'));
  });
}
