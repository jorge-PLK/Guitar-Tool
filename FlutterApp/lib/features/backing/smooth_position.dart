import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/study_position.dart';
import 'package:toneforge/features/backing/study_store.dart';

/// Posición bajo el puntero durante el arrastre de la barra (SwiftUI `scrub ?? time`). Null si no se arrastra.
final scrubPositionProvider =
    NotifierProvider<ScrubPositionNotifier, double?>(ScrubPositionNotifier.new);

class ScrubPositionNotifier extends Notifier<double?> {
  @override
  double? build() => null;

  void set(double? seconds) => state = seconds;
}

/// Retroceso máximo (s) respecto a lo extrapolado que se trata como jitter de `study.position` y se ignora.
const double _jitterTolerance = 0.06;

/// Reconstruye [builder] a cada fotograma con la posición suavizada: ancla en cada `study.position` y
/// extrapola `seconds + dt * rate` solo mientras suena. Con arrastre activo ([scrubPositionProvider])
/// entrega la posición del puntero. Sin Ticker activo cuando no suena.
class SmoothPositionBuilder extends ConsumerStatefulWidget {
  const SmoothPositionBuilder({required this.builder, super.key});

  final Widget Function(BuildContext context, double seconds) builder;

  @override
  ConsumerState<SmoothPositionBuilder> createState() => _SmoothPositionBuilderState();
}

class _SmoothPositionBuilderState extends ConsumerState<SmoothPositionBuilder>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  late final ValueNotifier<double> _value;
  double _anchorSeconds = 0;
  Duration _anchorAt = Duration.zero;
  Duration _last = Duration.zero;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    final StudyPositionEvent e = ref.read(studyPositionProvider);
    _value = ValueNotifier<double>(e.seconds);
    _anchor(e.seconds, e.playing);
    ref.listenManual(studyPositionProvider, (_, StudyPositionEvent e) => _onEvent(e));
    ref.listenManual<double?>(scrubPositionProvider, (double? prev, double? next) {
      // Al soltar, el cabezal se queda donde se soltó hasta que el núcleo responda.
      if (prev != null && next == null) _anchor(prev, _playing);
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _value.dispose();
    super.dispose();
  }

  void _onEvent(StudyPositionEvent e) {
    if (e.playing && _playing) {
      final double behind = _extrapolated() - e.seconds;
      if (behind > 0 && behind < _jitterTolerance) return;
    }
    _anchor(e.seconds, e.playing);
  }

  void _anchor(double seconds, bool playing) {
    _anchorSeconds = seconds;
    _playing = playing;
    if (playing) {
      if (!_ticker.isActive) {
        _last = Duration.zero;
        _ticker.start();
      }
      _anchorAt = _last;
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
    _value.value = _extrapolated();
  }

  void _onTick(Duration elapsed) {
    _last = elapsed;
    _value.value = _extrapolated();
  }

  double _extrapolated() {
    if (!_playing) return _anchorSeconds;
    final transport = ref.read(studyStoreProvider).transport;
    final double rate = transport?.rate ?? 1;
    double s = _anchorSeconds + (_last - _anchorAt).inMicroseconds / 1e6 * rate;
    final loop = transport?.loop;
    if (loop != null && _anchorSeconds >= loop.start && _anchorSeconds <= loop.end && s > loop.end) {
      s = loop.end;
    }
    final double duration = transport?.duration ?? 0;
    if (duration > 0 && s > duration) s = duration;
    return s < _anchorSeconds ? _anchorSeconds : s;
  }

  @override
  Widget build(BuildContext context) {
    final double? scrub = ref.watch(scrubPositionProvider);
    return ValueListenableBuilder<double>(
      valueListenable: _value,
      builder: (BuildContext c, double v, _) => widget.builder(c, scrub ?? v),
    );
  }
}
