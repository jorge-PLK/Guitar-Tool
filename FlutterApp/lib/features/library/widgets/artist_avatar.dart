import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:toneforge/features/library/library_logic.dart';

import '../../../theme/icons.dart';
import '../../../theme/tokens.dart';
import '../../../theme/typography.dart';

/// Tamaño del glifo de «Sin artista» (AG:47) y de las iniciales (AG:42).
const double _unknownIconSize = 40;
const double _initialsSize = 34;
const double _saturation = 0.45;
const double _brightness = 0.5;

/// Hasta dos letras: las iniciales de las dos primeras palabras (AG:64-68); «?» si no hay.
String artistInitials(String name) {
  final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2);
  final s = words.map((w) => String.fromCharCode(w.runes.first)).join().toUpperCase();
  return s.isEmpty ? '?' : s;
}

/// Color estable derivado del nombre plegado (FNV-1a de 64 bits sobre UTF-8; AG:70-75).
/// No existe `TfColors.artistAvatar` en `lib/theme`: se calcula aquí (es cálculo, no literal).
Color artistAvatar(String name) {
  var h = 0xcbf29ce484222325;
  for (final b in utf8.encode(foldText(name))) {
    h = (h ^ b) * 0x100000001b3; // desborda en 64 bits, igual que `&*` de Swift
  }
  // `h` es el patrón de 64 bits sin signo: módulo 360 sin pasar a negativo.
  final hue = (2 * ((h >>> 1) % 180) + (h & 1)) % 360;
  return HSVColor.fromAHSV(1, hue.toDouble(),_saturation, _brightness).toColor();
}

/// Portada del recuadro sin foto: color + iniciales, o «Sin artista» (icono sobre `field`).
class ArtistAvatar extends StatelessWidget {
  const ArtistAvatar({super.key, required this.name, required this.isUnknown});

  final String name;
  final bool isUnknown;

  @override
  Widget build(BuildContext context) {
    if (isUnknown) {
      return const ColoredBox(
        color: TfColors.field,
        child: Center(child: TfIconView(TfIcon.personFill, size: _unknownIconSize, color: TfColors.muted, filled: true)),
      );
    }
    return ColoredBox(
      color: artistAvatar(name),
      child: Center(
        child: Text(
          artistInitials(name),
          style: TfText.display(_initialsSize).copyWith(
            color: TfColors.white.withValues(alpha: TfOpacity.whiteSoft),
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
