part of 'study.dart';

// Parámetros de edición: acordes, tonalidad y secciones. Ver study_params.dart.

/// `key` nulo quita la corrección: se envía como clave ausente, que el núcleo lee igual.
/// `shown` = tonalidad como se ve (transpuesta); el núcleo deshace la transposición.
final class StudySetKeyParams {
  const StudySetKeyParams({this.key, this.shown});

  factory StudySetKeyParams.fromJson(Json j) => StudySetKeyParams(
        key: _sn(j['key']),
        shown: _opt(j['shown'], StudyShownKey.fromJson),
      );

  final String? key;
  final StudyShownKey? shown;

  Json toJson() => _compact({'key': key, 'shown': shown?.toJson()});
}

final class StudySetChordParams {
  const StudySetChordParams({required this.start, required this.end, this.index, this.label, this.shown});

  factory StudySetChordParams.fromJson(Json j) => StudySetChordParams(
        start: _d(j['start']),
        end: _d(j['end']),
        index: _in(j['index']),
        label: _sn(j['label']),
        shown: _opt(j['shown'], StudyShownChord.fromJson),
      );

  final double start;
  final double end;

  /// Solo uno de [index], [label] y [shown]; [shown] = acorde tal como se ve (el núcleo destranspone).
  final int? index;
  final String? label;
  final StudyShownChord? shown;

  Json toJson() => _compact({
        'start': start,
        'end': end,
        'index': index,
        'label': label,
        'shown': shown?.toJson(),
      });
}

/// Rango de corrección (`removeChordOverrides`).
final class StudyChordRangeParams {
  const StudyChordRangeParams({required this.start, required this.end});

  factory StudyChordRangeParams.fromJson(Json j) =>
      StudyChordRangeParams(start: _d(j['start']), end: _d(j['end']));

  final double start;
  final double end;

  Json toJson() => {'start': start, 'end': end};
}

final class StudySplitChordParams {
  const StudySplitChordParams({required this.at});

  factory StudySplitChordParams.fromJson(Json j) => StudySplitChordParams(at: _d(j['at']));

  final double at;

  Json toJson() => {'at': at};
}

final class StudyMarkSectionParams {
  const StudyMarkSectionParams({
    required this.start,
    required this.end,
    this.solo,
    this.snap,
  });

  factory StudyMarkSectionParams.fromJson(Json j) => StudyMarkSectionParams(
        start: _d(j['start']),
        end: _d(j['end']),
        solo: _bn(j['solo']),
        snap: j['snap'] == null ? null : _enumOr(StudySnap.values, j['snap'], StudySnap.unknown),
      );

  final double start;
  final double end;
  final bool? solo;
  final StudySnap? snap;

  Json toJson() => _compact({
        'start': start,
        'end': end,
        'solo': solo,
        'snap': _wireOpt(snap),
      });
}

/// Tri-estado de `color`: ausente = no cambia, `null` = automático, índice = paleta.
sealed class StudyColorChange {
  const StudyColorChange();
}

/// Ausente en el JSON: no cambia.
final class StudyColorKeep extends StudyColorChange {
  const StudyColorKeep();
}

/// `null` en el JSON: color automático.
final class StudyColorAuto extends StudyColorChange {
  const StudyColorAuto();
}

/// Índice de paleta `0...6`.
final class StudyColorPalette extends StudyColorChange {
  const StudyColorPalette(this.index);

  final int index;
}

final class StudyUpdateSectionParams {
  const StudyUpdateSectionParams({
    required this.id,
    this.name,
    this.start,
    this.end,
    this.solo,
    this.snap,
    this.color = const StudyColorKeep(),
  });

  factory StudyUpdateSectionParams.fromJson(Json j) => StudyUpdateSectionParams(
        id: _s(j['id']),
        name: _sn(j['name']),
        start: _dn(j['start']),
        end: _dn(j['end']),
        solo: _bn(j['solo']),
        snap: j['snap'] == null ? null : _enumOr(StudySnap.values, j['snap'], StudySnap.unknown),
        color: !j.containsKey('color')
            ? const StudyColorKeep()
            : j['color'] == null
                ? const StudyColorAuto()
                : StudyColorPalette(_i(j['color'])),
      );

  final String id;
  final String? name;
  final double? start;
  final double? end;
  final bool? solo;
  final StudySnap? snap;
  final StudyColorChange color;

  Json toJson() {
    final m = _compact({
      'id': id,
      'name': name,
      'start': start,
      'end': end,
      'solo': solo,
      'snap': _wireOpt(snap),
    });
    final c = color;
    if (c is StudyColorAuto) m['color'] = null;
    if (c is StudyColorPalette) m['color'] = c.index;
    return m;
  }
}

final class StudyPreviewSectionEdgeParams {
  const StudyPreviewSectionEdgeParams({required this.id, required this.start, required this.to, this.snap});

  factory StudyPreviewSectionEdgeParams.fromJson(Json j) => StudyPreviewSectionEdgeParams(
        id: _s(j['id']),
        start: _b(j['start']),
        to: _d(j['to']),
        snap: j['snap'] == null ? null : _enumOr(StudySnap.values, j['snap'], StudySnap.unknown),
      );

  final String id;
  final bool start;
  final double to;
  final StudySnap? snap;

  Json toJson() => _compact({
        'id': id,
        'start': start,
        'to': to,
        'snap': _wireOpt(snap),
      });
}

final class StudyNudgeSectionParams {
  const StudyNudgeSectionParams({
    required this.id,
    required this.start,
    required this.forward,
    this.bar,
  });

  factory StudyNudgeSectionParams.fromJson(Json j) => StudyNudgeSectionParams(
        id: _s(j['id']),
        start: _b(j['start']),
        forward: _b(j['forward']),
        bar: _bn(j['bar']),
      );

  final String id;
  final bool start;
  final bool forward;
  final bool? bar;

  Json toJson() => _compact({'id': id, 'start': start, 'forward': forward, 'bar': bar});
}

final class StudyDeleteSectionParams {
  const StudyDeleteSectionParams({required this.id});

  factory StudyDeleteSectionParams.fromJson(Json j) => StudyDeleteSectionParams(id: _s(j['id']));

  final String id;

  Json toJson() => {'id': id};
}
