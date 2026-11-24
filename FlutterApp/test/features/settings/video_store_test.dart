import 'dart:convert';

import 'package:flutter/painting.dart' show Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/video.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/settings/video_store.dart';
import 'package:toneforge/shell/shell_providers.dart';
import 'package:toneforge/shell/shell_route.dart';

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<({MockCore core, ProviderContainer c})> setup({String screen = 'settings-video'}) async {
  final src = await DirectoryFixtureSource.find();
  final core = await MockCore.load(src!);
  core.result('video.preview.start',
      jsonDecodeMap(await src.read('video/video.preview.start.live.result.json')));
  final c = ProviderContainer(overrides: [
    coreClientProvider.overrideWithValue(core),
    launchOptionsProvider.overrideWithValue(LaunchOptions(screen: screen)),
  ]);
  addTearDown(c.dispose);
  c.listen(videoStoreProvider, (_, _) {});
  await settle();
  return (core: core, c: c);
}

List<MockCall> callsOf(MockCore core, String m) => [for (final k in core.calls) if (k.method == m) k];

void main() {
  test('al entrar carga cámaras y ajustes y arranca la previa', () async {
    final t = await setup();
    final s = t.c.read(videoStoreProvider);
    expect(s.cameras, isNotNull);
    expect(s.settings, isNotNull);
    expect(s.preview?.state, PreviewState.live);
    expect(s.frameSize, const Size(1920, 1080));
    expect(callsOf(t.core, 'video.preview.start'), hasLength(1));
  });

  test('preview.stop al salir de la pestaña y start al volver; stop al salir de Ajustes', () async {
    final t = await setup();
    t.c.read(settingsTabProvider.notifier).select(SettingsTab.audio);
    await settle();
    expect(callsOf(t.core, 'video.preview.stop'), hasLength(1));
    expect(t.c.read(videoStoreProvider).frameSize, isNull);
    t.c.read(settingsTabProvider.notifier).select(SettingsTab.video);
    await settle();
    expect(callsOf(t.core, 'video.preview.start'), hasLength(2));
    t.c.read(shellRouteProvider.notifier).select(ShellRoute.record);
    await settle();
    expect(callsOf(t.core, 'video.preview.stop'), hasLength(2));
  });

  test('fuera de la pestaña Vídeo no llama al núcleo', () async {
    final t = await setup(screen: 'settings-audio');
    expect(t.core.calls, isEmpty);
  });

  test('setCamera envía cameraUID null explícito frente a ausente y rehace la previa', () async {
    final t = await setup();
    final n = t.c.read(videoStoreProvider.notifier);
    await n.setCamera(null);
    await n.setCamera('sim-camera');
    await n.setRotation(90);
    final p = [for (final k in callsOf(t.core, 'video.setSettings')) k.params as Map];
    expect(p[0], {'cameraUID': null});
    expect(p[1], {'cameraUID': 'sim-camera'});
    expect(p[2].containsKey('cameraUID'), isFalse);
    expect(p[2], {'rotation': {'degrees': 90}});
    // 1 al entrar + 2 por cambio de cámara; el giro no rehace la previa.
    expect(callsOf(t.core, 'video.preview.start'), hasLength(3));
  });

  test('resolución y fps envían solo lo que cambia y rehacen la previa', () async {
    final t = await setup();
    final n = t.c.read(videoStoreProvider.notifier);
    await n.setResolution(1280, 720);
    await n.setFps(60);
    await n.setOffset(12);
    final p = [for (final k in callsOf(t.core, 'video.setSettings')) k.params as Map];
    expect(p[0], {'resolution': {'width': 1280, 'height': 720}});
    expect(p[1], {'fps': 60.0});
    expect(p[2], {'offset': {'ms': 12.0}});
    expect(callsOf(t.core, 'video.preview.start'), hasLength(3));
  });

  test('setSettings con bad-params deja el error y no rehace la previa', () async {
    final t = await setup();
    t.core.failWith('video.setSettings', const CoreError('bad-params', 'resolución'));
    await t.c.read(videoStoreProvider.notifier).setResolution(1, 1);
    expect(t.c.read(videoStoreProvider).error?.code, 'bad-params');
    expect(callsOf(t.core, 'video.preview.start'), hasLength(1));
    t.c.read(videoStoreProvider.notifier).clearError();
    expect(t.c.read(videoStoreProvider).error, isNull);
  });

  test('video.camerasChanged recarga cámaras y ajustes y rehace la previa', () async {
    final t = await setup();
    t.core.emitFixture('video.camerasChanged');
    await settle();
    expect(callsOf(t.core, 'video.cameras'), hasLength(2));
    expect(callsOf(t.core, 'video.settings'), hasLength(2));
    expect(callsOf(t.core, 'video.preview.start'), hasLength(2));
  });

  test('camerasChanged fuera de la pestaña no hace nada', () async {
    final t = await setup(screen: 'settings-audio');
    t.core.emitFixture('video.camerasChanged');
    await settle();
    expect(t.core.calls, isEmpty);
  });

  test('previa denied, noCamera y failed sin frameSize', () async {
    for (final (name, st) in [
      ('denied', PreviewState.denied),
      ('nocamera', PreviewState.noCamera),
      ('failed', PreviewState.failed),
    ]) {
      final src = await DirectoryFixtureSource.find();
      final core = await MockCore.load(src!);
      final raw = await src.read('video/video.preview.start.$name.result.json');
      core.handle('video.preview.start', (_) => (jsonDecodeMap(raw)));
      final c = ProviderContainer(overrides: [
        coreClientProvider.overrideWithValue(core),
        launchOptionsProvider.overrideWithValue(const LaunchOptions(screen: 'settings-video')),
      ]);
      addTearDown(c.dispose);
      c.listen(videoStoreProvider, (_, _) {});
      await settle();
      final s = c.read(videoStoreProvider);
      expect(s.preview?.state, st);
      expect(s.frameSize, isNull);
    }
  });

  test('error RPC al cargar y openCameraPrivacy', () async {
    final src = await DirectoryFixtureSource.find();
    final core = await MockCore.load(src!);
    core.result('video.preview.start',
        jsonDecodeMap(await src.read('video/video.preview.start.live.result.json')));
    core.failWith('video.cameras', const CoreError('internal', 'fallo'));
    final c = ProviderContainer(overrides: [
      coreClientProvider.overrideWithValue(core),
      launchOptionsProvider.overrideWithValue(const LaunchOptions(screen: 'settings-video')),
    ]);
    addTearDown(c.dispose);
    c.listen(videoStoreProvider, (_, _) {});
    await settle();
    final s = c.read(videoStoreProvider);
    expect(s.error?.code, 'internal');
    expect(s.settings, isNotNull);
    await c.read(videoStoreProvider.notifier).openCameraPrivacy();
    expect(callsOf(core, 'video.openCameraPrivacy'), hasLength(1));
  });
}

Map<String, Object?> jsonDecodeMap(String raw) =>
    (jsonDecode(raw) as Map).cast<String, Object?>();
