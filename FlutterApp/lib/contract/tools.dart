import '../core/core_client.dart' show Json;

/// Origen de yt-dlp (`ToolsInfoResult.ytDlpOrigin`, `UpdateYtDlpResult.origin`).
/// Valor no previsto → [unknown].
enum YtDlpOrigin {
  updated('updated'),
  embedded('embedded'),
  unknown('unknown');

  const YtDlpOrigin(this.raw);

  /// Valor crudo del contrato.
  final String raw;

  static YtDlpOrigin fromRaw(String raw) => values.firstWhere(
    (v) => v != YtDlpOrigin.unknown && v.raw == raw,
    orElse: () => YtDlpOrigin.unknown,
  );
}

/// Resultado de `tools.info`. Todo ausente si es nulo.
class ToolsInfoResult {
  const ToolsInfoResult({
    this.ytDlpVersion,
    this.ytDlpOrigin,
    this.denoVersion,
    this.ffmpegVersion,
  });

  factory ToolsInfoResult.fromJson(Json json) => ToolsInfoResult(
    ytDlpVersion: json['ytDlpVersion'] as String?,
    ytDlpOrigin: json['ytDlpOrigin'] == null
        ? null
        : YtDlpOrigin.fromRaw(json['ytDlpOrigin'] as String),
    denoVersion: json['denoVersion'] as String?,
    ffmpegVersion: json['ffmpegVersion'] as String?,
  );

  /// Ausente si es nulo.
  final String? ytDlpVersion;
  final YtDlpOrigin? ytDlpOrigin;
  final String? denoVersion;
  final String? ffmpegVersion;

  Json toJson() => {
    if (ytDlpVersion != null) 'ytDlpVersion': ytDlpVersion,
    if (ytDlpOrigin != null) 'ytDlpOrigin': ytDlpOrigin?.raw,
    if (denoVersion != null) 'denoVersion': denoVersion,
    if (ffmpegVersion != null) 'ffmpegVersion': ffmpegVersion,
  };
}

/// Resultado de `tools.updateYtDlp`. `alreadyLatest = (origin != updated)`.
class UpdateYtDlpResult {
  const UpdateYtDlpResult({
    required this.version,
    required this.origin,
    required this.alreadyLatest,
  });

  factory UpdateYtDlpResult.fromJson(Json json) => UpdateYtDlpResult(
    version: json['version'] as String,
    origin: YtDlpOrigin.fromRaw(json['origin'] as String),
    alreadyLatest: json['alreadyLatest'] as bool,
  );

  final String version;
  final YtDlpOrigin origin;
  final bool alreadyLatest;

  Json toJson() => {
    'version': version,
    'origin': origin.raw,
    'alreadyLatest': alreadyLatest,
  };
}

/// Resultado de `tools.revertYtDlp` (siempre `true` si no lanza).
class RevertedResult {
  const RevertedResult({required this.reverted});

  factory RevertedResult.fromJson(Json json) =>
      RevertedResult(reverted: json['reverted'] as bool);

  final bool reverted;

  Json toJson() => {'reverted': reverted};
}
