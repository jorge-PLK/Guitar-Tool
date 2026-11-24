import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

/// Pestañas (SettingsView.swift:17-32): contenedor `field` radio 10 con borde `fieldLine`, padding 3,
/// separación 4; botón alto 44, h18, radio 8. Teclado: ← → cambian la pestaña cuando la barra tiene foco.
class TfTabBar extends StatefulWidget {
  const TfTabBar({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  State<TfTabBar> createState() => _TfTabBarState();
}

class _TfTabBarState extends State<TfTabBar> {
  final FocusNode _focus = FocusNode(debugLabel: 'TfTabBar');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final int step = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => -1,
      LogicalKeyboardKey.arrowRight => 1,
      _ => 0,
    };
    if (step == 0) return KeyEventResult.ignored;
    final int next = widget.selected + step;
    if (next >= 0 && next < widget.labels.length) widget.onSelect(next);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TfRadius.control),
          border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: TfColors.field,
            borderRadius: BorderRadius.circular(TfRadius.control),
          ),
          child: Padding(
            padding: const EdgeInsets.all(TfSpace.s3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: TfSpace.s4,
              children: <Widget>[
                for (int i = 0; i < widget.labels.length; i++) _tab(i),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(int i) {
    final bool on = i == widget.selected;
    return Semantics(
      button: true,
      selected: on,
      label: widget.labels[i],
      excludeSemantics: true,
      onTap: () => widget.onSelect(i),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _focus.requestFocus();
            widget.onSelect(i);
          },
          child: Container(
            height: TfSize.controlLg,
            padding: const EdgeInsets.symmetric(horizontal: TfSpace.s18),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? TfColors.accentBg : null,
              borderRadius: BorderRadius.circular(TfRadius.field),
            ),
            child: Text(
              widget.labels[i],
              maxLines: 1,
              style: TfText.body(14, on ? TfWeight.semibold : TfWeight.medium)
                  .copyWith(color: on ? TfColors.accent : TfColors.text2),
            ),
          ),
        ),
      ),
    );
  }
}
