import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/montage.dart';
import 'package:toneforge/features/montage/montage_timeline_mapping.dart';
import 'package:toneforge/features/montage/widgets/montage_timeline_painter.dart';

MontageSnapshot snap(String name) => MontageSnapshot.fromJson(
    (json.decode(File('../Contract/fixtures/montage/montage.$name.json').readAsStringSync()) as Map).cast<String, Object?>());

void main() {
  test('layout lado a lado: eje, carriles y sin carril Plano', () {
    final s = snap('open.result');
    final d = montageTimelineData(s);
    final axis = MontageTimelineData.axisFor(
        spanStart: s.span.start, spanEnd: s.span.end, songDuration: s.songDuration, barDuration: s.barDuration);
    expect(d.axisStart, axis.start);
    expect(d.axisEnd, axis.end);
    expect(d.spanStart, s.span.start);
    expect(d.lanes.length, s.lanes.length);
    expect(d.showPlane, isFalse);
    expect(d.cuts, isEmpty);
    expect(d.missingCount, s.missingParts.length);
    expect(d.cursor, isNull);
    expect(d.lanes.first.take, TimeSpan(s.lanes.first.take.start, s.lanes.first.take.end));
  });

  test('plano unico: carril Plano, cortes y tramos', () {
    final s = snap('open.single.result');
    final d = montageTimelineData(s, cursor: 4);
    expect(d.showPlane, isTrue);
    expect(d.cuts.map((c) => c.time), [3, 5]);
    expect(d.cuts.every((c) => c.covered), isTrue);
    expect(d.planeShots.length, s.planeShots.length);
    expect(d.cursor, 4);
  });

  test('colorIndex cuenta solo las no solistas', () {
    final d = montageTimelineData(snap('open.result'));
    final idx = [for (final l in d.lanes) if (!l.solo) l.colorIndex];
    expect(idx, [for (var i = 0; i < idx.length; i++) i]);
  });
}
