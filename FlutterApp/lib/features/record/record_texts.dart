import '../../contract/core_message.dart';
import '../../contract/record.dart';
import '../../l10n/app_localizations.dart';

/// Texto de un bloqueo de grabación por código (`record-block-*`); código desconocido: `message`.
String recordBlockText(AppLocalizations l, CoreMessage m) {
  num arg(String k) => (m.args[k] as num?) ?? 0;
  // kHz sin «.0» sobrante: 48000 -> 48, 44100 -> 44.1.
  num khz(String k) {
    final double v = arg(k) / 1000;
    return v == v.roundToDouble() ? v.toInt() : v;
  }
  return switch (m.code) {
    'record-block-busy' => l.record_block_busy,
    'record-block-invalid-channels' => l.record_block_invalidChannels,
    'record-block-input-disconnected' => l.record_block_inputDisconnected,
    'record-block-loop' => l.record_block_loop,
    'record-block-no-guitar-input' => l.record_block_noGuitarInput,
    'record-block-no-input-device' => l.record_block_noInputDevice,
    'record-block-no-part' => l.record_block_noPart,
    'record-block-output-disconnected' => l.record_block_outputDisconnected,
    'record-block-punch-no-marks' => l.record_block_punchNoMarks,
    'record-block-punch-no-take' => l.record_block_punchNoTake,
    // El núcleo manda Hz; la clave ARB lleva «kHz» tras el número.
    'record-block-rate-mismatch' => l.record_block_rateMismatch(khz('deviceHz'), khz('workingHz')),
    'record-block-session-unavailable' =>
      m.args['detail'] is String ? l.record_block_sessionUnavailable(m.args['detail']! as String) : m.message,
    'record-block-speed' => l.record_block_speed(arg('rate')),
    _ => m.message,
  };
}

/// Línea de estado de la cámara (RV:174-176); `null` si hay cámara (live/simulated) o no se sabe.
String? recordCameraLine(AppLocalizations l, RecordCamera c) => switch (c.state) {
      CameraState.denied => l.record_cameraDenied,
      CameraState.none || CameraState.failed => l.record_cameraAudioOnly(
          (c.message?.isNotEmpty ?? false) ? c.message! : l.record_cameraNone),
      _ => null,
    };

/// «Desfase de la cámara: …»; 0 ms equivale a «sin ajustar» (el contrato no distingue nulo).
String recordOffsetText(AppLocalizations l, int ms) {
  if (ms == 0) return l.record_offsetUnset;
  return l.record_offsetValue(ms > 0 ? '+$ms' : '−${-ms}');
}
