import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/tools.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';

const Object _keep = Object();

/// Estado de la actualización de yt-dlp.
enum YtDlpUpdateStatus { idle, updating, done, failed }

/// Estado de «Fuentes externas». Inmutable.
class SettingsToolsState {
  const SettingsToolsState({
    this.info,
    this.status = YtDlpUpdateStatus.idle,
    this.updateResult,
    this.error,
  });

  /// null → «comprobando…». Si `tools.info` falla queda vacío (todo «no disponible»).
  final ToolsInfoResult? info;
  final YtDlpUpdateStatus status;

  /// Con `status == done`: versión, origen y `alreadyLatest` (ok o «ya estaba al día»).
  final UpdateYtDlpResult? updateResult;

  /// Con `status == failed` (o fallo de `revertYtDlp`).
  final CoreError? error;

  bool get updating => status == YtDlpUpdateStatus.updating;

  /// «Volver a la embebida» solo si hay una actualizada y no se está actualizando.
  bool get canRevert => !updating && info?.ytDlpOrigin == YtDlpOrigin.updated;

  SettingsToolsState copyWith({
    Object? info = _keep,
    YtDlpUpdateStatus? status,
    Object? updateResult = _keep,
    Object? error = _keep,
  }) => SettingsToolsState(
    info: identical(info, _keep) ? this.info : info as ToolsInfoResult?,
    status: status ?? this.status,
    updateResult: identical(updateResult, _keep) ? this.updateResult : updateResult as UpdateYtDlpResult?,
    error: identical(error, _keep) ? this.error : error as CoreError?,
  );
}

final settingsToolsStoreProvider =
    NotifierProvider<SettingsToolsStore, SettingsToolsState>(SettingsToolsStore.new);

class SettingsToolsStore extends Notifier<SettingsToolsState> {
  CoreClient get _core => ref.read(coreClientProvider);

  @override
  SettingsToolsState build() {
    Future.microtask(loadInfo);
    return const SettingsToolsState();
  }

  Future<void> loadInfo() async {
    try {
      final r = await _core.call('tools.info', const <String, Object?>{}, ToolsInfoResult.fromJson);
      if (ref.mounted) state = state.copyWith(info: r);
    } on CoreError {
      if (ref.mounted) state = state.copyWith(info: const ToolsInfoResult());
    }
  }

  /// «Actualizar yt-dlp»: barra indeterminada mientras dura; después recarga `tools.info`.
  Future<void> updateYtDlp() async {
    if (state.updating) return;
    state = state.copyWith(status: YtDlpUpdateStatus.updating, updateResult: null, error: null);
    try {
      final r = await _core.call(
        'tools.updateYtDlp',
        const <String, Object?>{},
        UpdateYtDlpResult.fromJson,
      );
      if (!ref.mounted) return;
      state = state.copyWith(status: YtDlpUpdateStatus.done, updateResult: r);
    } on CoreError catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(status: YtDlpUpdateStatus.failed, error: e);
    }
    await loadInfo();
  }

  /// «Volver a la embebida». Devuelve null si fue bien.
  Future<CoreError?> revertYtDlp() async {
    if (state.updating) return null;
    try {
      await _core.call('tools.revertYtDlp', const <String, Object?>{}, RevertedResult.fromJson);
      if (!ref.mounted) return null;
      state = state.copyWith(status: YtDlpUpdateStatus.idle, updateResult: null, error: null);
      await loadInfo();
      return null;
    } on CoreError catch (e) {
      if (ref.mounted) state = state.copyWith(status: YtDlpUpdateStatus.failed, error: e);
      return e;
    }
  }
}
