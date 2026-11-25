import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/library/library_logic.dart';
import 'package:toneforge/features/library/library_prefs.dart';
import 'package:toneforge/features/library/library_store.dart';
import 'package:toneforge/shell/selected_project.dart';

class MemoryPrefs implements LibraryPrefs {
  MemoryPrefs([Map<String, String>? initial]) : values = {...?initial};
  final Map<String, String> values;

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async => values[key] = value;
}

Json project(String id, String title, {String? artist}) => {
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

Future<(ProviderContainer, MockCore, MemoryPrefs)> setup({
  List<Json>? projects,
  Map<String, String>? prefs,
  bool keepProposal = false,
}) async {
  final core = await MockCore.load((await DirectoryFixtureSource.find())!);
  if (!keepProposal) {
    // Sin la propuesta del núcleo, la hoja de primer arranque muestra el respaldo (y el golden no cambia).
    final info = await core.call<Json>('app.info', const <String, Object?>{}, (j) => j);
    core.result('app.info', {...info}..remove('proposedProjectsFolder'));
  }
  if (projects != null) core.result('library.list', {'projects': projects, 'skipped': <Object>[]});
  final mem = MemoryPrefs(prefs);
  final c = ProviderContainer(
    overrides: [coreClientProvider.overrideWithValue(core), libraryPrefsProvider.overrideWithValue(mem)],
  );
  addTearDown(c.dispose);
  c.listen(libraryStoreProvider, (_, _) {});
  await pumpEventQueue();
  return (c, core, mem);
}

void main() {
  test('app.info.proposedProjectsFolder llega al estado; sin el campo queda null', () async {
    final (c, _, _) = await setup(keepProposal: true);
    expect(c.read(libraryStoreProvider).proposedFolder, '/<dir>/Music/ToneForge');
    final (c2, _, _) = await setup();
    expect(c2.read(libraryStoreProvider).proposedFolder, isNull);
  });

  test('la lista se ordena por título plegado y la carga marca loaded', () async {
    final (c, _, _) = await setup(
      projects: [
        project('1', 'zeta'),
        project('2', 'Árbol'),
        project('3', 'beta'),
      ],
    );
    final s = c.read(libraryStoreProvider);
    expect(s.loaded, isTrue);
    expect([for (final p in s.songs) p.title], ['Árbol', 'beta', 'zeta']);
  });

  test('antes del primer library.list no está loaded', () async {
    final core = await MockCore.load((await DirectoryFixtureSource.find())!);
    final c = ProviderContainer(overrides: [coreClientProvider.overrideWithValue(core)]);
    addTearDown(c.dispose);
    expect(c.read(libraryStoreProvider).loaded, isFalse);
  });

  test('la búsqueda ignora mayúsculas, tildes y espacios, en título y artista', () async {
    final (c, _, _) = await setup(
      projects: [
        project('1', 'Canción', artist: 'Él'),
        project('2', 'Otra', artist: 'Banda'),
      ],
    );
    final st = c.read(libraryStoreProvider.notifier);
    st.setQuery('  CANCION ');
    expect([for (final p in c.read(libraryStoreProvider).songs) p.id], ['1']);
    st.setQuery('el');
    expect([for (final p in c.read(libraryStoreProvider).songs) p.id], ['1']);
    st.setQuery('zzz');
    expect(c.read(libraryStoreProvider).noMatches, isTrue);
  });

  test('agrupación por artista: «Sin artista» al final y temas por título', () async {
    final (c, _, _) = await setup(
      projects: [
        project('1', 'Solo'),
        project('2', 'B', artist: 'Zeta'),
        project('3', 'Z', artist: 'Álamo'),
        project('4', 'A', artist: 'Zeta'),
      ],
    );
    final g = c.read(libraryStoreProvider).groups;
    expect([for (final x in g) x.name], ['Álamo', 'Zeta', '']);
    expect([for (final p in g[1].tracks) p.title], ['A', 'B']);
    expect(g.last.isUnknown, isTrue);
  });

  test('el artista abierto se cierra al cambiar de vista y si desaparece', () async {
    final (c, core, _) = await setup(
      projects: [project('1', 'A', artist: 'Uno'), project('2', 'B', artist: 'Dos')],
    );
    final st = c.read(libraryStoreProvider.notifier);
    st.openArtistGroup('Uno');
    expect(c.read(libraryStoreProvider).openArtistTracks.single.id, '1');
    await st.setGrouping(LibraryGrouping.songs);
    expect(c.read(libraryStoreProvider).openArtist, isNull);

    st.openArtistGroup('Uno');
    core.result('library.list', {'projects': [project('2', 'B', artist: 'Dos')], 'skipped': <Object>[]});
    core.emitFixture('library.changed');
    await pumpEventQueue();
    expect(c.read(libraryStoreProvider).openArtist, isNull);
  });

  test('library.changed recarga la lista', () async {
    final (c, core, _) = await setup();
    final before = core.calls.where((x) => x.method == 'library.list').length;
    core.emitFixture('library.changed');
    await pumpEventQueue();
    expect(core.calls.where((x) => x.method == 'library.list').length, before + 1);
    expect(c.read(libraryStoreProvider).entries, isNotEmpty);
  });

  test('no-projects-folder pone needsFolder', () async {
    final core = await MockCore.load((await DirectoryFixtureSource.find())!);
    core.failWith('library.list', const CoreError('no-projects-folder', 'x'));
    final c = ProviderContainer(overrides: [coreClientProvider.overrideWithValue(core)]);
    addTearDown(c.dispose);
    c.listen(libraryStoreProvider, (_, _) {});
    await pumpEventQueue();
    final s = c.read(libraryStoreProvider);
    expect(s.needsFolder, isTrue);
    expect(s.loaded, isTrue);
  });

  test('la vista se persiste; buscador y artista abierto no', () async {
    final (c, _, mem) = await setup(prefs: {libraryGroupingKey: 'artists'});
    expect(c.read(libraryStoreProvider).grouping, LibraryGrouping.artists);
    final st = c.read(libraryStoreProvider.notifier);
    st.setQuery('algo');
    st.openArtistGroup('Banda');
    await st.setGrouping(LibraryGrouping.songs);
    expect(mem.values, {libraryGroupingKey: 'songs'});
  });

  test('rename con artista vacío lo envía ausente; si falla devuelve el error y no cambia nada', () async {
    final (c, core, _) = await setup();
    final st = c.read(libraryStoreProvider.notifier);
    final before = c.read(libraryStoreProvider).entries;
    expect(await st.rename('1', 'Nuevo', '  '), isNull);
    final p = core.calls.firstWhere((x) => x.method == 'library.rename').params as Map;
    expect(p.containsKey('artist'), isFalse);

    core.failWithFixture('library.rename');
    final calls = core.calls.length;
    final err = await st.rename('1', '', 'X');
    expect(err, isA<CoreError>());
    expect(core.calls.length, calls + 1); // sin recarga
    expect(c.read(libraryStoreProvider).entries.length, before.length);
  });

  test('cancelSeparation usa jobs.cancel con el id del tema', () async {
    final (c, core, _) = await setup();
    await c.read(libraryStoreProvider.notifier).cancelSeparation('00000000-0000-0000-0000-000000000001');
    final call = core.calls.firstWhere((x) => x.method == 'jobs.cancel');
    expect(call.params, {'id': '00000000-0000-0000-0000-000000000001'});
  });

  test('cleanup con y sin id', () async {
    final (c, core, _) = await setup();
    final st = c.read(libraryStoreProvider.notifier);
    expect(await st.cleanupInfo(), isA<int>());
    await st.cleanup(id: 'x');
    expect(core.calls.where((x) => x.method.startsWith('library.cleanup')).length, 2);
    expect((core.calls.firstWhere((x) => x.method == 'library.cleanupInfo').params as Map)['id'], isNull);
  });

  test('trashContent junta stems y tomas de la lista con los vídeos de library.project', () async {
    final (c, core, _) = await setup();
    core.handle('library.project', (_) => {...project('00000000-0000-0000-0000-000000000005', 'Delta'), 'stems': <Object>[], 'parts': <Object>[], 'videoCount': 3});
    final t = await c.read(libraryStoreProvider.notifier).trashContent('00000000-0000-0000-0000-000000000005');
    expect((t.stems, t.takes, t.videos), (2, 4, 3));
  });

  test('borrar el tema seleccionado limpia la selección; también si su id desaparece', () async {
    final (c, core, _) = await setup();
    c.listen(selectedProjectProvider, (_, _) {});
    final sel = c.read(selectedProjectProvider.notifier);
    sel.select('00000000-0000-0000-0000-000000000002');
    expect(await c.read(libraryStoreProvider.notifier).trash('00000000-0000-0000-0000-000000000002'), isNull);
    expect(c.read(selectedProjectProvider), isNull);

    sel.select('00000000-0000-0000-0000-000000000001');
    core.result('library.list', {'projects': [project('9', 'Otro')], 'skipped': <Object>[]});
    core.emitFixture('library.changed');
    await pumpEventQueue();
    expect(c.read(selectedProjectProvider), isNull);
  });

  test('trash con error no toca la selección y devuelve el error', () async {
    final (c, core, _) = await setup();
    c.listen(selectedProjectProvider, (_, _) {});
    c.read(selectedProjectProvider.notifier).select('00000000-0000-0000-0000-000000000002');
    core.failWithFixture('library.trash');
    expect(await c.read(libraryStoreProvider.notifier).trash('00000000-0000-0000-0000-000000000002'), isNotNull);
    expect(c.read(selectedProjectProvider), '00000000-0000-0000-0000-000000000002');
  });

  test('artistPhoto cachea por nombre plegado, también los null', () async {
    final (c, core, _) = await setup();
    final st = c.read(libraryStoreProvider.notifier);
    core.result('library.artistPhoto', {'photo': null});
    expect(await st.artistPhoto('Béla'), isNull);
    expect(await st.artistPhoto(' bela '), isNull);
    expect(await st.artistPhoto(''), isNull);
    expect(core.calls.where((x) => x.method == 'library.artistPhoto').length, 1);
  });
}
