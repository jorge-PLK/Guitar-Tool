import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'tf_popover.dart';

/// Entrada de un [TfMenu] o [TfContextMenu].
sealed class TfMenuEntry {
  const TfMenuEntry();
}

/// Entrada con texto. [destructive] la pinta en `danger`; [enabled] false la deja inerte.
class TfMenuItem extends TfMenuEntry {
  const TfMenuItem({
    required this.label,
    required this.onSelected,
    this.destructive = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onSelected;
  final bool destructive;
  final bool enabled;
}

/// Separador (el `Divider` del menú nativo).
class TfMenuDivider extends TfMenuEntry {
  const TfMenuDivider();
}

/// Menú desplegable desde un botón (`Menu {}` de SwiftUI). [builder] dibuja el botón y recibe la
/// función que abre o cierra el menú.
class TfMenu extends StatefulWidget {
  const TfMenu({super.key, required this.entries, required this.builder});

  final List<TfMenuEntry> entries;
  final Widget Function(BuildContext context, VoidCallback toggle) builder;

  @override
  State<TfMenu> createState() => _TfMenuState();
}

class _TfMenuState extends State<TfMenu> {
  final TfPopoverController _controller = TfPopoverController();

  @override
  Widget build(BuildContext context) {
    return TfPopover(
      controller: _controller,
      popoverBuilder: (BuildContext c) =>
          TfMenuPanel(entries: widget.entries, onClose: _controller.hide),
      child: widget.builder(context, _controller.toggle),
    );
  }
}

/// Menú contextual: se abre con clic secundario sobre [child], en el punto del clic.
class TfContextMenu extends StatefulWidget {
  const TfContextMenu({super.key, required this.entries, required this.child});

  final List<TfMenuEntry> entries;
  final Widget child;

  @override
  State<TfContextMenu> createState() => _TfContextMenuState();
}

class _TfContextMenuState extends State<TfContextMenu> {
  final TfPopoverController _controller = TfPopoverController();
  Offset _at = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return TfPopover(
      controller: _controller,
      anchorAlignment: Alignment.topLeft,
      offset: _at,
      popoverBuilder: (BuildContext c) =>
          TfMenuPanel(entries: widget.entries, onClose: _controller.hide),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapDown: (TapDownDetails d) {
          setState(() => _at = d.localPosition);
          _controller.show();
        },
        child: widget.child,
      ),
    );
  }
}

/// Panel del menú con navegación de teclado: ↑↓ mueven, Intro elige, Esc lo cierra el popover.
class TfMenuPanel extends StatefulWidget {
  const TfMenuPanel({super.key, required this.entries, required this.onClose});

  final List<TfMenuEntry> entries;
  final VoidCallback onClose;

  @override
  State<TfMenuPanel> createState() => _TfMenuPanelState();
}

class _TfMenuPanelState extends State<TfMenuPanel> {
  final FocusNode _focus = FocusNode();
  int? _index;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  bool _selectable(int i) {
    final TfMenuEntry e = widget.entries[i];
    return e is TfMenuItem && e.enabled;
  }

  void _move(int step) {
    final int n = widget.entries.length;
    int i = _index ?? (step > 0 ? -1 : n);
    for (int tries = 0; tries < n; tries++) {
      i = (i + step) % n;
      if (i < 0) i += n;
      if (_selectable(i)) {
        setState(() => _index = i);
        return;
      }
    }
  }

  void _select(int i) {
    if (!_selectable(i)) return;
    final TfMenuItem item = widget.entries[i] as TfMenuItem;
    widget.onClose();
    item.onSelected();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      if (_index != null) _select(_index!);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: TfSize.menuMinWidth),
        child: IntrinsicWidth(
          child: Padding(
            padding: const EdgeInsets.all(TfSpace.s4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < widget.entries.length; i++)
                  switch (widget.entries[i]) {
                    TfMenuDivider() => const Padding(
                        padding: EdgeInsets.symmetric(vertical: TfSpace.s4),
                        child: SizedBox(
                          height: TfStroke.hairline,
                          child: ColoredBox(color: TfColors.line),
                        ),
                      ),
                    final TfMenuItem item => _Row(
                        item: item,
                        highlighted: _index == i,
                        onHover: () {
                          if (item.enabled) setState(() => _index = i);
                        },
                        onTap: () => _select(i),
                      ),
                  },
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.item,
    required this.highlighted,
    required this.onHover,
    required this.onTap,
  });

  final TfMenuItem item;
  final bool highlighted;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color tone = item.destructive ? TfColors.danger : TfColors.accent;
    final Color textColor = !item.enabled
        ? TfColors.muted.withValues(alpha: TfOpacity.disabled)
        : (item.destructive ? TfColors.danger : TfColors.text);
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: item.enabled ? onTap : null,
        child: Container(
          height: TfSize.controlSm,
          padding: const EdgeInsets.symmetric(horizontal: TfSpace.s12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: highlighted && item.enabled
                ? tone.withValues(alpha: TfOpacity.tint12)
                : null,
            borderRadius: BorderRadius.circular(TfRadius.small),
          ),
          child: Text(
            item.label,
            style: TfText.body(13).copyWith(color: textColor),
          ),
        ),
      ),
    );
  }
}
