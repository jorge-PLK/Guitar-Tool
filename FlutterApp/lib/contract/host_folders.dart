import '../core/core_client.dart' show Json;

/// Resultado de `host.pickProjectsFolder`. `path` siempre sale; `null` si se cancela.
class PickedFolderResult {
  const PickedFolderResult({this.path, required this.restartRequired});

  factory PickedFolderResult.fromJson(Json json) => PickedFolderResult(
    path: json['path'] as String?,
    restartRequired: json['restartRequired'] as bool,
  );

  final String? path;
  final bool restartRequired;

  Json toJson() => {'path': path, 'restartRequired': restartRequired};
}

/// Resultado de `host.chooseFolder`. `path` siempre sale; `null` si se cancela.
class ChosenFolderResult {
  const ChosenFolderResult({this.path});

  factory ChosenFolderResult.fromJson(Json json) =>
      ChosenFolderResult(path: json['path'] as String?);

  final String? path;

  Json toJson() => {'path': path};
}
