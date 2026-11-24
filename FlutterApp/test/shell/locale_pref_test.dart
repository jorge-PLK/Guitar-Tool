import 'dart:ui' show Size;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/app.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/shell/locale_pref.dart';

import '../support/harness.dart';

class _MemoryStore implements LocalePrefStore {
  _MemoryStore([this.value]);
  LocaleChoice? value;
  int writes = 0;

  @override
  Future<LocaleChoice?> read() async => value;

  @override
  Future<void> write(LocaleChoice choice) async {
    value = choice;
    writes++;
  }
}

class _ThrowingStore implements LocalePrefStore {
  int reads = 0;

  @override
  Future<LocaleChoice?> read() async {
    reads++;
    throw StateError('sin almacén');
  }

  @override
  Future<void> write(LocaleChoice choice) async {}
}

ProviderContainer _container(_MemoryStore store, {String? locale}) {
  final c = ProviderContainer(
    overrides: [
      launchOptionsProvider.overrideWithValue(LaunchOptions(mock: true, locale: locale)),
      localePrefStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('sin nada guardado -> system', () async {
    final c = _container(_MemoryStore());
    expect(c.read(localeChoiceProvider), LocaleChoice.system);
    await _settle();
    expect(c.read(localeChoiceProvider), LocaleChoice.system);
  });

  test('guardado en -> en', () async {
    final c = _container(_MemoryStore(LocaleChoice.en));
    c.listen(localeChoiceProvider, (_, _) {});
    await _settle();
    expect(c.read(localeChoiceProvider), LocaleChoice.en);
  });

  test('--locale gana a lo guardado y no se persiste', () async {
    final store = _MemoryStore(LocaleChoice.en);
    final c = _container(store, locale: 'es');
    c.listen(localeChoiceProvider, (_, _) {});
    await _settle();
    expect(c.read(localeChoiceProvider), LocaleChoice.es);
    expect(store.value, LocaleChoice.en);
    expect(store.writes, 0);
  });

  test('precargado en main -> sale ya en el primer valor sin leer el almacén', () async {
    final store = _ThrowingStore();
    final c = ProviderContainer(
      overrides: [
        launchOptionsProvider.overrideWithValue(const LaunchOptions(mock: true)),
        localePrefStoreProvider.overrideWithValue(store),
        preloadedLocaleChoiceProvider.overrideWithValue(LocaleChoice.en),
      ],
    );
    addTearDown(c.dispose);
    expect(c.read(localeChoiceProvider), LocaleChoice.en);
    await _settle();
    expect(c.read(localeChoiceProvider), LocaleChoice.en);
    expect(store.reads, 0);
  });

  test('readSavedLocaleChoice no lanza si el almacén falla', () async {
    expect(await readSavedLocaleChoice(_ThrowingStore()), isNull);
    expect(await readSavedLocaleChoice(_MemoryStore(LocaleChoice.es)), LocaleChoice.es);
  });

  test('set persiste y actualiza', () async {
    final store = _MemoryStore();
    final c = _container(store);
    await c.read(localeChoiceProvider.notifier).set(LocaleChoice.en);
    expect(c.read(localeChoiceProvider), LocaleChoice.en);
    expect(store.value, LocaleChoice.en);
  });

  testWidgets('set(en) cambia el idioma de la app al momento', (tester) async {
    await tester.runAsync(loadTfFonts);
    final MockCore? core = await tester.runAsync(() async => MockCore.load((await DirectoryFixtureSource.find())!));
    setTestSurface(tester, const Size(1440, 900));
    final store = _MemoryStore(LocaleChoice.es);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          launchOptionsProvider.overrideWithValue(const LaunchOptions(mock: true)),
          coreClientProvider.overrideWithValue(core!),
          localePrefStoreProvider.overrideWithValue(store),
        ],
        child: const ToneForgeApp(),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Biblioteca'), findsWidgets);
    final c = ProviderScope.containerOf(tester.element(find.byType(ToneForgeApp)));
    await c.read(localeChoiceProvider.notifier).set(LocaleChoice.en);
    await tester.pump();
    await tester.pump();
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Biblioteca'), findsNothing);
    expect(store.value, LocaleChoice.en);
  });
}
