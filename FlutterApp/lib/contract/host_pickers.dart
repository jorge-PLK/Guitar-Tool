import '../core/core_client.dart' show Json;

/// Resultado de `host.pickAudioFiles`.
class PickedFilesResult {
  const PickedFilesResult({required this.paths});

  factory PickedFilesResult.fromJson(Json json) => PickedFilesResult(
    paths: List.unmodifiable((json['paths'] as List<Object?>).cast<String>()),
  );

  final List<String> paths;

  Json toJson() => {'paths': paths};
}

/// Parámetros de `host.openURL`.
class OpenURLParams {
  const OpenURLParams({required this.urls});

  factory OpenURLParams.fromJson(Json json) => OpenURLParams(
    urls: List.unmodifiable((json['urls'] as List<Object?>).cast<String>()),
  );

  final List<String> urls;

  Json toJson() => {'urls': urls};
}

/// Resultado de `host.openURL`. Ausente si es nulo.
class OpenURLResult {
  const OpenURLResult({this.opened});

  factory OpenURLResult.fromJson(Json json) =>
      OpenURLResult(opened: json['opened'] as String?);

  final String? opened;

  Json toJson() => {if (opened != null) 'opened': opened};
}
