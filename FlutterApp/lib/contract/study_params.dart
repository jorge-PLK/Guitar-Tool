part of 'study.dart';

// Parámetros. toJson omite las claves nulas (ausente = «no cambia» en el núcleo),
// salvo el tri-estado de `color` en StudyUpdateSectionParams (en study_params_edits.dart).
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

enum StudySnap { none, beat, bar, chord, unknown }

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
