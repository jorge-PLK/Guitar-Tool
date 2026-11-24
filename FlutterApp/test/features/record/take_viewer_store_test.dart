import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/frame_channel.dart';
import 'package:toneforge/core/frame_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/record/take_viewer_store.dart';

Json fx(String path) =>
    (json.decode(File('../Contract/fixtures/$path.json').readAsStringSync()) as Map).cast<String, Object?>();

const takeId = '00000000-0000-0000-0000-000000000002';

class Rig {
  Rig(this.core, this.c, this.created, this.disposed);
  final MockCore core;
  final ProviderContainer c;
  final List<int> created;
  final List<int> disposed;
  TakeViewerState get s => c.read(takeViewerStoreProvider);
  TakeViewerStore get store => c.read(takeViewerStoreProvider.notifier);
  int count(String m) => core.calls.where((x) => x.method == m).length;
}

Json snap(String name, [Json extra = const {}]) => {...fx('takeview/takeview.$name.result'), ...extra};

Rig setup({bool withVideo = true}) {
  final created = <int>[], disposed = <int>[];
  final core = MockCore()
    ..result('takeview.open', snap('open'))
    ..result('takeview.openOffset', snap('openOffset'))
    ..result('takeview.close', <String, Object?>{})
    ..result('takeview.snapshot', snap('snapshot'))
    ..result('takeview.pause', snap('pause'))
    ..result('takeview.seek', snap('seek'))
    ..result('takeview.setBacking', snap('setBacking'))
    ..result('takeview.play', snap('snapshot', {'playing': true, 'epoch': 1}));
  final channel = FrameChannel(FrameChannelId.take,
      createTexture: (id) {
        created.add(id);
        return 7;
      },
      disposeTexture: disposed.add);
  final c = ProviderContainer(overrides: [
    coreClientProvider.overrideWithValue(core),
    frameChannelProvider(FrameChannelId.take).overrideWithValue(channel),
  ]);
  addTearDown(c.dispose);
  c.listen(takeViewerStoreProvider, (_, _) {});
  c.read(takeViewerStoreProvider);
  return Rig(core, c, created, disposed);
}

Json pos(Json extra) => {'seconds': 1.0, 'playing': true, 'rate': 1.0, 'at': 100.0, 'epoch': 1, ...extra};

void main() {
  test('open: snapshot con vídeo crea el canal take, frameSize y rotación (FC1)', () async {
    final r = setup();
    await r.store.open('p', takeId);
    expect(r.core.calls.first.params, {'projectId': 'p', 'takeId': takeId});
    expect(r.s.isOpen, isTrue);
    expect(r.s.video, TakeVideoState.ready);
    expect(r.s.frameSize, const Size(640, 360));
    expect(r.s.videoRotation, 90);
    expect(r.s.textureId, 7);
    expect(r.created, [FrameChannelId.take.value]);
    expect(r.s.duration, 3);
    expect(r.s.songStart, 2);
    expect(r.s.outputName, 'Salida simulada');
  });

  test('toma sin vídeo: solo audio, sin canal ni frameSize', () async {
    final r = setup();
    r.core.result('takeview.open', fx('takeview/takeview.open.no-video.result'));
    await r.store.open('p', takeId);
    expect(r.s.isOpen, isTrue);
    expect(r.s.video, TakeVideoState.none);
    expect(r.s.hasVideo, isFalse);
    expect(r.s.frameSize, isNull);
    expect(r.s.textureId, isNull);
    expect(r.created, isEmpty);
  });

  test('openOffset: sin backing aunque haya stems', () async {
    final r = setup();
    await r.store.openOffset();
    expect(r.count('takeview.openOffset'), 1);
    expect(r.s.isOffset, isTrue);
    expect(r.s.backingOn, isFalse);
    expect(r.s.canToggleBacking, isFalse);
    await r.store.setBacking(true);
    expect(r.count('takeview.setBacking'), 0);
  });

  test('takeview.position actualiza posición, playing, rate, at y epoch', () async {
    final r = setup();
    await r.store.open('p', takeId);
    r.core.emit('takeview.position', pos({'seconds': 1.25}));
    await pumpEventQueue();
    expect(r.s.position, 1.25);
    expect(r.s.playing, isTrue);
    expect(r.s.rate, 1);
    expect(r.s.at, 100);
    expect(r.s.epoch, 1);
    r.core.emit('takeview.position', fx('takeview/takeview.position.paused.event'));
    await pumpEventQueue();
    expect(r.s.playing, isFalse);
  });

  test('positionAt extrapola mientras suena y recorta a la duración; quieto no mueve', () async {
    final r = setup();
    await r.store.open('p', takeId);
    r.core.emit('takeview.position', pos({'seconds': 1.0}));
    await pumpEventQueue();
    expect(r.s.positionAt(100.5), closeTo(1.5, 1e-9));
    expect(r.s.positionAt(200), 3);
    r.core.emit('takeview.position', pos({'seconds': 1.0, 'playing': false, 'rate': 0.0, 'epoch': 2}));
    await pumpEventQueue();
    expect(r.s.positionAt(105), 1.0);
  });

  test('un position con epoch viejo se ignora; sin toma abierta también', () async {
    final r = setup();
    r.core.emit('takeview.position', pos({}));
    await pumpEventQueue();
    expect(r.s.position, 0);
    await r.store.open('p', takeId);
    r.core.emit('takeview.position', pos({'epoch': 5, 'seconds': 2.0}));
    r.core.emit('takeview.position', pos({'epoch': 4, 'seconds': 0.5}));
    await pumpEventQueue();
    expect(r.s.position, 2.0);
  });

  test('play/pause/seek aplican el snapshot; el reinicio al final lo hace el núcleo', () async {
    final r = setup();
    await r.store.open('p', takeId);
    r.core.handle('takeview.play', (_) => snap('snapshot', {'playing': true, 'position': 0.0, 'epoch': 3}));
    r.core.emit('takeview.position', pos({'seconds': 2.95, 'playing': false, 'rate': 0.0, 'epoch': 2}));
    await pumpEventQueue();
    await r.store.play();
    expect(r.s.playing, isTrue);
    expect(r.s.position, 0);
    expect(r.s.epoch, 3);
    await r.store.pause();
    expect(r.s.playing, isFalse);
    await r.store.seek(1.5);
    expect(r.core.calls.last.method, 'takeview.seek');
    expect(r.core.calls.last.params, {'seconds': 1.5});
    await r.store.togglePlay();
    expect(r.count('takeview.play'), 2);
  });

  test('backing: setBacking envía on y refleja backingOn', () async {
    final r = setup();
    await r.store.open('p', takeId);
    expect(r.s.canToggleBacking, isTrue);
    r.core.handle('takeview.setBacking', (p) => snap('setBacking', {'backingOn': p['on']}));
    await r.store.setBacking(false);
    expect(r.s.backingOn, isFalse);
    expect(r.core.calls.last.params, {'on': false});
  });

  test('backing deshabilitado si la toma no tiene stems', () async {
    final r = setup();
    r.core.result('takeview.open', snap('open', {'hasBacking': false, 'backingOn': false}));
    await r.store.open('p', takeId);
    expect(r.s.canToggleBacking, isFalse);
    await r.store.setBacking(true);
    expect(r.count('takeview.setBacking'), 0);
  });

  test('takeview.video: converting, error y ready', () async {
    final r = setup();
    r.core.result('takeview.open', fx('takeview/takeview.open.no-video.result'));
    await r.store.open('p', takeId);
    final conv = fx('takeview/takeview.video.converting.event');
    final failed = fx('takeview/takeview.video.error.event');
    Json forTake(Json e) => {
          ...e,
          'takeId': takeId,
          if (e['video'] != null) 'video': {...(e['video'] as Map).cast<String, Object?>(), 'takeId': takeId},
        };
    r.core.emit('takeview.video', forTake(conv));
    await pumpEventQueue();
    expect(r.s.video, TakeVideoState.converting);
    expect(r.s.videoProgress, closeTo(0.4, 1e-9));
    expect(r.s.videoMessage, contains('H.264'));
    r.core.emit('takeview.video', forTake(failed));
    await pumpEventQueue();
    expect(r.s.video, TakeVideoState.error);
    expect(r.s.textureId, isNull);
    // otra toma: se ignora
    r.core.emit('takeview.video', conv);
    await pumpEventQueue();
    expect(r.s.video, TakeVideoState.error);
    // listo: pide snapshot con el tamaño y crea el canal
    r.core.result('takeview.snapshot', snap('open'));
    r.core.emit('takeview.video', {'takeId': takeId});
    await pumpEventQueue();
    expect(r.s.video, TakeVideoState.ready);
    expect(r.s.frameSize, const Size(640, 360));
    expect(r.s.textureId, 7);
    expect(r.created, [2]);
  });

  test('close suelta el canal, llama takeview.close y vuelve a closed', () async {
    final r = setup();
    await r.store.open('p', takeId);
    await r.store.close();
    expect(r.s.phase, TakeViewerPhase.closed);
    expect(r.s.textureId, isNull);
    expect(r.disposed, [2]);
    expect(r.count('takeview.close'), 1);
    await r.store.close();
    expect(r.count('takeview.close'), 1);
  });

  test('reabrir otra toma suelta el canal anterior', () async {
    final r = setup();
    await r.store.open('p', takeId);
    await r.store.open('p', takeId);
    expect(r.disposed, [2]);
    expect(r.created, [2, 2]);
  });

  for (final (code, msg) in [
    ('not-found', 'Esta toma no tiene audio que reproducir.'),
    ('bad-params', 'bad'),
    ('internal', 'no se pudo leer'),
    ('load-failed', 'pistas'),
    ('no-offset', 'sin hoja'),
  ]) {
    test('error de open: $code se guarda y no abre', () async {
      final r = setup();
      r.core.failWith('takeview.open', CoreError(code, msg));
      r.core.failWith('takeview.openOffset', CoreError(code, msg));
      await r.store.open('p', takeId);
      expect(r.s.phase, TakeViewerPhase.closed);
      expect(r.s.error?.code, code);
      expect(r.s.error?.message, msg);
      await r.store.openOffset();
      expect(r.s.error?.code, code);
      expect(r.created, isEmpty);
    });
  }

  test('not-open en transporte: guarda el error y marca cerrado', () async {
    final r = setup();
    await r.store.open('p', takeId);
    r.core.failWith('takeview.seek', const CoreError('not-open', 'No hay ninguna toma abierta en el visor.'));
    await r.store.seek(1);
    expect(r.s.error?.code, 'not-open');
    expect(r.s.phase, TakeViewerPhase.closed);
  });

  test('audio-unavailable en play: error y audioError del snapshot', () async {
    final r = setup();
    await r.store.open('p', takeId);
    r.core.failWith('takeview.play', const CoreError('audio-unavailable', 'sin salida'));
    await r.store.play();
    expect(r.s.error?.code, 'audio-unavailable');
    expect(r.s.isOpen, isTrue);
    r.core.result('takeview.pause', snap('pause', {'audioError': 'fallo'}));
    await r.store.pause();
    expect(r.s.audioError, 'fallo');
    expect(r.s.error, isNull);
  });

  test('transporte sin toma abierta no llama al núcleo', () async {
    final r = setup();
    await r.store.play();
    await r.store.seek(1);
    expect(r.core.calls, isEmpty);
  });

  test('soltar el store con toma abierta cierra el núcleo y el canal', () async {
    final r = setup();
    await r.store.open('p', takeId);
    r.c.dispose();
    await pumpEventQueue();
    expect(r.count('takeview.close'), 1);
    expect(r.disposed, [2]);
  });
}
