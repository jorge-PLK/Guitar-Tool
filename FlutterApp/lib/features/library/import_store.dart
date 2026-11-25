import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/host_pickers.dart';
import 'package:toneforge/contract/jobs.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';

const Object _keep = Object();

/// Extensiones que se importan (sin distinguir mayúsculas).
const Set<String> importableExtensions = {'wav', 'flac', 'mp3'};

bool isImportablePath(String path) {
  final name = path.split(RegExp(r'[\\/]')).last;
  final dot = name.lastIndexOf('.');
  return dot > 0 && importableExtensions.contains(name.substring(dot + 1).toLowerCase());
}

/// Aviso genérico (`notice`): error del núcleo con código y mensaje.
class ImportNotice {
  const ImportNotice({required this.code, required this.message});

  final String code;
  final String message;
}

/// Estado de las importaciones y de los trabajos vivos. Inmutable.
class ImportState {
  const ImportState({this.jobs = const {}, this.duplicateOf, this.notice, this.importing = false});

  /// Trabajos vivos por id (los terminados se quitan).
  final Map<String, JobInfo> jobs;

  /// Id del tema existente cuando `import.file` devolvió `duplicate:true`.
  final String? duplicateOf;
  final ImportNotice? notice;

  /// Hay un `import.file` en curso desde `importPaths`.
  final bool importing;

  /// Filas de importación arriba de la tabla: `import-…` y `link-…` en etapa import/download.
  List<JobInfo> get importRows => [
    for (final j in jobs.values)
      if ((j.isImportJob || j.isLinkJob) &&
          (j.stage == JobStage.importStage || j.stage == JobStage.download))
        j,
  ];

  /// Trabajo vivo de un tema (por id de tema), si lo hay.
  JobInfo? jobFor(String projectId) => jobs[projectId];

  /// Estado de separación del chip: el trabajo vivo manda sobre el de la lista.
  SeparationState separationStateFor(ProjectSummary p) {
    final j = jobs[p.id];
    if (j == null || j.stage != JobStage.separation) return p.separationState;
    return switch (j.state) {
      JobState.queued => SeparationState.queued,
      JobState.running => SeparationState.running,
      JobState.failed => SeparationState.failed,
      JobState.done => SeparationState.done,
      _ => p.separationState,
    };
  }

  /// Fracción del trabajo de separación vivo (null si indeterminada o sin trabajo).
  double? separationFractionFor(String projectId) {
    final j = jobs[projectId];
    return j != null && j.stage == JobStage.separation ? j.fraction : null;
  }

  /// Motivo del tooltip «Error»: el de `jobs.progress` `failed`; si no, el de la lista.
  String? separationErrorFor(ProjectSummary p) {
    final j = jobs[p.id];
    if (j != null && j.state == JobState.failed && j.error != null) return j.error;
    return p.separationError;
  }

  ImportState copyWith({
    Map<String, JobInfo>? jobs,
    Object? duplicateOf = _keep,
    Object? notice = _keep,
    bool? importing,
  }) => ImportState(
    jobs: jobs ?? this.jobs,
    duplicateOf: identical(duplicateOf, _keep) ? this.duplicateOf : duplicateOf as String?,
    notice: identical(notice, _keep) ? this.notice : notice as ImportNotice?,
    importing: importing ?? this.importing,
  );
}

final importStoreProvider = NotifierProvider<ImportStore, ImportState>(ImportStore.new);

class ImportStore extends Notifier<ImportState> {
  CoreClient get _core => ref.read(coreClientProvider);

  @override
  ImportState build() {
    final sub = _core.on<JobInfo>('jobs.progress', JobInfo.fromJson).listen(_onJob);
    ref.onDispose(sub.cancel);
    Future.microtask(_loadJobs);
    return const ImportState();
  }

  Future<void> _loadJobs() async {
    try {
      final r = await _core.call('jobs.list', const <String, Object?>{}, JobsListResult.fromJson);
      if (!ref.mounted) return;
      // Lo que llegó por evento mientras tanto es más reciente que la lista.
      final merged = {for (final j in r.jobs) j.id: j, ...state.jobs};
      state = state.copyWith(jobs: _alive(merged));
    } on CoreError {
      // sin lista de trabajos: se llenará con los eventos
    }
  }

  void _onJob(JobInfo j) {
    if (!ref.mounted) return;
    state = state.copyWith(jobs: _alive({...state.jobs, j.id: j}));
  }

  /// Quita los terminados salvo los fallidos de tema (conservan el motivo del tooltip).
  Map<String, JobInfo> _alive(Map<String, JobInfo> all) => {
    for (final e in all.entries)
      if (e.value.state == JobState.queued ||
          e.value.state == JobState.running ||
          (e.value.state == JobState.failed && !e.value.isImportJob && !e.value.isLinkJob))
        e.key: e.value,
  };

  void dismissDuplicate() => state = state.copyWith(duplicateOf: null);

  void dismissNotice() => state = state.copyWith(notice: null);

  /// Abre el selector del anfitrión e importa lo elegido.
  Future<void> pickAndImport() async {
    try {
      final r = await _core.call(
        'host.pickAudioFiles',
        const <String, Object?>{},
        PickedFilesResult.fromJson,
      );
      await importPaths(r.paths);
    } on CoreError catch (e) {
      _fail(e);
    }
  }

  /// Importa en serie las rutas wav/flac/mp3; el resto se ignora sin avisar.
  Future<void> importPaths(List<String> paths) async {
    final ok = paths.where(isImportablePath).toList();
    if (ok.isEmpty) return;
    state = state.copyWith(importing: true);
    for (final path in ok) {
      try {
        final r = await _core.call(
          'import.file',
          ImportFileParams(path: path).toJson(),
          ImportResult.fromJson,
        );
        if (!ref.mounted) return;
        if (r.duplicate) state = state.copyWith(duplicateOf: r.id);
      } on CoreError catch (e) {
        _fail(e);
      }
      if (!ref.mounted) return;
    }
    state = state.copyWith(importing: false);
  }

  void _fail(CoreError e) {
    if (ref.mounted) state = state.copyWith(notice: ImportNotice(code: e.code, message: e.message));
  }
}
