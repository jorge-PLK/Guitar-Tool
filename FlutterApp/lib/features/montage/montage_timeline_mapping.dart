import 'package:toneforge/contract/montage.dart';

import 'widgets/montage_timeline_painter.dart';

/// Cursor fuera del eje: el painter de la tarjeta dibuja siempre un cursor; el real va en una capa
/// aparte (la única que escucha la posición a 30 Hz), así que el painter grande lo recibe oculto.
const double montageHiddenCursor = -1e9;

/// Snapshot de Montaje -> datos de la línea de tiempo (MV:521-537). Puro y sin estado.
/// [cursor] es la posición en segundos del tema; sin ella el cursor queda oculto.
MontageTimelineData montageTimelineData(MontageSnapshot s, {double cursor = montageHiddenCursor}) {
  final axis = MontageTimelineData.axisFor(
    spanStart: s.span.start,
    spanEnd: s.span.end,
    songDuration: s.songDuration,
    barDuration: s.barDuration,
  );
  // Color de parte: posición entre las no solistas (MV:534-535).
  var nonSolo = 0;
  final lanes = <MontageLaneData>[
    for (final l in s.lanes)
      MontageLaneData(
        take: TimeSpan(l.take.start, l.take.end),
        presence: [for (final p in l.presence) TimeSpan(p.start, p.end)],
        solo: l.isSolo,
        hasVideo: l.hasVideo,
        colorIndex: l.isSolo ? 0 : nonSolo++,
      ),
  ];
  final laneIndex = <String, int>{for (var i = 0; i < s.lanes.length; i++) s.lanes[i].id: i};
  final segs = s.segments;
  return MontageTimelineData(
    axisStart: axis.start,
    axisEnd: axis.end,
    spanStart: s.span.start,
    spanEnd: s.span.end,
    barDuration: s.barDuration,
    fadeIn: segs.isNotEmpty && segs.first.fadeIn,
    fadeOut: segs.isNotEmpty && segs.last.fadeOut,
    sections: [
      for (final x in s.sections) MontageSectionData(name: x.name, start: x.start, end: x.end, solo: x.solo),
    ],
    lanes: lanes,
    missingCount: s.missingParts.length,
    showPlane: s.isSingleShot,
    planeShots: s.isSingleShot
        ? [
            for (final p in s.planeShots)
              MontagePlaneShot(
                start: p.start,
                end: p.end,
                laneIndex: p.partId == null ? null : laneIndex[p.partId],
                black: p.black,
              ),
          ]
        : const [],
    cuts: s.isSingleShot ? [for (final c in s.cuts) MontageCutMark(time: c.time, covered: c.covered)] : const [],
    // Huecos cortados: lo que queda entre tramos consecutivos.
    gaps: [
      for (var i = 0; i + 1 < segs.length; i++)
        if (segs[i + 1].start > segs[i].end) TimeSpan(segs[i].end, segs[i + 1].start),
    ],
    cursor: cursor,
  );
}
