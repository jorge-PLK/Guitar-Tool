import 'package:toneforge/l10n/app_localizations.dart';

/// Texto del aviso de salida de audio: traduce por [code] y cae a [fallback] (el `audioError` crudo
/// del núcleo) si el código es nulo o desconocido. Nulo si no hay ninguno de los dos.
String? audioErrorText(AppLocalizations l, String? code, String? fallback) {
  switch (code) {
    case 'not-connected':
      return l.audioErrorNotConnected;
    case 'sample-rate-mismatch':
      return l.audioErrorSampleRate;
    case 'busy':
      return l.audioErrorBusy;
    case 'unavailable':
      return l.audioErrorUnavailable;
  }
  return fallback;
}
