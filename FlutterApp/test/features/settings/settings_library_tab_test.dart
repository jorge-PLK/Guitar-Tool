import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/library_storage.dart';
import 'package:toneforge/contract/models.dart';
import 'package:toneforge/contract/tools.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/features/settings/settings_library_store.dart';
import 'package:toneforge/features/settings/settings_library_tab.dart';
import 'package:toneforge/features/settings/settings_models_store.dart';
import 'package:toneforge/features/settings/settings_tools_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/locale_pref.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_dropdown.dart';

import '../../support/harness.dart';

class _FakeLibrary extends SettingsLibraryStore {
  _FakeLibrary(this.initial, {this.chosen, this.failure});

  final SettingsLibraryState initial;
  final String? chosen;
  final CoreError? failure;
  final List<(String, RelocateMode)> relocated = [];

  @override
  SettingsLibraryState build() => initial;

  @override
  Future<String?> chooseFolder() async => chosen;

  @override
  Future<CoreError?> relocate(String path, RelocateMode mode) async {
    relocated.add((path, mode));
    return failure;
  }
}

class _FakeModels extends SettingsModelsStore {
  _FakeModels(this.initial);

  final SettingsModelsState initial;
  final List<String> deleted = [];

  @override
  SettingsModelsState build() => initial;

  @override
  Future<CoreError?> delete(String id) async {
    deleted.add(id);
    return null;
  }
}

class _FakeTools extends SettingsToolsStore {
  @override
  SettingsToolsState build() => const SettingsToolsState(
    info: ToolsInfoResult(
      ytDlpVersion: '2026.03.17',
      ytDlpOrigin: YtDlpOrigin.embedded,
      denoVersion: '2.1.4',
      ffmpegVersion: '7.1',
    ),
  );
}

class _MemoryLocalePrefs implements LocalePrefStore {
  LocaleChoice? saved;

  @override
  Future<LocaleChoice?> read() async => saved;

  @override
  Future<void> write(LocaleChoice choice) async => saved = choice;
}

const _usage = UsageResult(totalBytes: 2400000000, regenerableBytes: 800000000, projects: []);

const _loaded = SettingsLibraryState(
  projectsFolder: '/Users/jorge/Music/ToneForge/Proyectos',
  usage: _usage,
  loaded: true,
);

const _installed = ModelEntry(
  id: 'demucs',
  name: 'Demucs',
  stateRaw: 'installed',
  archiveBytes: 300000000,
  bytes: 320000000,
  sourceRaw: 'store',
);

const _pending = ModelEntry(id: 'basic', name: 'Basic Pitch', stateRaw: 'notInstalled', archiveBytes: 20000000);

SettingsModelsState _models(List<ModelEntry> m) => SettingsModelsState(models: m, loaded: true);

final _both = _models([_installed, _pending]);

class _Ctx {
  _Ctx(this.container, this.library, this.models, this.prefs);

  final _MemoryLocalePrefs prefs;
  final ProviderContainer container;
  final _FakeLibrary library;
  final _FakeModels models;
}

Future<_Ctx> _pump(
  WidgetTester tester, {
  SettingsLibraryState library = _loaded,
  SettingsModelsState? models,
  String? chosen,
  CoreError? failure,
  String systemLocale = 'es',
}) async {
  await tester.runAsync(loadTfFonts);
  final prefs = _MemoryLocalePrefs();
  setTestSurface(tester, const Size(1200, 1500));
  final lib = _FakeLibrary(library, chosen: chosen, failure: failure);
  final mod = _FakeModels(models ?? _both);
  final c = ProviderContainer(
    overrides: [
      settingsLibraryStoreProvider.overrideWith(() => lib),
      settingsModelsStoreProvider.overrideWith(() => mod),
      settingsToolsStoreProvider.overrideWith(_FakeTools.new),
      localePrefStoreProvider.overrideWithValue(prefs),
    ],
  );
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: Consumer(
        builder: (context, ref, _) {
          final choice = ref.watch(localeChoiceProvider);
          return WidgetsApp(
            color: TfColors.bg,
            debugShowCheckedModeBanner: false,
            locale: switch (choice) {
              LocaleChoice.system => Locale(systemLocale),
              LocaleChoice.es => const Locale('es'),
              LocaleChoice.en => const Locale('en'),
            },
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
                  child: const Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: TfSpace.s40, vertical: TfSpace.s32),
                      child: SettingsLibraryTab(),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return _Ctx(c, lib, mod, prefs);
}

AppLocalizations _l(WidgetTester tester) => AppLocalizations.of(tester.element(find.byType(SettingsLibraryTab)));

final _dropdown = find.byType(TfDropdown<LocaleChoice>);
final _shownLabel = find.descendant(of: _dropdown, matching: find.byType(Text)).last;

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('base: grupos en orden y golden', (tester) async {
    await _pump(tester);
    final l = _l(tester);
    final ys = [
      for (final t in [l.settings_lib_title, l.settings_models_title, l.settings_tools_title, l.settings_lang_title])
        tester.getTopLeft(find.text(t).first).dy,
    ];
    expect([...ys]..sort(), ys);
    expect(find.text('/Users/jorge/Music/ToneForge/Proyectos'), findsOneWidget);
    await expectLater(find.byKey(k5Boundary), matchesGoldenFile('goldens/settings_library.png'));
  });

  testWidgets('move al 40 %: barra y «Cambiar carpeta» deshabilitado', (tester) async {
    final c = await _pump(
      tester,
      library: _loaded.copyWith(relocating: true, relocateMode: RelocateMode.move, relocateFraction: 0.4),
    );
    final l = _l(tester);
    expect(find.text(l.settings_lib_change), findsOneWidget);
    await tester.tap(find.text(l.settings_lib_change));
    await _settle(tester);
    expect(find.text(l.settings_lib_moveHere), findsNothing);
    expect(c.library.relocated, isEmpty);
    await expectLater(find.byKey(k5Boundary), matchesGoldenFile('goldens/settings_library_moving.png'));
  });

  testWidgets('point: sin barra de progreso', (tester) async {
    final move = await _pump(
      tester,
      library: _loaded.copyWith(relocating: true, relocateMode: RelocateMode.move, relocateFraction: 0.4),
    );
    final withBar = tester.getSize(find.byKey(k5Boundary));
    final moveTop = tester.getTopLeft(find.text(_l(tester).settings_models_title)).dy;
    expect(move.library.initial.showRelocateProgress, isTrue);
    await _pump(tester, library: _loaded.copyWith(relocating: true, relocateMode: RelocateMode.point));
    expect(tester.getSize(find.byKey(k5Boundary)), withBar);
    expect(tester.getTopLeft(find.text(_l(tester).settings_models_title)).dy, lessThan(moveTop));
  });

  testWidgets('diálogo de carpeta: tres botones; mover llama a relocate', (tester) async {
    final c = await _pump(tester, chosen: '/nueva/ruta');
    final l = _l(tester);
    await tester.tap(find.text(l.settings_lib_change));
    await _settle(tester);
    expect(find.text(l.settings_lib_moveHere), findsOneWidget);
    expect(find.text(l.settings_lib_pointOnly), findsOneWidget);
    expect(find.text(l.settings_lib_cancel), findsOneWidget);
    await tester.tap(find.text(l.settings_lib_moveHere));
    await _settle(tester);
    expect(c.library.relocated, [('/nueva/ruta', RelocateMode.move)]);
  });

  testWidgets('diálogo de carpeta: cancelar no relocaliza', (tester) async {
    final c = await _pump(tester, chosen: '/nueva/ruta');
    final l = _l(tester);
    await tester.tap(find.text(l.settings_lib_change));
    await _settle(tester);
    await tester.tap(find.text(l.settings_lib_cancel));
    await _settle(tester);
    expect(find.text(l.settings_lib_moveHere), findsNothing);
    expect(c.library.relocated, isEmpty);
  });

  testWidgets('work-in-progress: aviso propio', (tester) async {
    await _pump(tester, chosen: '/n', failure: const CoreError('work-in-progress', 'busy'));
    final l = _l(tester);
    await tester.tap(find.text(l.settings_lib_change));
    await _settle(tester);
    await tester.tap(find.text(l.settings_lib_pointOnly));
    await _settle(tester);
    expect(find.text(l.settings_lib_workInProgress), findsOneWidget);
    expect(find.text(l.library_noticeOk), findsOneWidget);
  });

  testWidgets('modelo instalado: Borrar pide confirmación y borra', (tester) async {
    final c = await _pump(tester);
    final l = _l(tester);
    await tester.tap(find.text(l.settings_models_delete));
    await _settle(tester);
    expect(find.text(l.settings_models_deleteTitle), findsOneWidget);
    expect(c.models.deleted, isEmpty);
    await tester.tap(find.text(l.settings_models_delete).last);
    await _settle(tester);
    expect(c.models.deleted, ['demucs']);
  });

  testWidgets('modelo instalado: cancelar la confirmación no borra', (tester) async {
    final c = await _pump(tester);
    final l = _l(tester);
    await tester.tap(find.text(l.settings_models_delete));
    await _settle(tester);
    await tester.tap(find.text(l.settings_lib_cancel));
    await _settle(tester);
    expect(c.models.deleted, isEmpty);
  });

  testWidgets('modelo descargando: porcentaje, barra y golden', (tester) async {
    await _pump(
      tester,
      models: _models([
        _installed,
        const ModelEntry(
          id: 'basic',
          name: 'Basic Pitch',
          stateRaw: 'downloading',
          archiveBytes: 20000000,
          fraction: 0.4,
        ),
      ]),
    );
    final l = _l(tester);
    expect(find.text(l.settings_models_downloading('40 %')), findsOneWidget);
    expect(find.text(l.settings_models_download), findsNothing);
    await expectLater(
      find.byKey(k5Boundary),
      matchesGoldenFile('goldens/settings_library_model_downloading.png'),
    );
  });

  testWidgets('modelo con fallo: estado de error y «Descargar»', (tester) async {
    await _pump(
      tester,
      models: _models([
        _installed,
        const ModelEntry(
          id: 'basic',
          name: 'Basic Pitch',
          stateRaw: 'failed',
          archiveBytes: 20000000,
          message: 'sin red',
        ),
      ]),
    );
    final l = _l(tester);
    expect(find.text(l.settings_models_error), findsOneWidget);
    expect(find.text(l.settings_models_download), findsOneWidget);
  });

  testWidgets('English cambia el idioma al momento', (tester) async {
    final c = await _pump(tester);
    expect(c.container.read(localeChoiceProvider), LocaleChoice.system);
    await tester.tap(_dropdown);
    await _settle(tester);
    await tester.tap(find.text('English').last);
    await _settle(tester);
    expect(c.container.read(localeChoiceProvider), LocaleChoice.en);
    expect(_l(tester).localeName, 'en');
    await expectLater(find.byKey(k5Boundary), matchesGoldenFile('goldens/settings_library_language_en.png'));
  });

  testWidgets('idioma: sin override y sistema en inglés, el desplegable muestra English', (tester) async {
    final c = await _pump(tester, systemLocale: 'en');
    expect(c.container.read(localeChoiceProvider), LocaleChoice.system);
    expect(tester.widget<Text>(_shownLabel).data, 'English');
  });

  testWidgets('idioma: elegir Español guarda LocaleChoice.es aunque coincida con el sistema', (tester) async {
    final c = await _pump(tester);
    await tester.tap(_dropdown);
    await _settle(tester);
    await tester.tap(find.text('Español').last);
    await _settle(tester);
    expect(c.container.read(localeChoiceProvider), LocaleChoice.es);
    expect(c.prefs.saved, LocaleChoice.es);
  });
}
