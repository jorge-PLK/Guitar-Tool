import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/record.dart';
import 'package:toneforge/contract/video_settings.dart';
import 'package:toneforge/core/core_client.dart' show Json;

// Opcionalidad 1:1 con los Codable de Swift (RecordMethods.swift, StudyMethods.swift): los campos `?` pueden
// llegar a null o ausentes sin que la decodificación falle.

Json base() =>
    (json.decode(File('../Contract/fixtures/record/record.open.result.json').readAsStringSync()) as Map).cast<String, Object?>();

Json obj(Object? o) => (o as Map).cast<String, Object?>();

void main() {
  test('RecordCamera: sin nombre, elegida, desfase ni tamaño (RecordMethods.swift:107-120)', () {
    final cam = obj(base()['camera']);
    for (final k in ['name', 'chosenId', 'defaultOffsetMs', 'width', 'height', 'fps', 'label', 'message']) {
      cam.remove(k);
    }
    final c = RecordCamera.fromJson(cam);
    expect(c.name, isNull);
    expect(c.chosenId, isNull);
    expect(c.defaultOffsetMs, isNull);
    expect(c.fps, isNull);
    final nulls = RecordCamera.fromJson({...cam, 'name': null, 'chosenId': null, 'defaultOffsetMs': null, 'fps': null});
    expect(nulls.defaultOffsetMs, isNull);
    final frac = RecordCamera.fromJson({...cam, 'fps': 29.97, 'defaultOffsetMs': -12.5});
    expect(frac.fps, 29.97);
    expect(frac.defaultOffsetMs, -12.5);
  });

  test('RecordSection: paletteIndex nulo o ausente (StudyMethods.swift:109)', () {
    final s = {'id': 'a', 'name': 'Verso', 'solo': true, 'start': 0, 'end': 4};
    expect(RecordSection.fromJson(s).paletteIndex, isNull);
    expect(RecordSection.fromJson({...s, 'paletteIndex': null, 'color': null}).paletteIndex, isNull);
    expect(RecordSection.fromJson({...s, 'paletteIndex': 2}).paletteIndex, 2);
    expect(RecordSection.fromJson(s).toJson().containsKey('paletteIndex'), isFalse);
  });

  test('RecordTake: videoOffsetMs y videoFormat.fps fraccionarios, opcionales ausentes (RecordMethods.swift:25-51)', () {
    final t = {
      'best': false,
      'createdAt': '2026-01-01T00:00:00Z',
      'discarded': false,
      'hasVideo': true,
      'id': 't',
      'number': 1,
      'punches': <Object?>[],
      'selected': false,
      'videoRotation': 0,
      'videoOffsetMs': 12.5,
      'videoFormat': {'cameraId': 'c', 'cameraName': 'n', 'width': 1280, 'height': 720, 'fps': 29.97},
    };
    final take = RecordTake.fromJson(t);
    expect(take.videoOffsetMs, 12.5);
    expect(take.videoFormat!.fps, 29.97);
    final bare = RecordTake.fromJson({...t}..remove('videoOffsetMs')..remove('videoFormat'));
    expect(bare.videoOffsetMs, isNull);
    expect(bare.videoFormat, isNull);
  });

  test('RecordOffset: valores Double de Swift (RecordMethods.swift:122-138)', () {
    final o = {
      'audioPath': 'a',
      'cameraId': 'c',
      'cameraName': 'n',
      'fps': 29.97,
      'frameMs': 33.4,
      'initialMs': -10.5,
      'isNew': false,
      'maxMs': 500.0,
      'minMs': -500.0,
      'punches': <Object?>[],
      'rotation': 0,
      'songStart': 1.5,
      'takeId': 't',
      'valueMs': 3.25,
      'videoPath': 'v',
    };
    final off = RecordOffset.fromJson(o);
    expect(off.valueMs, 3.25);
    expect(off.minMs, -500);
    expect(off.fps, 29.97);
  });

  test('RecordSnapshot: activePartId nulo, cámara y sección con opcionales nulos', () {
    final j = base();
    j.remove('activePartId');
    j['camera'] = {'state': 'idle', 'rotation': 0, 'cameras': <Object?>[], 'name': null, 'chosenId': null, 'defaultOffsetMs': null};
    j['sections'] = [
      {'id': 'a', 'name': 'Verso', 'solo': false, 'start': 0, 'end': 4, 'paletteIndex': null},
    ];
    final s = RecordSnapshot.fromJson(j);
    expect(s.activePartId, isNull);
    expect(s.camera.state, CameraState.unknown);
    expect(s.sections.single.paletteIndex, isNull);
    expect(RecordSnapshot.fromJson({...j, 'activePartId': null}).activePartId, isNull);
  });

  test('VideoOffsetRange: min y max llegan como Double (SettingsMethods.swift:469)', () {
    final r = VideoOffsetRange.fromJson({'min': -500.0, 'max': 500.0});
    expect(r.min, -500);
    expect(r.max, 500);
  });
}
