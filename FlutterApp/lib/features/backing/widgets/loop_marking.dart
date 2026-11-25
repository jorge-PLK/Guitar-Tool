import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/backing/study_position.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/position_bar.dart';

/// Inicio de bucle pendiente (`pendingLoopStart`, BT): estado de vista, no del núcleo.
/// Se borra al cambiar de estudio.
final pendingLoopStartProvider =
    NotifierProvider<PendingLoopStartNotifier, double?>(PendingLoopStartNotifier.new);

class PendingLoopStartNotifier extends Notifier<double?> {
  @override
  double? build() {
    ref.watch(studyStoreProvider.select((s) => s.openProjectId));
    return null;
  }

  void set(double? seconds) => state = seconds;
}

/// «Inicio» (BT:412-417): con bucle y la posición antes de su fin, mueve el inicio del bucle; si no,
/// deja el inicio pendiente.
void markLoopStart(WidgetRef ref) {
  final double time = ref.read(studyPositionProvider).seconds;
  final loop = ref.read(studyStoreProvider).transport?.loop;
  final PendingLoopStartNotifier pending = ref.read(pendingLoopStartProvider.notifier);
  if (loop != null && time < loop.end) {
    pending.set(null);
    unawaited(ref.read(studyStoreProvider.notifier).setLoop(time, loop.end, name: loop.name));
  } else {
    pending.set(time);
  }
}

/// «Fin» (BT:419-425): con inicio pendiente crea un bucle libre; con bucle, mueve su fin.
void markLoopEnd(WidgetRef ref) {
  final double time = ref.read(studyPositionProvider).seconds;
  final loop = ref.read(studyStoreProvider).transport?.loop;
  final double? start = ref.read(pendingLoopStartProvider);
  final StudyStore store = ref.read(studyStoreProvider.notifier);
  if (start != null && time > start) {
    unawaited(store.setLoop(start, time));
    ref.read(pendingLoopStartProvider.notifier).set(null);
  } else if (loop != null && time > loop.start) {
    unawaited(store.setLoop(loop.start, time, name: loop.name));
  }
}

/// Limita los seeks del arrastre (`SCRUB_INTERVAL_MS`): una petición en vuelo, la última gana y
/// al menos [interval] entre envíos. La última posición pedida siempre acaba enviándose.
class SeekCoalescer {
  SeekCoalescer(this._send, {this.interval = const Duration(milliseconds: 120)});

  final Future<void> Function(double seconds) _send;
  final Duration interval;
  Timer? _timer;
  double? _pending;
  bool _inFlight = false;

  void request(double seconds) {
    _pending = seconds;
    _flush();
  }

  void _flush() {
    final double? p = _pending;
    if (p == null || _inFlight || _timer != null) return;
    _pending = null;
    _inFlight = true;
    _timer = Timer(interval, () {
      _timer = null;
      _flush();
    });
    _send(p).catchError((Object _) {}).whenComplete(() {
      _inFlight = false;
      _flush();
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }
}

/// [PositionBar] conectada al store: posición, bucle y seek coalescido.
class CoalescedPositionBar extends ConsumerStatefulWidget {
  const CoalescedPositionBar({super.key});

  @override
  ConsumerState<CoalescedPositionBar> createState() => _CoalescedPositionBarState();
}

class _CoalescedPositionBarState extends ConsumerState<CoalescedPositionBar> {
  late final SeekCoalescer _seek = SeekCoalescer(ref.read(studyStoreProvider.notifier).seek);

  @override
  void dispose() {
    _seek.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double position = ref.watch(studyPositionProvider.select((e) => e.seconds));
    final transport = ref.watch(studyStoreProvider.select((s) => s.transport));
    return PositionBar(
      position: position,
      duration: transport?.duration ?? 0,
      loopStart: transport?.loop?.start,
      loopEnd: transport?.loop?.end,
      onSeek: _seek.request,
    );
  }
}
