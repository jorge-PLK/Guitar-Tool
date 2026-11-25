part of 'study.dart';

// Parámetros. toJson omite las claves nulas (ausente = «no cambia» en el núcleo),
// salvo el tri-estado de `color` en StudyUpdateSectionParams.
// Los parámetros sin campos (`{}`) no tienen clase.

final class StudyOpenParams {
  const StudyOpenParams({required this.projectId});

  factory StudyOpenParams.fromJson(Json j) => StudyOpenParams(projectId: _s(j['projectId']));

  final String projectId;

  Json toJson() => {'projectId': projectId};
}

final class StudySeekParams {
  const StudySeekParams({required this.seconds});

  factory StudySeekParams.fromJson(Json j) => StudySeekParams(seconds: _d(j['seconds']));

  final double seconds;

  Json toJson() => {'seconds': seconds};
}

final class StudyRateParams {
  const StudyRateParams({required this.rate});

  factory StudyRateParams.fromJson(Json j) => StudyRateParams(rate: _d(j['rate']));

  final double rate;

  Json toJson() => {'rate': rate};
}

final class StudyTransposeParams {
  const StudyTransposeParams({this.semitones, this.fineCents});

  factory StudyTransposeParams.fromJson(Json j) => StudyTransposeParams(
        semitones: _in(j['semitones']),
        fineCents: _dn(j['fineCents']),
      );

  final int? semitones;
  final double? fineCents;

  Json toJson() => _compact({'semitones': semitones, 'fineCents': fineCents});
}

final class StudyCapoParams {
  const StudyCapoParams({required this.capo});

  factory StudyCapoParams.fromJson(Json j) => StudyCapoParams(capo: _i(j['capo']));

  final int capo;

  Json toJson() => {'capo': capo};
}

final class StudyLoopParams {
  const StudyLoopParams({this.start, this.end, this.name, this.snap});

  factory StudyLoopParams.fromJson(Json j) => StudyLoopParams(
        start: _dn(j['start']),
        end: _dn(j['end']),
        name: _sn(j['name']),
        snap: j['snap'] == null ? null : _enumOr(StudySnap.values, j['snap'], StudySnap.unknown),
      );

  final double? start;
  final double? end;
  final String? name;
  final StudySnap? snap;

  Json toJson() => _compact({
        'start': start,
        'end': end,
        'name': name,
        'snap': _wireOpt(snap),
      });
}

final class StudyMixParams {
  const StudyMixParams({required this.channel, this.gainDB, this.mute, this.solo});

  factory StudyMixParams.fromJson(Json j) => StudyMixParams(
        channel: _s(j['channel']),
        gainDB: _dn(j['gainDB']),
        mute: _bn(j['mute']),
        solo: _bn(j['solo']),
      );

  final String channel;
  final double? gainDB;
  final bool? mute;
  final bool? solo;

  Json toJson() =>
      _compact({'channel': channel, 'gainDB': gainDB, 'mute': mute, 'solo': solo});
}

final class StudyMasterParams {
  const StudyMasterParams({required this.gainDB});

  factory StudyMasterParams.fromJson(Json j) => StudyMasterParams(gainDB: _d(j['gainDB']));

  final double gainDB;

  Json toJson() => {'gainDB': gainDB};
}

final class StudyMetronomeParams {
  const StudyMetronomeParams({this.on, this.gainDB});

  factory StudyMetronomeParams.fromJson(Json j) =>
      StudyMetronomeParams(on: _bn(j['on']), gainDB: _dn(j['gainDB']));

  final bool? on;
  final double? gainDB;

  Json toJson() => _compact({'on': on, 'gainDB': gainDB});
}

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

enum StudySnap { none, beat, bar, chord, unknown }

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

final class StudyRenameGuitarParams {
  const StudyRenameGuitarParams({required this.role, required this.name});

  factory StudyRenameGuitarParams.fromJson(Json j) => StudyRenameGuitarParams(
        role: _enumOr(StudyGuitarRole.values, j['role'], StudyGuitarRole.unknown),
        name: _s(j['name']),
      );

  final StudyGuitarRole role;

  /// Vacío = nombre por defecto.
  final String name;

  Json toJson() => {'role': _wire(role), 'name': name};
}

final class StudyGuitarStereoParams {
  const StudyGuitarStereoParams({required this.on});

  factory StudyGuitarStereoParams.fromJson(Json j) => StudyGuitarStereoParams(on: _b(j['on']));

  final bool on;

  Json toJson() => {'on': on};
}
