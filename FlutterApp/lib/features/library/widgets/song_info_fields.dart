import 'package:flutter/widgets.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

// Medidas de AG:78-131 sin token en el kit (pedido en el informe): alto de campo.
const double _fieldHeight = 40;

/// Campos «Título» y «Artista» con el botón de intercambiar (`SongInfoFields`, AG:78-131).
/// Los comparten el modo edición del detalle y la hoja «Corregir título y artista».
///
/// El llamante es dueño de los controladores. [titleFocus] opcional (para enfocar «Título»);
/// con [autofocusTitle] el título se enfoca al montarse. [onSubmitted] se llama con Intro en cualquiera
/// de los dos campos. Intercambiar cambia los textos de ambos controladores.
class SongInfoFields extends StatelessWidget {
  const SongInfoFields({
    super.key,
    required this.titleController,
    required this.artistController,
    this.titleFocus,
    this.autofocusTitle = false,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController titleController;
  final TextEditingController artistController;
  final FocusNode? titleFocus;
  final bool autofocusTitle;
  final VoidCallback? onSubmitted;

  /// Se llama al teclear o intercambiar (para recalcular «Guardar»).
  final VoidCallback? onChanged;

  void _swap() {
    final t = titleController.text;
    titleController.text = artistController.text;
    artistController.text = t;
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Field(
                label: l.library_fieldTitle,
                controller: titleController,
                focusNode: titleFocus,
                autofocus: autofocusTitle,
                onSubmitted: onSubmitted,
                onChanged: onChanged,
              ),
              const SizedBox(height: TfSpace.s12),
              _Field(
                label: l.library_fieldArtist,
                controller: artistController,
                onSubmitted: onSubmitted,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
        const SizedBox(width: TfSpace.s10),
        Semantics(
          button: true,
          label: l.library_swapTooltip,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _swap,
              child: Container(
                width: TfSize.controlMd,
                height: TfSize.controlMd,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: TfColors.field,
                  borderRadius: BorderRadius.circular(TfRadius.control),
                  border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
                ),
                child: const TfIconView(TfIcon.arrowUpArrowDown, size: TfSize.iconButtonIcon, color: TfColors.muted),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Field extends StatefulWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.focusNode,
    this.autofocus = false,
    this.onSubmitted,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onSubmitted;
  final VoidCallback? onChanged;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  FocusNode? _own;

  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final controller = widget.controller;
    final style = TfText.body().copyWith(color: TfColors.text, decoration: TextDecoration.none);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TfText.body(TfSize.font13).copyWith(color: TfColors.muted, decoration: TextDecoration.none),
        ),
        const SizedBox(height: TfSpace.s6),
        Container(
          height: _fieldHeight,
          padding: const EdgeInsets.symmetric(horizontal: TfSpace.s12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: TfColors.field,
            borderRadius: BorderRadius.circular(TfRadius.field),
            border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
          ),
          child: EditableText(
            controller: controller,
            focusNode: _focus,
            autofocus: widget.autofocus,
            style: style,
            cursorColor: TfColors.accent,
            backgroundCursorColor: TfColors.muted,
            selectionColor: TfColors.accent.withValues(alpha: TfOpacity.tint35),
            maxLines: 1,
            onChanged: (_) => widget.onChanged?.call(),
            onSubmitted: (_) => widget.onSubmitted?.call(),
          ),
        ),
      ],
    );
  }
}
