/// M-6 (desvío de SwiftUI, decisión de Jorge 26/11/2026): umbral de pico a partir del cual
/// «Tu guitarra» avisa de tope.
const double clipThresholdDB = -3;

/// M-6: tiempo que el aviso sigue encendido tras la última muestra caliente (a 20 Hz no se vería).
const Duration clipHoldDuration = Duration(seconds: 1);

/// Lo que pintan los medidores de «Tu guitarra»: nivel RMS 0…1 y aviso de tope.
class InputMeter {
  const InputMeter(this.level, {this.hot = false});

  static const InputMeter silent = InputMeter(0);

  final double level;
  final bool hot;

  @override
  bool operator ==(Object other) => other is InputMeter && other.level == level && other.hot == hot;

  @override
  int get hashCode => Object.hash(level, hot);
}

/// M-6: mantiene el aviso de tope `clipHoldDuration` desde la última muestra con pico ≥ `clipThresholdDB`.
class ClipHold {
  ClipHold({this.threshold = clipThresholdDB, this.hold = clipHoldDuration});

  final double threshold;
  final Duration hold;
  DateTime? _lastHot;

  /// Registra una muestra de pico (dBFS) en `now` y devuelve si el aviso está encendido.
  bool update(double peakDB, DateTime now) {
    if (peakDB >= threshold) _lastHot = now;
    final DateTime? last = _lastHot;
    return last != null && now.difference(last) < hold;
  }

  void reset() => _lastHot = null;
}
