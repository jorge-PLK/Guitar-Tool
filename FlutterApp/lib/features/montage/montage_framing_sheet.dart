import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contract/montage.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/fmt.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/tf_buttons.dart';
import '../../widgets/tf_progress.dart';
import '../../widgets/tf_sheet.dart';
import '../../widgets/tf_slider.dart';
import '../../widgets/tf_switch.dart';
import 'montage_framing_controls.dart';
import 'montage_store.dart';
import 'widgets/framing_box_painter.dart';

/// Abre la hoja «Encuadre» de la toma [takeId].
Future<void> showMontageFramingSheet(BuildContext context, String takeId) =>
    showTfSheet<void>(context: context, builder: (BuildContext _) => MontageFramingSheet(takeId: takeId));

/// Hoja «Encuadre» (FS): fotograma con la caja, modo seguir y ajuste manual.
/// [frameBuilder] sustituye a `Image.file` (tests).
class MontageFramingSheet extends ConsumerStatefulWidget {
  const MontageFramingSheet({super.key, required this.takeId, this.frameBuilder});

  final String takeId;
  final Widget Function(MontageFrame frame)? frameBuilder;

  @override
  ConsumerState<MontageFramingSheet> createState() => _MontageFramingSheetState();
}

class _MontageFramingSheetState extends ConsumerState<MontageFramingSheet> {
  static const Duration _debounce = Duration(milliseconds: 80);
  static const double _width = 760;
  static const double _instantValueWidth = 44;
  static const double _defaultAspect = 16 / 9;
  static const double _zoomMin = 0.5;
  static const double _zoomMax = 3;
  static const double _offsetMax = 0.5;

  double _time = 0;
  MontageFrame? _frame;
  Timer? _frameTimer;
  Timer? _followTimer;
  int _seq = 0;

  // Arrastre en curso.
  Rect? _dragBase;
  bool _dragResizes = false;
  Rect? _dragBox;
  MontageOffsetInfo? _offsetBase;
  MontageOffsetInfo? _dragOffset;

  // Valores locales del modo seguir mientras se mueven los deslizadores.
  double? _zoom;
  MontageOffsetInfo? _offset;

  MontageStore get _store => ref.read(montageStoreProvider.notifier);

  MontageLaneInfo? get _lane {
    for (final MontageLaneInfo l in ref.read(montageStoreProvider).snapshot?.lanes ?? const <MontageLaneInfo>[]) {
      if (l.takeId == widget.takeId) return l;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final MontageLaneInfo? lane = _lane;
    if (lane != null) {
      final MontageRangeInfo p = lane.presence.isNotEmpty ? lane.presence.first : lane.take;
      _time = (p.start + p.end) / 2;
    }
    _scheduleFrame();
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _followTimer?.cancel();
    super.dispose();
  }

  void _scheduleFrame() {
    _frameTimer?.cancel();
    _frameTimer = Timer(_debounce, _requestFrame);
  }

  Future<void> _requestFrame() async {
    final int seq = ++_seq;
    final MontageFrame? f = await _store.framingFrame(widget.takeId, _time);
    if (!mounted || seq != _seq || f == null) return;
    setState(() => _frame = f);
  }

  MontageFramingInfo? _info(MontageState s) {
    for (final MontageFramingInfo f in s.snapshot?.framing ?? const <MontageFramingInfo>[]) {
      if (f.takeId == widget.takeId) return f;
    }
    return null;
  }

  Future<void> _apply({String? mode, MontageBoxInfo? box, double? zoom, MontageOffsetInfo? offset}) async {
    await _store.setFraming(widget.takeId, mode: mode, manualBox: box, followZoom: zoom, followOffset: offset);
    if (!mounted) return;
    setState(() {
      _dragBox = null;
      _dragOffset = null;
      _zoom = null;
      _offset = null;
    });
    _scheduleFrame();
  }

  void _commitFollowSoon() {
    _followTimer?.cancel();
    _followTimer = Timer(_debounce, () => _apply(zoom: _zoom, offset: _offset));
  }

  Rect _effectiveBox(MontageFramingInfo? info) {
    final MontageBoxInfo? m = info?.manualBox;
    if (_dragBox != null) return _dragBox!;
    if (info?.mode == 'follow') return _boxOf(_frame?.result.box);
    return _boxOf(m ?? _frame?.result.box);
  }

  Rect _boxOf(MontageBoxInfo? b) => b == null ? const Rect.fromLTWH(0, 0, 1, 1) : Rect.fromLTWH(b.x, b.y, b.width, b.height);

  double get _aspect {
    final MontageFrame? f = _frame;
    return f == null || f.result.height == 0 ? _defaultAspect : f.result.width / f.result.height;
  }

  void _dragStart(Offset start, Size size, MontageFramingInfo? info) {
    if (info?.mode == 'follow') {
      _offsetBase = info?.followOffset ?? const MontageOffsetInfo(x: 0, y: 0);
      return;
    }
    final Rect base = _effectiveBox(info);
    _dragBase = base;
    _dragResizes = FramingBoxGeometry(base, size).hitsHandle(start);
  }

  void _dragUpdate(Offset t, Size size, MontageFramingInfo? info) {
    if (size.width <= 0 || size.height <= 0) return;
    final double dx = t.dx / size.width, dy = t.dy / size.height;
    if (info?.mode == 'follow') {
      final MontageOffsetInfo? base = _offsetBase;
      if (base == null) return;
      setState(() => _dragOffset = MontageOffsetInfo(
            x: FramingBoxMath.clampTo(base.x + dx, -_offsetMax, _offsetMax),
            y: FramingBoxMath.clampTo(base.y + dy, -_offsetMax, _offsetMax),
          ));
      return;
    }
    final Rect? base = _dragBase;
    if (base == null) return;
    setState(() => _dragBox = _dragResizes ? FramingBoxMath.resized(base, dx, _aspect) : FramingBoxMath.moved(base, dx, dy));
  }

  void _dragEnd() {
    final Rect? box = _dragBox;
    final MontageOffsetInfo? off = _dragOffset;
    _dragBase = null;
    _dragResizes = false;
    _offsetBase = null;
    if (box != null) {
      _apply(box: MontageBoxInfo(x: box.left, y: box.top, width: box.width, height: box.height));
    } else if (off != null) {
      _apply(offset: off);
    }
  }

  Widget _image(AppLocalizations l) {
    final MontageFrame? f = _frame;
    Widget empty() => Center(
          child: Text(l.montageFramingNoImage, style: TfText.body(TfSize.font13).copyWith(color: TfColors.muted)),
        );
    if (f == null) return empty();
    if (widget.frameBuilder != null) return widget.frameBuilder!(f);
    return Image.file(File(f.absolutePath), fit: BoxFit.fill, gaplessPlayback: true, errorBuilder: (_, _, _) => empty());
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MontageState state = ref.watch(montageStoreProvider);
    final MontageLaneInfo? lane = _lane;
    final MontageFramingInfo? info = _info(state);
    final bool follow = info?.mode == 'follow';
    final MontageFramingStatus? status = state.framingStatus(widget.takeId);
    final bool analyzing = status == MontageFramingStatus.analyzing;
    final bool busy = analyzing || status == MontageFramingStatus.pending;
    final String title = l.montageFramingTitle(lane?.partName ?? '');
    final double zoom = _zoom ?? info?.followZoom ?? 1;
    final MontageOffsetInfo offset = _dragOffset ?? _offset ?? info?.followOffset ?? const MontageOffsetInfo(x: 0, y: 0);

    return Semantics(
      container: true,
      explicitChildNodes: true,
      scopesRoute: true,
      namesRoute: true,
      label: title,
      child: SizedBox(
        width: _width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: TfColors.card,
            borderRadius: BorderRadius.circular(TfRadius.card),
            border: Border.all(color: TfColors.line, width: TfStroke.hairline),
          ),
          child: Padding(
            padding: const EdgeInsets.all(TfSpace.s24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TfSpace.s12,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(child: Text(title, style: TfText.display(20).copyWith(color: TfColors.text))),
                    Text(l.montageFramingFollow, style: TfText.body(TfSize.font13).copyWith(color: TfColors.text)),
                    const SizedBox(width: TfSpace.s10),
                    TfSwitch(
                      value: follow,
                      semanticLabel: l.montageFramingFollow,
                      onChanged: (bool on) => _apply(mode: on ? 'follow' : 'fixed'),
                    ),
                  ],
                ),
                if (busy)
                  Row(
                    spacing: TfSpace.s10,
                    children: <Widget>[
                      const TfSpinner.small(),
                      // TODO(l10n): texto de estado del análisis («Analizando la guitarra… NN %»): sin clave en ola4-claves.
                      Expanded(child: TfProgress(value: state.framingProgress(widget.takeId) ?? 0)),
                    ],
                  ),
                FramingFrameArea(
                  aspect: _aspect,
                  box: _effectiveBox(info),
                  showHandle: !follow,
                  image: _image(l),
                  onDragStart: (Offset s, Size z) => _dragStart(s, z, info),
                  onDragUpdate: (Offset t, Size z) => _dragUpdate(t, z, info),
                  onDragEnd: _dragEnd,
                ),
                if (lane != null)
                  Row(
                    spacing: TfSpace.s10,
                    children: <Widget>[
                      Text(l.montageFramingInstant, style: TfText.body(TfSize.font13).copyWith(color: TfColors.muted)),
                      Expanded(
                        child: TfSlider(
                          value: FramingBoxMath.clampTo(_time, lane.take.start, _instantMax(lane)),
                          min: lane.take.start,
                          max: _instantMax(lane),
                          onChanged: (double v) {
                            setState(() => _time = v);
                            _scheduleFrame();
                          },
                        ),
                      ),
                      SizedBox(
                        width: _instantValueWidth,
                        child: Text(
                          TfFmt.duration(_time),
                          textAlign: TextAlign.right,
                          style: TfText.body(TfSize.font13, TfWeight.regular, true).copyWith(color: TfColors.text),
                        ),
                      ),
                    ],
                  ),
                if (!follow)
                  Text(
                    info?.manualBox == null ? l.montageFramingFixedHelp : l.montageFramingFixedHelpManual,
                    style: TfText.body(TfSize.font12).copyWith(color: TfColors.muted),
                  )
                else
                  ..._followControls(l, zoom, offset),
                Row(
                  spacing: TfSpace.s12,
                  children: <Widget>[
                    TfSecondaryButton(
                      label: l.montageFramingReset,
                      onPressed: () async {
                        await _store.resetFraming(widget.takeId);
                        _scheduleFrame();
                      },
                    ),
                    TfSecondaryButton(
                      label: l.montageFramingReanalyze,
                      onPressed: analyzing ? null : () => _store.reanalyze(widget.takeId),
                    ),
                    const Spacer(),
                    TfPrimaryButton(label: l.montageFramingDone, onPressed: () => Navigator.of(context).maybePop()),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _instantMax(MontageLaneInfo lane) => lane.take.end > lane.take.start + 0.1 ? lane.take.end : lane.take.start + 0.1;

  List<Widget> _followControls(AppLocalizations l, double zoom, MontageOffsetInfo offset) {
    String sign(double v) => '${v < 0 ? '-' : '+'}${v.abs().toStringAsFixed(2)}';
    return <Widget>[
      FramingSliderRow(
        title: 'Zoom', // TODO(l10n): título visible del deslizador (solo hay clave de semántica).
        semanticLabel: l.montageFramingZoom(zoom.toStringAsFixed(2)),
        value: zoom,
        min: _zoomMin,
        max: _zoomMax,
        valueText: '×${zoom.toStringAsFixed(2)}',
        onChanged: (double v) {
          setState(() => _zoom = v);
          _commitFollowSoon();
        },
      ),
      FramingSliderRow(
        title: 'Desplazamiento X', // TODO(l10n)
        semanticLabel: l.montageFramingOffsetX(sign(offset.x)),
        value: offset.x,
        min: -_offsetMax,
        max: _offsetMax,
        valueText: sign(offset.x),
        onChanged: (double v) {
          setState(() => _offset = MontageOffsetInfo(x: v, y: offset.y));
          _commitFollowSoon();
        },
      ),
      FramingSliderRow(
        title: 'Desplazamiento Y', // TODO(l10n)
        semanticLabel: l.montageFramingOffsetY(sign(offset.y)),
        value: offset.y,
        min: -_offsetMax,
        max: _offsetMax,
        valueText: sign(offset.y),
        onChanged: (double v) {
          setState(() => _offset = MontageOffsetInfo(x: offset.x, y: v));
          _commitFollowSoon();
        },
      ),
      Text(l.montageFramingFollowHelp, style: TfText.body(TfSize.font12).copyWith(color: TfColors.muted)),
    ];
  }
}
