import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../contract/record_state.dart' show RecordPhase;
import '../../../l10n/app_localizations.dart';
import '../../../theme/fmt.dart';
import '../../../theme/tokens.dart';
import '../../../theme/typography.dart';
import '../../../widgets/tf_card.dart';
import '../record_store.dart';
import 'punch_timeline_painter.dart';

/// Downbeat más cercano a [t] (`nearestBar`); sin downbeats, múltiplo de [barSeconds]. Sin umbral.
double nearestBar(double t, List<double> downbeats, num barSeconds) {
  if (downbeats.isNotEmpty) {
    var best = downbeats.first;
    for (final d in downbeats) {
      if ((d - t).abs() < (best - t).abs()) best = d;
    }
    return best;
  }
  return barSeconds > 0 ? (t / barSeconds).roundToDouble() * barSeconds : t;
}

enum _Handle { entry, exit }

/// Tarjeta «Punch-in»: resumen, zona de marcas y ayuda (PunchTimeline.swift). Solo con `punchEnabled`
/// (decide quien la monta). Bloqueada fuera de `idle`.
class PunchTimeline extends ConsumerStatefulWidget {
  const PunchTimeline({super.key});

  @override
  ConsumerState<PunchTimeline> createState() => _PunchTimelineState();
}

class _PunchTimelineState extends ConsumerState<PunchTimeline> {
  _Handle? _active;
  bool _dragging = false;
  num? _in;
  num? _out;
  double? _lastSent;

  String _fmt(num? t, String locale) {
    if (t == null) return '—';
    final m = t ~/ 60;
    final s = TfFmt.number((t % 60).toDouble(), 1, locale);
    return '$m:${(t % 60) < 10 ? '0' : ''}$s';
  }

  void _down(PointerDownEvent e, double width) {
    final p = ref.read(recordStoreProvider).snapshot?.punch;
    _dragging = true;
    _active = null;
    _lastSent = null;
    _in = p?.inSeconds;
    _out = p?.outSeconds;
    _move(e.localPosition.dx, width);
  }

  void _move(double dx, double width) {
    if (!_dragging) return;
    final snap = ref.read(recordStoreProvider).snapshot;
    if (snap == null) return;
    final d = snap.duration.toDouble();
    var t = (dx / math.max(width, 1) * d).clamp(0.0, d);
    final alt = HardwareKeyboard.instance.isAltPressed;
    if (!alt) t = nearestBar(t, snap.downbeats, snap.barSeconds).clamp(0.0, d);
    final a = _in, b = _out;
    _active ??= a == null
        ? _Handle.entry
        : b == null
            ? _Handle.exit
            : ((t - a).abs() <= (t - b).abs() ? _Handle.entry : _Handle.exit);
    final toExit = _active == _Handle.exit;
    setState(() {
      if (_active == _Handle.entry) {
        _in = t;
        if (b != null && t >= b) _out = null;
      } else if (a != null && t <= a) {
        _out = a;
        _in = t;
        _active = _Handle.entry;
      } else {
        _out = t;
      }
    });
    if (_lastSent == t) return;
    _lastSent = t;
    final notifier = ref.read(recordStoreProvider.notifier);
    // Mover la salida a <= entrada: el núcleo intercambia (mismo `exit: t`); aquí ya se ha reflejado en local.
    notifier.setPunchPoints(entry: toExit ? null : t, exit: toExit ? t : null, free: alt);
  }

  void _end() => setState(() {
        _dragging = false;
        _active = null;
      });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final st = ref.watch(recordStoreProvider);
    final snap = st.snapshot;
    final punch = snap?.punch;
    final entry = _dragging ? _in : punch?.inSeconds;
    final exit = _dragging ? _out : punch?.outSeconds;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final cursor = (st.phase != RecordPhase.idle || st.position > 0) ? st.position : null;
    final muted = TfText.body(12).copyWith(color: TfColors.muted);
    final help = Platform.isMacOS ? l.record_punchHelp_mac : l.record_punchHelp_win;
    return IgnorePointer(
      ignoring: st.isBusy,
      child: TfCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: TfSpace.s16, vertical: TfSpace.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Text(l.record_punchTitle, style: TfText.display(16).copyWith(color: TfColors.text)),
                const Spacer(),
                Text(
                  l.record_punchSummary(_fmt(entry, locale), _fmt(exit, locale)),
                  style: muted.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ]),
              const SizedBox(height: TfSpace.s8),
              LayoutBuilder(
                builder: (context, c) => Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => _down(e, c.maxWidth),
                  onPointerMove: (e) => _move(e.localPosition.dx, c.maxWidth),
                  onPointerUp: (_) => _end(),
                  onPointerCancel: (_) => _end(),
                  child: CustomPaint(
                    size: Size(c.maxWidth, PunchTimelinePainter.height),
                    painter: PunchTimelinePainter(
                      duration: snap?.duration ?? 0,
                      sections: snap?.sections ?? const [],
                      entry: entry,
                      exit: exit,
                      cursor: cursor,
                      entryLabel: l.record_punchEntryA11y,
                      exitLabel: l.record_punchExitA11y,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: TfSpace.s8),
              Text(help, style: muted),
            ],
          ),
        ),
      ),
    );
  }
}
