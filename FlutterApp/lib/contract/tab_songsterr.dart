part of 'tab.dart';

// Hoja de Songsterr (`tab.songsterr.*`). Solo fromJson.

enum TabSongsterrStage with TabWire {
  choosing('choosing'),
  working('working'),
  pairing('pairing'),
  failed('failed'),
  unknown('unknown');

  const TabSongsterrStage(this.wire);
  @override
  final String wire;
}

enum TabSongsterrSearchPhase with TabWire {
  idle('idle'),
  searching('searching'),
  results('results'),
  failed('failed'),
  unknown('unknown');

  const TabSongsterrSearchPhase(this.wire);
  @override
  final String wire;
}

enum TabSongsterrIssueKind with TabWire {
  noResults('noResults'),
  rateLimited('rateLimited'),
  offline('offline'),
  formatChanged('formatChanged'),
  invalidLink('invalidLink'),
  other('other'),
  unknown('unknown');

  const TabSongsterrIssueKind(this.wire);
  @override
  final String wire;
}

/// Rol de un slot de emparejamiento. `guitar_lead` se sustituye por `lead`.
enum TabSongsterrRole with TabWire {
  guitarL('guitar_L'),
  guitarR('guitar_R'),
  guitar('guitar'),
  bass('bass'),
  drums('drums'),
  lead('lead'),
  unknown('unknown');

  const TabSongsterrRole(this.wire);
  @override
  final String wire;
}

final class SongsterrSheetState {
  const SongsterrSheetState({
    required this.open,
    required this.stage,
    required this.results,
    required this.busy,
    required this.canUse,
    this.query,
    this.search,
    this.selected,
    this.loadingSongId,
    this.detailIssue,
    this.linkIssue,
    this.workingText,
    this.failure,
    this.pairing,
  });

  /// Cerrada: `{open:false, stage:"choosing", results:[], busy:false, canUse:false}`.
  factory SongsterrSheetState.fromJson(Json j) => SongsterrSheetState(
        open: _b(j['open']),
        stage: _enumOr(
          TabSongsterrStage.values,
          j['stage'],
          TabSongsterrStage.unknown,
        ),
        query: _sn(j['query']),
        search: _opt(j['search'], SongsterrSearchInfo.fromJson),
        results: _items(j['results'], SongsterrResultInfo.fromJson),
        selected: _opt(j['selected'], SongsterrSongInfo.fromJson),
        loadingSongId: _in(j['loadingSongId']),
        detailIssue: _opt(j['detailIssue'], SongsterrIssueInfo.fromJson),
        linkIssue: _opt(j['linkIssue'], SongsterrIssueInfo.fromJson),
        busy: _b(j['busy']),
        canUse: _b(j['canUse']),
        workingText: _sn(j['workingText']),
        failure: _opt(j['failure'], SongsterrIssueInfo.fromJson),
        pairing: _opt(j['pairing'], SongsterrPairingInfo.fromJson),
      );

  final bool open;
  final TabSongsterrStage stage;
  /// «Artista · Título».
  final String? query;
  final SongsterrSearchInfo? search;
  final List<SongsterrResultInfo> results;
  final SongsterrSongInfo? selected;
  /// `-1` = se está leyendo el enlace pegado.
  final int? loadingSongId;
  final SongsterrIssueInfo? detailIssue;
  final SongsterrIssueInfo? linkIssue;
  final bool busy;
  final bool canUse;
  /// Con `working`.
  final String? workingText;
  /// Con `failed`.
  final SongsterrIssueInfo? failure;
  /// Con `pairing`.
  final SongsterrPairingInfo? pairing;
}

final class SongsterrSearchInfo {
  const SongsterrSearchInfo({required this.phase, this.issue});

  factory SongsterrSearchInfo.fromJson(Json j) => SongsterrSearchInfo(
        phase: _enumOr(
          TabSongsterrSearchPhase.values,
          j['phase'],
          TabSongsterrSearchPhase.unknown,
        ),
        issue: _opt(j['issue'], SongsterrIssueInfo.fromJson),
      );

  final TabSongsterrSearchPhase phase;
  final SongsterrIssueInfo? issue;
}

final class SongsterrIssueInfo {
  const SongsterrIssueInfo({
    required this.kind,
    required this.message,
    required this.canRetry,
    this.suggestion,
  });

  factory SongsterrIssueInfo.fromJson(Json j) => SongsterrIssueInfo(
        kind: _enumOr(
          TabSongsterrIssueKind.values,
          j['kind'],
          TabSongsterrIssueKind.unknown,
        ),
        message: _s(j['message']),
        canRetry: _b(j['canRetry']),
        suggestion: _sn(j['suggestion']),
      );

  final TabSongsterrIssueKind kind;
  final String message;
  final bool canRetry;
  final String? suggestion;
}

final class SongsterrResultInfo {
  const SongsterrResultInfo({
    required this.songId,
    required this.artist,
    required this.title,
    required this.selected,
    required this.loading,
    this.previewUrl,
  });

  factory SongsterrResultInfo.fromJson(Json j) => SongsterrResultInfo(
        songId: _i(j['songId']),
        artist: _s(j['artist']),
        title: _s(j['title']),
        selected: _b(j['selected']),
        loading: _b(j['loading']),
        previewUrl: _sn(j['previewUrl']),
      );

  final int songId;
  final String artist;
  final String title;
  final bool selected;
  final bool loading;
  final String? previewUrl;
}

final class SongsterrSongInfo {
  const SongsterrSongInfo({
    required this.songId,
    required this.revisionId,
    required this.artist,
    required this.title,
    required this.tracks,
    this.previewUrl,
  });

  factory SongsterrSongInfo.fromJson(Json j) => SongsterrSongInfo(
        songId: _i(j['songId']),
        revisionId: _i(j['revisionId']),
        artist: _s(j['artist']),
        title: _s(j['title']),
        tracks: _items(j['tracks'], SongsterrTrackInfo.fromJson),
        previewUrl: _sn(j['previewUrl']),
      );

  final int songId;
  final int revisionId;
  final String artist;
  final String title;
  final List<SongsterrTrackInfo> tracks;
  final String? previewUrl;
}

final class SongsterrTrackInfo {
  const SongsterrTrackInfo({
    required this.partId,
    required this.name,
    required this.instrument,
    required this.tuningText,
    this.tuning,
  });

  factory SongsterrTrackInfo.fromJson(Json j) => SongsterrTrackInfo(
        partId: _i(j['partId']),
        name: _s(j['name']),
        instrument: _s(j['instrument']),
        tuningText: _s(j['tuningText']),
        tuning: j['tuning'] == null ? null : _ints(j['tuning']),
      );

  final int partId;
  final String name;
  final String instrument;
  /// «E A D G B E»; «-» en batería.
  final String tuningText;
  final List<int>? tuning;
}
