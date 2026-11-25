import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/record.dart';
import 'package:toneforge/contract/takeview.dart';

// Valores y campos de Swift (RecordMethods.swift, RecordController.swift:117-132, TakeViewMethods.swift:111,
// StudyMethods.swift:102) que antes caían en `unknown` o se ignoraban.

void main() {
  test('PartStatus: pending, recording y done', () {
    for (final (raw, v) in [('pending', PartStatus.pending), ('recording', PartStatus.recording), ('done', PartStatus.done)]) {
      expect(enumOf(PartStatus.values, PartStatus.unknown, raw), v);
    }
    expect(enumOf(PartStatus.values, PartStatus.unknown, 'otro'), PartStatus.unknown);
  });

  test('CameraState: idle | none | denied | simulated | failed | live', () {
    for (final raw in ['idle', 'none', 'denied', 'simulated', 'failed', 'live']) {
      expect(enumOf(CameraState.values, CameraState.unknown, raw).name, raw);
    }
  });

  test('RecordPart.replaces y RecordMixChannel.guitarRole', () {
    final p = RecordPart.fromJson({
      'id': 'p', 'name': 'Rítmica', 'isLead': false, 'status': 'recording', 'takes': <Object?>[], 'replaces': 'rhythm',
    });
    expect(p.replaces, 'rhythm');
    expect(p.status, PartStatus.recording);
    expect(p.toJson()['replaces'], 'rhythm');
    expect(RecordPart.fromJson({'id': 'p', 'name': 'x', 'isLead': false, 'status': 'done', 'takes': <Object?>[]}).replaces, isNull);
    final m = {'id': 'g', 'kind': 'guitar', 'name': 'Guitarra', 'gainDB': 0, 'muted': false, 'solo': false, 'forcedMuted': true};
    expect(RecordMixChannel.fromJson({...m, 'guitarRole': 'lead'}).guitarRole, 'lead');
    expect(RecordMixChannel.fromJson(m).guitarRole, isNull);
  });

  test('RecordSection.color', () {
    final s = {'id': 'a', 'name': 'V', 'solo': false, 'start': 0, 'end': 4};
    expect(RecordSection.fromJson({...s, 'color': 3}).color, 3);
    expect(RecordSection.fromJson(s).color, isNull);
    expect(RecordSection.fromJson({...s, 'color': 3}).toJson()['color'], 3);
  });

  test('TakeViewSnapshot.video: convirtiendo, fallido y ausente', () {
    final s = {
      'projectId': 'p', 'takeId': 't', 'duration': 1, 'songStart': 0, 'hasBacking': false, 'backingOn': false,
      'playing': false, 'position': 0, 'epoch': 0, 'outputName': 'o',
    };
    expect(TakeViewSnapshot.fromJson(s).video, isNull);
    final v = TakeViewSnapshot.fromJson({
      ...s,
      'video': {'code': 'video-converting', 'takeId': 't', 'jobId': 'j', 'progress': 0.5, 'message': 'Convirtiendo'},
    }).video!;
    expect(v.code, 'video-converting');
    expect(v.progress, 0.5);
    final f = TakeViewSnapshot.fromJson({
      ...s,
      'video': {'code': 'video-failed', 'takeId': 't', 'jobId': 'j', 'message': 'Falló'},
    });
    expect(f.video!.progress, isNull);
    expect(f.toJson()['video'], isNotNull);
  });
}
