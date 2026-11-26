import 'package:toneforge/contract/record.dart';

import 'record_store.dart';

/// Lecturas de la hoja «Ajustar desfase» sobre el estado de Grabar.
extension RecordOffsetState on RecordState {
  /// `snapshot.offset`: no nulo = la hoja de desfase debe estar abierta (fase `adjusting` o menú de toma).
  RecordOffset? get offset => snapshot?.offset;

  /// Toma recién grabada y pendiente (rótulos «Descartar toma» / «Guardar toma»).
  bool get isNewOffsetTake => snapshot?.offset?.isNew ?? false;
}

class _Pending {
  _Pending({this.valueMs, this.deltaMs, this.frames});

  num? valueMs;
  num? deltaMs;
  num? frames;
}

class _Queue {
  bool inFlight = false;
  _Pending? pending;
}

final Expando<_Queue> _queues = Expando<_Queue>('offsetQueue');

/// Acciones del desfase. `setOffset` une cambios: con uno en vuelo solo se envía el último acumulado.
extension RecordOffsetActions on RecordStore {
  /// `record.adjustOffset {takeId}`: el snapshot trae `offset` y eso abre la hoja.
  Future<void> adjustOffset(String takeId) => act('record.adjustOffset', RecordTakeParams(takeId: takeId).toJson());

  /// `record.setOffset`. El núcleo recorta a ±500 ms. Con una petición en vuelo, los cambios se funden
  /// (un valor absoluto sustituye; los pasos se suman) y se envían como una sola al terminar.
  Future<void> setOffset({num? valueMs, num? deltaMs, int? frames}) async {
    final _Queue q = _queues[this] ??= _Queue();
    final _Pending next = _Pending(valueMs: valueMs, deltaMs: deltaMs, frames: frames);
    final _Pending? p = q.pending;
    if (q.inFlight) {
      q.pending = p == null ? next : _merge(p, next, offsetFrameMs);
      return;
    }
    q.inFlight = true;
    _Pending? cur = next;
    try {
      while (cur != null && isMounted) {
        await act('record.setOffset', RecordOffsetParams(valueMs: cur.valueMs, deltaMs: cur.deltaMs, frames: cur.frames).toJson());
        cur = q.pending;
        q.pending = null;
      }
    } finally {
      q.inFlight = false;
      q.pending = null;
    }
  }

  static _Pending _merge(_Pending a, _Pending b, num frameMs) {
    if (b.valueMs != null) return b;
    final num step = (b.deltaMs ?? 0) + (b.frames ?? 0) * frameMs;
    if (a.valueMs != null) return _Pending(valueMs: a.valueMs! + step);
    final bool onlyFrames = a.deltaMs == null && b.deltaMs == null;
    if (onlyFrames) return _Pending(frames: (a.frames ?? 0) + (b.frames ?? 0));
    return _Pending(deltaMs: (a.deltaMs ?? 0) + (a.frames ?? 0) * frameMs + step);
  }

  /// `record.finishOffset`. Cancelar envía `makeDefault: false`. Nueva+guardar guarda la toma; nueva+descartar
  /// la borra; existente+guardar fija el desfase; existente+cancelar no cambia nada (lo decide el núcleo).
  Future<void> finishOffset({required bool save, bool makeDefault = false}) =>
      act('record.finishOffset', RecordFinishOffsetParams(save: save, makeDefault: save && makeDefault).toJson());
}
