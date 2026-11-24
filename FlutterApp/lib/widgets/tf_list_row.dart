import 'package:flutter/widgets.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

/// Fila de lista (LibraryView.swift:208-254): padding h20 v14, separador `line` encima (como el
/// `Divider` previo a cada fila), reposo transparente, hover `accent @0.07`, seleccionada
/// `ok @0.12` + franja izquierda 3 `ok` (manda sobre el hover). Las columnas las define el llamador.
class TfListRow extends StatefulWidget {
  const TfListRow({
    super.key,
    required this.child,
    this.selected = false,
    this.divider = true,
    this.onTap,
  });

  final Widget child;
  final bool selected;
  final bool divider;
  final VoidCallback? onTap;

  @override
  State<TfListRow> createState() => _TfListRowState();
}

class _TfListRowState extends State<TfListRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final Color? background = widget.selected
        ? TfColors.ok.withValues(alpha: TfOpacity.tint12)
        : _hover
            ? TfColors.accent.withValues(alpha: TfOpacity.tint07)
            : null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (widget.divider)
              const SizedBox(height: TfStroke.hairline, child: ColoredBox(color: TfColors.line)),
            Stack(
              children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(color: background),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: TfSpace.s20, vertical: TfSpace.s14),
                    child: widget.child,
                  ),
                ),
                if (widget.selected)
                  const Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: TfSpace.s3,
                    child: ColoredBox(color: TfColors.ok),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Celda de cabecera de tabla (LibraryView.swift:156-159): 12 medium MAYÚSCULAS, interletraje 0,7, `muted`.
class TfTableHeaderCell extends StatelessWidget {
  const TfTableHeaderCell(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TfText.body(12, TfWeight.medium)
          .copyWith(color: TfColors.muted, letterSpacing: TfSize.trackingTableHeader),
    );
  }
}
