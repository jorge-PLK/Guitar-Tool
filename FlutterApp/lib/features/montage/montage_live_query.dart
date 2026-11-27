import 'dart:async';

/// Envío «último gana» para consultas de solo lectura durante un arrastre: como mucho una petición en vuelo;
/// si llegan más valores mientras tanto, solo se guarda el último y sale al volver la respuesta.
/// Cada respuesta se aplica salvo que el gesto haya terminado ([reset]) mientras volaba (número de secuencia).
class MontageLiveQuery<A, R> {
  MontageLiveQuery({required this.fetch, required this.onResult});

  final Future<R?> Function(A arg) fetch;
  final void Function(R result) onResult;

  int _gesture = 0;
  bool _busy = false;
  bool _hasPending = false;
  A? _pending;

  /// Peticiones enviadas desde el último [reset].
  int sent = 0;

  void push(A arg) {
    if (_busy) {
      _pending = arg;
      _hasPending = true;
      return;
    }
    unawaited(_send(arg));
  }

  /// Fin (o inicio) de un gesto: descarta lo pendiente y las respuestas en vuelo.
  void reset() {
    _gesture++;
    _hasPending = false;
    _pending = null;
    _busy = false;
    sent = 0;
  }

  Future<void> _send(A arg) async {
    final int gesture = _gesture;
    _busy = true;
    sent++;
    R? r;
    try {
      r = await fetch(arg);
    } catch (_) {
      r = null;
    }
    if (gesture != _gesture) return;
    _busy = false;
    if (r != null) onResult(r);
    if (_hasPending && gesture == _gesture) {
      final A next = _pending as A;
      _pending = null;
      _hasPending = false;
      unawaited(_send(next));
    }
  }
}
