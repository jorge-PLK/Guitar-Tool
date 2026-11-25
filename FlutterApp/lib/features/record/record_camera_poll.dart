import 'dart:async';

/// Periodo del re-sondeo de cámara (SwiftUI `slowTick`, RecordView.swift:99).
const Duration kCameraPollInterval = Duration(seconds: 2);

/// Temporizador de `record.pollCamera`: sin solapes y sin romperse por errores.
class CameraPoller {
  CameraPoller(this._poll);

  final Future<void> Function() _poll;
  Timer? _timer;
  bool _inFlight = false;

  bool get running => _timer != null;

  void start() {
    _timer ??= Timer.periodic(kCameraPollInterval, (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      await _poll();
    } on Object {
      // Se ignora: se reintenta en el siguiente tick.
    } finally {
      _inFlight = false;
    }
  }
}
