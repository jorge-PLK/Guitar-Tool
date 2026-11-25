part of 'tab.dart';

// Parámetros: fromJson y toJson. Las claves nulas se omiten (ausente = null).

enum TabSpanAction with TabWire {
  clear('clear'),
  apply('apply'),
  extendForward('extendForward'),
  extendBack('extendBack'),
  unknown('unknown');

  const TabSpanAction(this.wire);
  @override
  final String wire;
}

final class TabOpenParams {
  const TabOpenParams({required this.projectId});

  factory TabOpenParams.fromJson(Json j) =>
      TabOpenParams(projectId: _s(j['projectId']));

  Json toJson() => {'projectId': projectId};

  final String projectId;
}

final class TabSourceParams {
  const TabSourceParams({required this.source});

  factory TabSourceParams.fromJson(Json j) => TabSourceParams(
        source: _enumOr(TabSource.values, j['source'], TabSource.unknown),
      );

  Json toJson() => {'source': _wire(source)};

  final TabSource source;
}

/// `track` opcional en `tab.score`; obligatorio en el resto de métodos que lo usan.
final class TabTrackParams {
  const TabTrackParams({this.track});

  factory TabTrackParams.fromJson(Json j) =>
      TabTrackParams(track: _sn(j['track']));

  Json toJson() => _compact({'track': track});

  final String? track;
}

/// Índices de alphaTab/JSON (no de la rejilla).
final class TabClickParams {
  const TabClickParams({
    required this.track,
    required this.bar,
    required this.beat,
    this.shift,
    this.string,
  });

  factory TabClickParams.fromJson(Json j) => TabClickParams(
        track: _i(j['track']),
        bar: _i(j['bar']),
        beat: _i(j['beat']),
        shift: _bn(j['shift']),
        string: _in(j['string']),
      );

  Json toJson() => _compact({
        'track': track,
        'bar': bar,
        'beat': beat,
        'shift': shift,
        'string': string,
      });

  final int track;
  final int bar;
  final int beat;
  final bool? shift;
  final int? string;
}

/// `beat` índice global; `tick` 0..<12.
final class TabSelectParams {
  const TabSelectParams({
    required this.track,
    required this.beat,
    required this.tick,
    this.string,
  });

  factory TabSelectParams.fromJson(Json j) => TabSelectParams(
        track: _s(j['track']),
        beat: _i(j['beat']),
        tick: _i(j['tick']),
        string: _in(j['string']),
      );

  Json toJson() => _compact({
        'track': track,
        'beat': beat,
        'tick': tick,
        'string': string,
      });

  final String track;
  final int beat;
  final int tick;
  final int? string;
}

final class TabSpanParams {
  const TabSpanParams({required this.action, this.keepAnchor});

  factory TabSpanParams.fromJson(Json j) => TabSpanParams(
        action: _enumOr(TabSpanAction.values, j['action'], TabSpanAction.unknown),
        keepAnchor: _bn(j['keepAnchor']),
      );

  Json toJson() => _compact({'action': _wire(action), 'keepAnchor': keepAnchor});

  final TabSpanAction action;

  /// Solo con `clear`: limpia el tramo y conserva el ancla del ⇧clic.
  final bool? keepAnchor;
}

final class TabListeningParams {
  const TabListeningParams({required this.on, this.track});

  factory TabListeningParams.fromJson(Json j) =>
      TabListeningParams(on: _b(j['on']), track: _sn(j['track']));

  Json toJson() => _compact({'track': track, 'on': on});

  final String? track;
  final bool on;
}

final class TabExportParams {
  const TabExportParams({required this.data, this.path});

  factory TabExportParams.fromJson(Json j) =>
      TabExportParams(data: _s(j['data']), path: _sn(j['path']));

  Json toJson() => _compact({'data': data, 'path': path});

  /// Base64 del `.gp`.
  final String data;
  final String? path;
}

/// Parámetros de `tab.edit`. Un constructor (factoría) por `op`; los valores de
/// `op`, `piece`, `name`, `preset` van como texto del contrato (lista abierta).
final class TabEditParams {
  const TabEditParams._(
    this.op, {
    this.value,
    this.up,
    this.sign,
    this.piece,
    this.name,
    this.key,
    this.shift,
    this.ctrl,
    this.alt,
    this.forward,
    this.track,
    this.preset,
    this.on,
  });

  factory TabEditParams.fromJson(Json j) => TabEditParams._(
        _s(j['op']),
        value: _in(j['value']),
        up: _bn(j['up']),
        sign: _in(j['sign']),
        piece: _sn(j['piece']),
        name: _sn(j['name']),
        key: _sn(j['key']),
        shift: _bn(j['shift']),
        ctrl: _bn(j['ctrl']),
        alt: _bn(j['alt']),
        forward: _bn(j['forward']),
        track: _sn(j['track']),
        preset: _sn(j['preset']),
        on: _bn(j['on']),
      );

  factory TabEditParams.digit(int value) =>
      TabEditParams._('digit', value: value);

  factory TabEditParams.moveString({required bool up}) =>
      TabEditParams._('moveString', up: up);

  factory TabEditParams.delete() => const TabEditParams._('delete');

  factory TabEditParams.duration({required int sign}) =>
      TabEditParams._('duration', sign: sign);

  factory TabEditParams.hit({required String piece}) =>
      TabEditParams._('hit', piece: piece);

  factory TabEditParams.ornament({required String name}) =>
      TabEditParams._('ornament', name: name);

  factory TabEditParams.key({
    required String key,
    bool? shift,
    bool? ctrl,
    bool? alt,
  }) =>
      TabEditParams._('key', key: key, shift: shift, ctrl: ctrl, alt: alt);

  factory TabEditParams.addNote() => const TabEditParams._('addNote');

  factory TabEditParams.move({required bool forward}) =>
      TabEditParams._('move', forward: forward);

  factory TabEditParams.tuning({required String track, required String preset}) =>
      TabEditParams._('tuning', track: track, preset: preset);

  factory TabEditParams.undo() => const TabEditParams._('undo');

  factory TabEditParams.redo() => const TabEditParams._('redo');

  factory TabEditParams.editMode({required bool on}) =>
      TabEditParams._('editMode', on: on);

  factory TabEditParams.deselect() => const TabEditParams._('deselect');

  Json toJson() => _compact({
        'op': op,
        'value': value,
        'up': up,
        'sign': sign,
        'piece': piece,
        'name': name,
        'key': key,
        'shift': shift,
        'ctrl': ctrl,
        'alt': alt,
        'forward': forward,
        'track': track,
        'preset': preset,
        'on': on,
      });

  final String op;
  final int? value;
  final bool? up;
  final int? sign;
  final String? piece;
  final String? name;
  final String? key;
  final bool? shift;
  final bool? ctrl;
  final bool? alt;
  final bool? forward;
  final String? track;
  final String? preset;
  final bool? on;
}

final class SongsterrSelectParams {
  const SongsterrSelectParams({required this.songId});

  factory SongsterrSelectParams.fromJson(Json j) =>
      SongsterrSelectParams(songId: _i(j['songId']));

  Json toJson() => {'songId': songId};

  final int songId;
}

final class SongsterrLinkParams {
  const SongsterrLinkParams({required this.link});

  factory SongsterrLinkParams.fromJson(Json j) =>
      SongsterrLinkParams(link: _s(j['link']));

  Json toJson() => {'link': link};

  final String link;
}

/// `track` ausente/null = automática (o «ninguna» en un solo); `solo` = índice de la sección.
final class SongsterrAssignParams {
  const SongsterrAssignParams({required this.stemId, this.track, this.solo});

  factory SongsterrAssignParams.fromJson(Json j) => SongsterrAssignParams(
        stemId: _s(j['stemId']),
        track: _in(j['track']),
        solo: _in(j['solo']),
      );

  Json toJson() => _compact({'stemId': stemId, 'track': track, 'solo': solo});

  final String stemId;
  final int? track;
  final int? solo;
}
