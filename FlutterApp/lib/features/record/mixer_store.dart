import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/record.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';

import 'record_store.dart';

const Object _keep = Object();

/// Rango del fader (`BackingController.faderRange`).
const double kFaderMinDb = -60;
const double kFaderMaxDb = 6;

/// Imán a 0 dB del Master (G6, solo en cliente): `|v| < 1,5` pasa a 0.
const double kFaderSnapDb = 1.5;

/// Valor de fader acotado al rango y con el imán a 0 dB.
double snapFaderDb(num v) {
  final c = v.toDouble().clamp(kFaderMinDb, kFaderMaxDb);
  return c.abs() < kFaderSnapDb ? 0 : c;
}

/// Mezclador de Grabar: `mix` del snapshot y niveles de `record.levels`.
class MixerState {
  const MixerState({this.mix, this.levels = const {}, this.error});

  final RecordMix? mix;

  /// Nivel por id de canal (`record.levels`), en dBFS; -120 = silencio.
  final Map<String, RecordLevel> levels;
  final CoreError? error;

  List<RecordMixChannel> get channels => mix?.channels ?? const [];
  List<RecordTakeChannel> get takeChannels => mix?.takeChannels ?? const [];
  num get masterGainDB => mix?.masterGainDB ?? 0;
  bool get anySolo => mix?.anySolo ?? false;

  MixerState copyWith({Object? mix = _keep, Map<String, RecordLevel>? levels, Object? error = _keep}) => MixerState(
        mix: identical(mix, _keep) ? this.mix : mix as RecordMix?,
        levels: levels ?? this.levels,
        error: identical(error, _keep) ? this.error : error as CoreError?,
      );
}

final mixerStoreProvider = NotifierProvider<MixerStore, MixerState>(MixerStore.new);

class MixerStore extends Notifier<MixerState> {
  CoreClient get _core => ref.read(coreClientProvider);

  @override
  MixerState build() {
    ref.listen<RecordMix?>(
      recordStoreProvider.select((s) => s.snapshot?.mix),
      (_, m) => state = state.copyWith(mix: m),
    );
    final sub = _core.on('record.levels', RecordLevelsEvent.fromJson).listen((e) {
      state = state.copyWith(levels: e.channels);
    });
    ref.onDispose(sub.cancel);
    return MixerState(mix: ref.read(recordStoreProvider).snapshot?.mix);
  }

  /// Ganancia de un canal (stem, guitarra o `take-<partId>`), acotada al rango del fader.
  Future<void> setGain(String channel, num gainDB) =>
      _setMix(RecordMixParams(channel: channel, gainDB: gainDB.toDouble().clamp(kFaderMinDb, kFaderMaxDb)));

  /// Silencio de un canal; no actúa en la guitarra que sustituye la parte (`forcedMuted`).
  Future<void> setMute(String channel, bool mute) async {
    if (_forced(channel)) return;
    await _setMix(RecordMixParams(channel: channel, mute: mute));
  }

  Future<void> setSolo(String channel, bool solo) async {
    if (_forced(channel)) return;
    await _setMix(RecordMixParams(channel: channel, solo: solo));
  }

  /// Master: actualización optimista con imán a 0 dB y rango −60…+6.
  Future<void> setMaster(num gainDB) async {
    final v = snapFaderDb(gainDB);
    final m = state.mix;
    if (m == null) return;
    state = state.copyWith(
      mix: RecordMix(
        anySolo: m.anySolo,
        channels: m.channels,
        masterGainDB: v,
        outputName: m.outputName,
        takeChannels: m.takeChannels,
      ),
    );
    await _send('record.setMaster', RecordMasterParams(gainDB: v).toJson());
  }

  bool _forced(String id) => state.channels.any((c) => c.id == id && c.forcedMuted);

  Future<void> _setMix(RecordMixParams p) => _send('record.setMix', p.toJson());

  Future<void> _send(String method, Object? params) async {
    try {
      final s = await _core.call(method, params, RecordSnapshot.fromJson);
      if (!ref.mounted) return;
      state = state.copyWith(error: null);
      ref.read(recordStoreProvider.notifier).applySnapshot(s);
    } on CoreError catch (e) {
      if (!ref.mounted) return;
      // Deshace lo optimista con el último estado del núcleo; `not-open` no se muestra.
      state = state.copyWith(
        mix: ref.read(recordStoreProvider).snapshot?.mix,
        error: e.code == 'not-open' ? null : e,
      );
    }
  }
}
