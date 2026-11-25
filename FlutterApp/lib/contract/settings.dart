import '../core/core_client.dart' show Json;

/// Resultado de `settings.get`. Las carpetas van siempre; `null` si no hay.
/// `video` queda crudo: su DTO llega en la ola 3 (`contract/video.dart`).
class SettingsGetResult {
  const SettingsGetResult({
    this.projectsFolder,
    this.activeProjectsFolder,
    required this.video,
  });

  factory SettingsGetResult.fromJson(Json json) => SettingsGetResult(
    projectsFolder: json['projectsFolder'] as String?,
    activeProjectsFolder: json['activeProjectsFolder'] as String?,
    video: json['video'] as Json,
  );

  final String? projectsFolder;
  final String? activeProjectsFolder;
  final Json video;

  Json toJson() => {
    'projectsFolder': projectsFolder,
    'activeProjectsFolder': activeProjectsFolder,
    'video': video,
  };
}
