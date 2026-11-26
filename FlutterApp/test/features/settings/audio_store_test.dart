import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/audio.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/settings/audio_store.dart';
import 'package:toneforge/shell/shell_providers.dart';
import 'package:toneforge/shell/shell_route.dart';

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<({MockCore core, ProviderContainer c})> setup({String screen = 'settings-audio'}) async {
  final src = await DirectoryFixtureSource.find();
  final core = await MockCore.load(src!);
  final c = ProviderContainer(overrides: [
    coreClientProvider.overrideWithValue(core),
    launchOptionsProvider.overrideWithValue(LaunchOptions(screen: screen)),
  ]);
  addTearDown(c.dispose);
  c.listen(audioStoreProvider, (_, _) {});
  await settle();
  return (core: core, c: c);
}

List<MockCall> callsOf(MockCore core, String m) => [for (final k in core.calls) if (k.method == m) k];

void main() {
  test('al entrar carga settings, devices y state y enciende los medidores', () async {
    final t = await setup();
    final s = t.c.read(audioStoreProvider);
    expect(s.settings, isNotNull);
    expect(s.devices, isNotNull);
    expect(s.audioState, isNotNull);
    expect(s.loading, isFalse);
    expect((callsOf(t.core, 'audio.setMeters').single.params as Map)['visible'], true);
  });

  test('audio.setMeters false al salir de la pestaña, true al volver y false al salir de Ajustes', () async {
    final t = await setup();
    t.c.read(settingsTabProvider.notifier).select(SettingsTab.video);
    await settle();
    t.c.read(settingsTabProvider.notifier).select(SettingsTab.audio);
    await settle();
    t.c.read(shellRouteProvider.notifier).select(ShellRoute.record);
    await settle();
    final v = [for (final k in callsOf(t.core, 'audio.setMeters')) (k.params as Map)['visible']];
    expect(v, [true, false, true, false]);
  });

  test('fuera de la pestaña Audio no llama al núcleo', () async {
    final t = await setup(screen: 'settings-library');
    expect(t.core.calls, isEmpty);
  });

  test('setSettings envía null explícito para salida y entrada, y solo lo que cambia', () async {
    final t = await setup();
    final n = t.c.read(audioStoreProvider.notifier);
    await n.setOutput(null);
    await n.setInput(null);
    await n.setGuitarIn([1]);
    await n.setOutput('abc');
    await n.setBackingOut(2, 3);
    await n.setWorkingSampleRate(44100);
    final p = [for (final k in callsOf(t.core, 'audio.setSettings')) k.params as Map];
    expect(p[0], {'outputDeviceUID': null});
    expect(p[0].containsKey('inputDeviceUID'), isFalse);
    expect(p[1], {'inputDeviceUID': null});
    expect(p[2], {'guitarIn': [1]});
    expect(p[3], {'outputDeviceUID': 'abc'});
    expect(p[4], {'backingOut': {'left': 2, 'right': 3}});
    expect(p[5], {'workingSampleRate': 44100});
    expect(t.c.read(audioStoreProvider).settings, isNotNull);
  });

  test('setSettings con error bad-params deja el error y conserva los ajustes', () async {
    final t = await setup();
    final before = t.c.read(audioStoreProvider).settings;
    t.core.failWith('audio.setSettings', const CoreError('bad-params', 'frecuencia'));
    await t.c.read(audioStoreProvider.notifier).setWorkingSampleRate(12345);
    final s = t.c.read(audioStoreProvider);
    expect(s.error?.code, 'bad-params');
    expect(s.settings, same(before));
    t.c.read(audioStoreProvider.notifier).clearError();
    expect(t.c.read(audioStoreProvider).error, isNull);
  });

  test('useDeviceRate usa la frecuencia del dispositivo solo si se permite', () async {
    final t = await setup();
    // Sin desajuste en el fixture por defecto: no llama.
    await t.c.read(audioStoreProvider.notifier).useDeviceRate();
    expect(callsOf(t.core, 'audio.setSettings'), isEmpty);
  });

  test('eventos: audio.levels, audio.state y audio.devicesChanged', () async {
    final t = await setup();
    t.core.emitFixture('audio.levels');
    await settle();
    expect(t.c.read(audioStoreProvider).levels?.levels, isNotEmpty);
    t.core.emit('audio.levels', {'levels': <double>[], 'rmsDB': <double>[], 'peakDB': <double>[]});
    await settle();
    expect(t.c.read(audioStoreProvider).levels?.levels, isEmpty);
    final nSettings = callsOf(t.core, 'audio.settings').length;
    t.core.emitFixture('audio.state');
    await settle();
    expect(callsOf(t.core, 'audio.settings').length, nSettings + 1);
    t.core.emitFixture('audio.devicesChanged');
    await settle();
    expect(callsOf(t.core, 'audio.settings').length, nSettings + 2);
    expect(t.c.read(audioStoreProvider).devices, isNotNull);
  });

  test('expone los contadores de canales y los vuelve a leer en devicesChanged', () async {
    final t = await setup();
    var s = t.c.read(audioStoreProvider).settings!;
    expect((s.outputChannelCount, s.inputChannelCount), (2, 2));
    final j = s.toJson()
      ..['outputChannelCount'] = 0
      ..['inputChannelCount'] = 0
      ..['backingChoices'] = <Object?>[]
      ..['guitarChoices'] = <Object?>[];
    t.core.result('audio.settings', j);
    t.core.emitFixture('audio.devicesChanged');
    await settle();
    s = t.c.read(audioStoreProvider).settings!;
    expect((s.outputChannelCount, s.inputChannelCount), (0, 0));
    expect(s.backingChoices, isEmpty);
  });

  test('al salir de la pestaña se vacían los medidores', () async {
    final t = await setup();
    t.core.emitFixture('audio.levels');
    await settle();
    t.c.read(settingsTabProvider.notifier).select(SettingsTab.library);
    await settle();
    expect(t.c.read(audioStoreProvider).levels, isNull);
  });

  test('calibrate se resuelve con eventos audio.calibration sin duplicar estado', () async {
    final t = await setup();
    t.core.handle('audio.calibrate', (_) {
      return {'phase': 'finished', 'outcome': 'error', 'error': 'respuesta'};
    });
    final seen = <CalibrationPhase?>[];
    t.c.listen(audioStoreProvider, (p, n) {
      if (p?.calibration != n.calibration) seen.add(n.calibration?.phase);
    });
    final f = t.c.read(audioStoreProvider.notifier).calibrate();
    // el mismo estado final llega por evento y por respuesta
    t.core.emit('audio.calibration',
        {'phase': 'finished', 'outcome': 'error', 'error': 'respuesta'});
    await f;
    await settle();
    final s = t.c.read(audioStoreProvider);
    expect(s.calibrating, isFalse);
    expect(s.calibration?.error, 'respuesta');
    expect(callsOf(t.core, 'audio.calibrate'), hasLength(1));
    // Un evento posterior manda sobre lo anterior.
    t.core.emit('audio.calibration', {'phase': 'idle'});
    await settle();
    expect(t.c.read(audioStoreProvider).calibration?.phase, CalibrationPhase.idle);
    expect(seen.last, CalibrationPhase.idle);
  });

  test('calibrate aplica la respuesta si no llegó ningún evento', () async {
    final t = await setup();
    await t.c.read(audioStoreProvider.notifier).calibrate();
    final s = t.c.read(audioStoreProvider);
    expect(s.calibration?.outcome, CalibrationOutcome.success);
    expect(s.calibration?.success?.rows, isNotEmpty);
  });

  test('calibración fallida y con error llegan por evento', () async {
    final t = await setup();
    t.core.emit('audio.calibration', {'phase': 'finished', 'outcome': 'failure', 'failure': {'reason': 'noSignal', 'spreadMS': 0, 'title': 't', 'hint': 'h'}});
    await settle();
    expect(t.c.read(audioStoreProvider).calibration?.failure?.reason, CalibrationFailureReason.noSignal);
    t.core.emit('audio.calibration', {'phase': 'finished', 'outcome': 'error', 'error': 'x'});
    await settle();
    expect(t.c.read(audioStoreProvider).calibration?.error, isNotNull);
  });

  test('calibrate con error RPC (timeout) deja el error y libera calibrating', () async {
    final t = await setup();
    t.core.failWith('audio.calibrate', const CoreError('timeout', 'Sin respuesta'));
    await t.c.read(audioStoreProvider.notifier).calibrate();
    final s = t.c.read(audioStoreProvider);
    expect(s.error?.code, 'timeout');
    expect(s.calibrating, isFalse);
  });

  test('cerrar la hoja: cancel si mide, dismiss si no', () async {
    final t = await setup();
    final n = t.c.read(audioStoreProvider.notifier);
    t.core.emit('audio.calibration', {'phase': 'running', 'progress': 0.4});
    await settle();
    await n.closeCalibration();
    expect(callsOf(t.core, 'audio.cancelCalibration'), hasLength(1));
    expect(callsOf(t.core, 'audio.dismissCalibration'), isEmpty);
    t.core.emit('audio.calibration', {'phase': 'finished', 'outcome': 'error', 'error': 'x'});
    await settle();
    await n.closeCalibration();
    expect(callsOf(t.core, 'audio.dismissCalibration'), hasLength(1));
  });

  test('un error RPC al cargar queda en error y no rompe el resto', () async {
    final src = await DirectoryFixtureSource.find();
    final core = await MockCore.load(src!);
    core.failWith('audio.devices', const CoreError('internal', 'fallo'));
    final c = ProviderContainer(overrides: [
      coreClientProvider.overrideWithValue(core),
      launchOptionsProvider.overrideWithValue(const LaunchOptions(screen: 'settings-audio')),
    ]);
    addTearDown(c.dispose);
    c.listen(audioStoreProvider, (_, _) {});
    await settle();
    final s = c.read(audioStoreProvider);
    expect(s.error?.code, 'internal');
    expect(s.settings, isNotNull);
    expect(s.devices, isNull);
  });
}
