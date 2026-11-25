import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Hoja modal de macOS (docs/flutter/tokens-componentes.md §3.1 `TfSheet`): sin barra de título,
/// oscurece lo de detrás, aparece centrada arriba (o centrada del todo con [centered], para alertas).
/// Esc llama a [onCancel] (por defecto cierra con `null`) e Intro a [onPrimary]; el foco queda
/// atrapado dentro porque la ruta modal tiene su propio `FocusScope`.
Future<T?> showTfSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  VoidCallback? onCancel,
  VoidCallback? onPrimary,
  bool centered = false,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierColor: TfColors.black.withValues(alpha: TfOpacity.dim),
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (BuildContext ctx, Animation<double> a, Animation<double> b) {
      return _TfSheetShell(
        centered: centered,
        onCancel: onCancel ?? () => Navigator.of(ctx).maybePop(),
        onPrimary: onPrimary,
        child: builder(ctx),
      );
    },
    transitionBuilder: (BuildContext ctx, Animation<double> anim,
        Animation<double> b, Widget child) {
      return FadeTransition(opacity: anim, child: child);
    },
  );
}

class _TfSheetShell extends StatelessWidget {
  const _TfSheetShell({
    required this.centered,
    required this.onCancel,
    required this.onPrimary,
    required this.child,
  });

  final bool centered;
  final VoidCallback onCancel;
  final VoidCallback? onPrimary;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): onCancel,
        if (onPrimary != null) ...<ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.enter): onPrimary!,
          const SingleActivator(LogicalKeyboardKey.numpadEnter): onPrimary!,
        },
      },
      child: FocusScope(
        autofocus: true,
        child: FocusTraversalGroup(
          child: Align(
            alignment: centered ? Alignment.center : Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(top: centered ? 0 : TfSpace.s64),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Contenido de la hoja: ancho fijo, padding 24 o 28, título display, cuerpo `muted` y pie con
/// los botones a la derecha. Los botones los pasa el llamador (en orden: secundarios, principal).
class TfSheetScaffold extends StatelessWidget {
  const TfSheetScaffold({
    super.key,
    required this.width,
    required this.title,
    this.body,
    this.actions = const <Widget>[],
    this.padding = TfSpace.s24,
    this.background = TfColors.card,
    this.titleSize = 22,
    this.titleTrailing,
    this.spacing,
  });

  /// 420, 480, 540, 720 o 760 según la hoja.
  final double width;
  final String title;
  final Widget? body;
  final List<Widget> actions;

  /// 24 (Tab, Montaje, Offset, LinkImport) o 28 (FirstRun, Calibración).
  final double padding;

  /// `card` (FirstRun, Montaje, AddPart) o `bg` (Calibración).
  final Color background;

  /// Display 22-24.
  final double titleSize;

  /// Hueco tras el título, en la misma fila (p. ej. el chip «★ mejor» del visor).
  final Widget? titleTrailing;

  /// Separación entre cabecera, cuerpo y pie. Nulo = 12 (título-cuerpo) y 20 (cuerpo-pie).
  final double? spacing;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      scopesRoute: true,
      namesRoute: true,
      label: title,
      child: SizedBox(
        width: width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(TfRadius.card),
            border: Border.all(color: TfColors.line, width: TfStroke.hairline),
          ),
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (titleTrailing == null)
                  Text(
                    title,
                    style: TfText.display(titleSize).copyWith(color: TfColors.text),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: TfSpace.s8,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          title,
                          style: TfText.display(titleSize).copyWith(color: TfColors.text),
                        ),
                      ),
                      titleTrailing!,
                    ],
                  ),
                if (body != null) ...<Widget>[
                  SizedBox(height: spacing ?? TfSpace.s12),
                  Flexible(
                    child: DefaultTextStyle(
                      style: TfText.body().copyWith(color: TfColors.muted),
                      child: body!,
                    ),
                  ),
                ],
                if (actions.isNotEmpty) ...<Widget>[
                  SizedBox(height: spacing ?? TfSpace.s20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    spacing: TfSpace.s12,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
