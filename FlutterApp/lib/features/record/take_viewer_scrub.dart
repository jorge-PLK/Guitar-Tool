import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reloj inyectable del arrastre del timeline (los tests lo sustituyen por uno falso).
class ScrubClock {
  const ScrubClock();

  DateTime now() => DateTime.now();

  Timer timer(Duration d, void Function() cb) => Timer(d, cb);
}

final scrubClockProvider = Provider<ScrubClock>((ref) => const ScrubClock());

/// Throttle con borde inicial y final (no debounce): como mucho un envío cada [interval]
/// mientras dura el arrastre; el último valor pendiente sale al vencer el intervalo.
class ScrubThrottle {
  ScrubThrottle(this._clock, this._send, {this.interval = const Duration(milliseconds: 80)});

  final ScrubClock _clock;
  final void Function(double) _send;
  final Duration interval;
  DateTime? _last;
  double? _pending;
  Timer? _timer;

  bool get active => _last != null;

  void push(double x) {
    _pending = x;
    final last = _last;
    if (last == null) return _flush();
    if (_timer != null) return;
    final wait = interval - _clock.now().difference(last);
    if (wait <= Duration.zero) return _flush();
    _timer = _clock.timer(wait, () {
      _timer = null;
      _flush();
    });
  }

  void _flush() {
    final x = _pending;
    if (x == null) return;
    _pending = null;
    _last = _clock.now();
    _send(x);
  }

  /// Fin del arrastre: cancela lo pendiente y reinicia; el llamante envía el seek final exacto.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _last = null;
  }
}
