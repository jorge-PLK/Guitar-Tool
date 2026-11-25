import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/record_state.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/record/record_camera_poll.dart';
import 'package:toneforge/features/record/record_store.dart';

Json fx(String path) =>
    (json.decode(File('../Contract/fixtures/$path.json').readAsStringSync()) as Map).cast<String, Object?>();

/// Snapshot con el estado de cámara dado (`idle` = buscando cámara). El sondeo no depende de él: es siempre en reposo.
Json withCamera(String cameraState) {
  final j = fx('record/record.open.result');
  return {...j, 'camera': {...(j['camera'] as Map).cast<String, Object?>(), 'state': cameraState}};
}

int polls(MockCore core) => core.calls.where((c) => c.method == 'record.pollCamera').length;

/// Abre Grabar con la cámara en [cameraState]; `record.pollCamera` devuelve [pollState].
Future<(MockCore, ProviderContainer)> openWith(WidgetTester t, String cameraState, {String pollState = 'live'}) async {
  final core = MockCore()
    ..result('study.open', <String, Object?>{})
    ..result('study.close', <String, Object?>{})
    ..result('record.open', withCamera(cameraState))
    ..result('record.pollCamera', withCamera(pollState))
    ..result('audio.settings', fx('audio/audio.settings.result'))
    ..result('audio.setMeters', fx('audio/audio.setMeters.result'))
    ..result('record.close', <String, Object?>{});
  final c = ProviderContainer(overrides: [coreClientProvider.overrideWithValue(core)]);
  addTearDown(c.dispose);
  c.listen(recordStoreProvider, (_, _) {});
  await c.read(recordStoreProvider.notifier).open('p1');
  return (core, c);
}

void main() {
  testWidgets('en reposo llama a record.pollCamera a los 2 s y aplica el snapshot', (t) async {
    final (core, c) = await openWith(t, 'idle');
    expect(c.read(recordStoreProvider).snapshot?.camera.state, CameraState.idle);
    await t.pump(kCameraPollInterval - const Duration(milliseconds: 1));
    expect(polls(core), 0);
    await t.pump(const Duration(milliseconds: 1));
    expect(polls(core), 1);
    expect(c.read(recordStoreProvider).snapshot?.camera.state, CameraState.live);
  });

  testWidgets('sigue sondeando con cámara live', (t) async {
    final (core, _) = await openWith(t, 'live');
    await t.pump(kCameraPollInterval);
    await t.pump(kCameraPollInterval * 2);
    expect(polls(core), 3);
  });

  testWidgets('sigue sondeando mientras la cámara siga buscando', (t) async {
    final (core, _) = await openWith(t, 'idle', pollState: 'idle');
    for (var i = 0; i < 3; i++) {
      await t.pump(kCameraPollInterval);
    }
    expect(polls(core), 3);
  });

  testWidgets('se para en close', (t) async {
    final (core, c) = await openWith(t, 'idle', pollState: 'idle');
    await c.read(recordStoreProvider.notifier).close();
    await t.pump(kCameraPollInterval * 3);
    expect(polls(core), 0);
  });

  testWidgets('no sondea fuera de reposo y se reanuda al volver', (t) async {
    final (core, c) = await openWith(t, 'live');
    core.emit('record.state', {...fx('record/record.state.recording.event')});
    await t.pump(kCameraPollInterval * 3);
    expect(polls(core), 0);
    core.emit('record.state', {...fx('record/record.state.idle.event')});
    await t.pump(kCameraPollInterval);
    expect(polls(core), 1);
    expect(c.read(recordStoreProvider).phase, RecordPhase.idle);
  });

  testWidgets('un error no lo detiene', (t) async {
    final (core, _) = await openWith(t, 'idle', pollState: 'idle');
    core.failWith('record.pollCamera', const CoreError('boom', 'fallo'));
    await t.pump(kCameraPollInterval);
    core.result('record.pollCamera', withCamera('idle'));
    await t.pump(kCameraPollInterval);
    expect(polls(core), 2);
  });

  testWidgets('el dispose del notifier cancela el temporizador', (t) async {
    final (core, c) = await openWith(t, 'idle', pollState: 'idle');
    c.dispose();
    await t.pump(kCameraPollInterval * 2);
    expect(polls(core), 0);
  });
}
