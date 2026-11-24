import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/shell/selected_project.dart';

const _id = '11111111-2222-3333-4444-555555555555';
const _other = '99999999-2222-3333-4444-555555555555';

MockCore _core() => MockCore()
  ..result('library.list', {
    'projects': [
      {'id': _other, 'title': 'Otro', 'folderName': 'otro'},
      {'id': _id, 'title': 'Tema Uno', 'folderName': 'tema-uno'},
    ],
    'skipped': <Object?>[],
  });

ProviderContainer _container(MockCore core, {String? project}) {
  final c = ProviderContainer(overrides: [
    coreClientProvider.overrideWithValue(core),
    launchOptionsProvider.overrideWithValue(LaunchOptions(project: project)),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<void> _settle(ProviderContainer c) async {
  c.read(selectedProjectProvider);
  await c.read(launchProjectIdProvider.future);
}

void main() {
  test('sin --project empieza en null y no llama al núcleo', () async {
    final core = _core();
    final c = _container(core);
    await _settle(c);
    expect(c.read(selectedProjectProvider), isNull);
    expect(core.calls, isEmpty);
  });

  test('--project por folderName se siembra con el id', () async {
    final c = _container(_core(), project: 'tema-uno');
    await _settle(c);
    expect(c.read(selectedProjectProvider), _id);
  });

  test('--project por título o por id también resuelve', () async {
    final c1 = _container(_core(), project: 'Tema Uno');
    await _settle(c1);
    expect(c1.read(selectedProjectProvider), _id);
    final c2 = _container(_core(), project: _other);
    await _settle(c2);
    expect(c2.read(selectedProjectProvider), _other);
  });

  test('--project desconocido o library.list con error deja null', () async {
    final c1 = _container(_core(), project: 'nada');
    await _settle(c1);
    expect(c1.read(selectedProjectProvider), isNull);

    final c2 = _container(MockCore(), project: 'tema-uno');
    await _settle(c2);
    expect(c2.read(selectedProjectProvider), isNull);
  });

  test('select cambia el valor y una elección previa no la pisa la siembra', () async {
    final c = _container(_core(), project: 'tema-uno');
    c.read(selectedProjectProvider.notifier).select(_other);
    await _settle(c);
    expect(c.read(selectedProjectProvider), _other);
    c.read(selectedProjectProvider.notifier).select(null);
    expect(c.read(selectedProjectProvider), isNull);
  });
}
