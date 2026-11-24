import 'package:flutter/widgets.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

/// Entrada de la barra lateral: la carcasa traduce rutas a esto.
class TfSidebarEntry {
  const TfSidebarEntry({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final TfIcon icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
}

/// Barra lateral (RootView.swift:51-120): 240 de ancho, padding h16 v24, fondo `sidebar`,
/// borde derecho `line` 1. No conoce rutas. `bottom` va tras el hueco elástico (Ajustes, tarjetas),
/// con la misma separación de 4 entre elementos.
class TfSidebar extends StatelessWidget {
  const TfSidebar({
    super.key,
    required this.logoTone,
    required this.logoForge,
    required this.entries,
    this.bottom = const <Widget>[],
  });

  final String logoTone;
  final String logoForge;
  final List<TfSidebarEntry> entries;
  final List<Widget> bottom;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: TfSize.sidebarWidth,
      child: ColoredBox(
        color: TfColors.sidebar,
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: TfSpace.s16, vertical: TfSpace.s24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: TfSpace.s4,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(left: TfSpace.s12, right: TfSpace.s12, bottom: TfSpace.s20),
                    child: Text.rich(
                      TextSpan(
                        style: TfText.display(22).copyWith(color: TfColors.text),
                        children: <InlineSpan>[
                          TextSpan(text: logoTone),
                          TextSpan(text: logoForge, style: const TextStyle(color: TfColors.accent)),
                        ],
                      ),
                      maxLines: 1,
                    ),
                  ),
                  for (final TfSidebarEntry e in entries)
                    TfNavRow(icon: e.icon, label: e.label, active: e.selected, onTap: e.onTap),
                  const Spacer(),
                  ...bottom,
                ],
              ),
            ),
            const Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: TfStroke.hairline,
              child: ColoredBox(color: TfColors.line),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila de navegación: alto 44, h12, radio 10, icono 18 + hueco 10 + texto body 14 medium.
class TfNavRow extends StatelessWidget {
  const TfNavRow({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final TfIcon icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = active ? TfColors.accent : TfColors.text2;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: TfSize.controlLg,
            padding: const EdgeInsets.symmetric(horizontal: TfSpace.s12),
            decoration: BoxDecoration(
              color: active ? TfColors.accentBg : null,
              borderRadius: BorderRadius.circular(TfRadius.control),
            ),
            child: Row(
              spacing: TfSpace.s10,
              children: <Widget>[
                SizedBox(
                  width: TfSize.navIcon,
                  child: TfIconView(icon, size: TfSize.navIcon, color: color),
                ),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TfText.body(14, TfWeight.medium).copyWith(color: color),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
