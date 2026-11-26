import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/fmt.dart';
import '../../../theme/icons.dart';
import '../../../theme/tokens.dart';
import '../../../theme/typography.dart';
import '../../../widgets/tf_slider.dart';
import '../../../widgets/tf_tooltip.dart';
import '../take_viewer_store.dart';

/// Controles del visor «Ver toma» (TV:334-359): ▶/pausa, posición, `TfSlider`, duración y «Backing».
/// La posición se extrapola con un `Ticker` desde el último evento (`positionAt`); no se pide al núcleo.
/// [enabled] false deshabilita todos los controles (cargando o error del visor).
class ViewerControls extends ConsumerStatefulWidget {
  const ViewerControls({super.key, required this.enabled});

  final bool enabled;

  @override
  ConsumerState<ViewerControls> createState() => _ViewerControlsState();
}

class _ViewerControlsState extends ConsumerState<ViewerControls> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  // Reloj local del ticker: «ahora» (en la escala de `at`) = `at` + tiempo transcurrido desde el último evento.
  Duration _lastTick = Duration.zero;
  Duration _anchorTick = Duration.zero;
  final ValueNotifier<double> _pos = ValueNotifier<double>(0);
  double? _drag;
  late TakeViewerState _anchor;

  @override
  void initState() {
    super.initState();
    _anchor = ref.read(takeViewerStoreProvider);
    _reanchor(_anchor);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _pos.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    _lastTick = elapsed;
    if (_drag != null) return;
    final double dt = (elapsed - _anchorTick).inMicroseconds / 1e6;
    _pos.value = _anchor.positionAt(_anchor.at + dt);
  }

  void _reanchor(TakeViewerState s) {
    _anchor = s;
    if (_drag == null) _pos.value = s.position;
    if (s.playing && s.rate > 0) {
      if (!_ticker.isActive) {
        _lastTick = Duration.zero;
        _ticker.start();
      }
      _anchorTick = _lastTick;
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<TakeViewerState>(takeViewerStoreProvider, (TakeViewerState? p, TakeViewerState n) {
      if (p == null ||
          p.position != n.position ||
          p.at != n.at ||
          p.epoch != n.epoch ||
          p.playing != n.playing ||
          p.rate != n.rate) {
        _reanchor(n);
      }
    });
    final TakeViewerState s = ref.watch(takeViewerStoreProvider);
    final TakeViewerStore store = ref.read(takeViewerStoreProvider.notifier);
    final AppLocalizations l = AppLocalizations.of(context);
    final bool on = widget.enabled;
    final double max = s.duration > 0.1 ? s.duration : 0.1;
    final TextStyle timeStyle = TfText.body(TfSize.font12, TfWeight.regular, true).copyWith(color: TfColors.muted);
    return Row(
      spacing: TfSpace.s12,
      children: <Widget>[
        _RoundButton(
          key: const ValueKey<String>('viewer-play'),
          playing: s.playing,
          label: s.playing ? l.takeview_pause : l.takeview_play,
          onTap: on ? store.togglePlay : null,
        ),
        ValueListenableBuilder<double>(
          valueListenable: _pos,
          builder: (BuildContext _, double v, Widget? _) => Text(TfFmt.clock(v), style: timeStyle),
        ),
        Expanded(
          child: Semantics(
            label: l.takeview_position,
            child: ValueListenableBuilder<double>(
              valueListenable: _pos,
              builder: (BuildContext _, double v, Widget? _) => TfSlider(
                value: v.clamp(0.0, max).toDouble(),
                max: max,
                onChanged: on ? (double x) => _setDrag(x, store) : null,
                onChangeEnd: on
                    ? (double x) {
                        _drag = null;
                        _pos.value = x;
                        store.scrubEnd(x);
                      }
                    : null,
              ),
            ),
          ),
        ),
        Text(TfFmt.clock(s.duration), style: timeStyle),
        _BackingButton(
          key: const ValueKey<String>('viewer-backing'),
          muted: !s.backingOn,
          enabled: on && s.canToggleBacking,
          label: s.backingOn ? l.takeview_backing : l.takeview_backingMuted,
          help: s.backingOn ? l.takeview_backingMuteHelp : l.takeview_backingUnmuteHelp,
          onTap: () => store.setBacking(!s.backingOn),
        ),
      ],
    );
  }

  void _setDrag(double x, TakeViewerStore store) {
    _drag = x;
    _pos.value = x;
    store.scrub(x);
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({super.key, required this.playing, required this.label, required this.onTap});

  final bool playing;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget circle = SizedBox.square(
      dimension: TfSize.controlMd,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: TfColors.accent, shape: BoxShape.circle),
        child: Center(
          child: TfIconView(playing ? TfIcon.pauseFill : TfIcon.playFill, size: TfSize.viewerPlayIcon, color: TfColors.accentInk, filled: true),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: onTap == null
          ? Opacity(opacity: TfOpacity.disabled, child: circle)
          : GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: circle),
    );
  }
}

class _BackingButton extends StatelessWidget {
  const _BackingButton({
    super.key,
    required this.muted,
    required this.enabled,
    required this.label,
    required this.help,
    required this.onTap,
  });

  final bool muted;
  final bool enabled;
  final String label;
  final String help;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color fg = muted ? TfColors.accent : TfColors.text2;
    final Widget box = DecoratedBox(
      decoration: BoxDecoration(
        color: TfColors.field,
        borderRadius: BorderRadius.circular(TfRadius.field),
        border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
      ),
      child: SizedBox(
        height: TfSpace.s32,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: TfSpace.s10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: TfSpace.s6,
            children: <Widget>[
              TfIconView(muted ? TfIcon.speakerSlashFill : TfIcon.speakerWave2Fill, size: TfSize.font12, color: fg, filled: true),
              Text(label, style: TfText.body(TfSize.font12, TfWeight.semibold).copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: enabled
          ? TfTooltip(
              message: help,
              child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: box),
            )
          : Opacity(opacity: TfOpacity.disabled, child: box),
    );
  }
}
