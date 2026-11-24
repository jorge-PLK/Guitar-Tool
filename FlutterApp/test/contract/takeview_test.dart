import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/takeview.dart';
import 'package:toneforge/core/core_client.dart' show Json;
import 'package:toneforge/core/mock_core.dart';

/// Decodifica con la clase del DTO y vuelve a codificar; el resultado debe igualar al fixture.
typedef _Codec = Json Function(Json j);

/// Params o result sin campos: el fixture debe ser `{}`.
Json _empty(Json j) {
  expect(j, isEmpty, reason: 'Se esperaba {}');
  return {};
}

Json _open(Json j) => TakeViewOpenParams.fromJson(j).toJson();
Json _seek(Json j) => TakeViewSeekParams.fromJson(j).toJson();
Json _backing(Json j) => TakeViewBackingParams.fromJson(j).toJson();
Json _snapshot(Json j) => TakeViewSnapshot.fromJson(j).toJson();
Json _position(Json j) => TakeViewPositionEvent.fromJson(j).toJson();
Json _video(Json j) => TakeViewVideoEvent.fromJson(j).toJson();

/// Clave `<método>.<params|result|event>` → decodificador. Un fixture sin entrada falla el test.
final Map<String, _Codec> _codecs = {
  'open.params': _open,
  'open.result': _snapshot,
  'openOffset.params': _empty,
  'openOffset.result': _snapshot,
  'close.params': _empty,
  'close.result': _empty,
  'snapshot.params': _empty,
  'snapshot.result': _snapshot,
  'play.params': _empty,
  'pause.params': _empty,
  'pause.result': _snapshot,
  'seek.params': _seek,
  'seek.result': _snapshot,
  'setBacking.params': _backing,
  'setBacking.result': _snapshot,
  'position.event': _position,
  'video.event': _video,
};

/// `takeview.open.no-video.params.json` → `open.params`; `takeview.video.error.event.json` → `video.event`.
String? _keyOf(String path) {
  final name = path.split('/').last.replaceFirst(RegExp(r'\.json$'), '');
  final parts = name.split('.');
  if (parts.length < 3 || parts.first != 'takeview') return null;
  return '${parts[1]}.${parts.last}';
}

bool _same(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_same(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_same(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

void main() {
  test('cada fixture de takeview tiene decodificador y reproduce sus campos', () async {
    final source = await DirectoryFixtureSource.find();
    if (source == null) fail('No se encuentra Contract/fixtures');
    final files = (await source.list()).where((p) => p.startsWith('takeview/')).toList()..sort();
    expect(files, hasLength(23));

    final missing = <String>[];
    final lost = <String>[];
    for (final path in files) {
      final key = _keyOf(path);
      final codec = key == null ? null : _codecs[key];
      if (codec == null) {
        missing.add(path);
        continue;
      }
      final original = jsonDecode(await source.read(path)) as Json;
      if (!_same(original, codec(original))) lost.add(path);
    }
    expect(missing, isEmpty, reason: 'Fixtures sin decodificador asignado');
    expect(lost, isEmpty, reason: 'Campos perdidos al volver a codificar');
  });

  test('valores concretos: FC1 de vídeo, toma sin vídeo, error de conversión y reloj', () async {
    final source = await DirectoryFixtureSource.find();
    if (source == null) fail('No se encuentra Contract/fixtures');
    Future<Json> load(String name) async => jsonDecode(await source.read('takeview/$name.json')) as Json;

    final open = TakeViewSnapshot.fromJson(await load('takeview.open.result'));
    expect(open.videoWidth, 640);
    expect(open.videoHeight, 360);
    expect(open.videoRotation, 90);
    expect(open.duration, 3.0);

    final noVideo = TakeViewSnapshot.fromJson(await load('takeview.open.no-video.result'));
    expect(noVideo.videoWidth, isNull);
    expect(noVideo.videoHeight, isNull);
    expect(noVideo.videoRotation, 0);

    final failed = TakeViewVideoEvent.fromJson(await load('takeview.video.error.event'));
    expect(failed.video?.code, 'video-failed');
    expect(failed.video?.progress, isNull);

    final ready = TakeViewVideoEvent.fromJson(await load('takeview.video.ready.event'));
    expect(ready.video, isNull);

    final playing = TakeViewPositionEvent.fromJson(await load('takeview.position.playing.event'));
    expect(playing.playing, isTrue);
    expect(playing.rate, 1);
    expect(playing.epoch, 1);
  });
}
