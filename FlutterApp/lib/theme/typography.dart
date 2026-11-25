import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// Pesos pedidos a la tipografía. Cada uno se mapea a una de las 5 caras existentes
/// (docs/flutter/tokens-componentes.md §1.2, igual que App/Sources/Theme.swift:33-57).
enum TfWeight { regular, medium, semibold, bold }

/// Familias declaradas en pubspec.yaml.
abstract final class TfFamily {
  static const String inter = 'Inter';
  static const String spaceGrotesk = 'SpaceGrotesk';
}

abstract final class TfText {
  /// Cifras tabulares (`.monospacedDigit()`): relojes, tempo, cents.
  static const List<FontFeature> tabularFigures = <FontFeature>[FontFeature.tabularFigures()];

  /// [base] con cifras tabulares.
  static TextStyle tabular(TextStyle base) => base.copyWith(fontFeatures: tabularFigures);

  /// Display (Space Grotesk). Por defecto bold, como `TF.display(s)`.
  /// regular/medium -> 500 (SpaceGroteskLight-Medium); semibold/bold -> 700 (SpaceGroteskLight-Bold).
  static TextStyle display(double size, [TfWeight weight = TfWeight.bold]) {
    final bool isBold = weight == TfWeight.semibold || weight == TfWeight.bold;
    return TextStyle(
      fontFamily: TfFamily.spaceGrotesk,
      fontSize: size,
      fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
    );
  }

  /// Body (Inter). Por defecto 14 regular, como `TF.body()`.
  /// regular -> 400 (Inter-Regular); medium -> 500 (Inter-Medium);
  /// semibold/bold -> 600 (Inter-SemiBold).
  static TextStyle body([double size = 14, TfWeight weight = TfWeight.regular]) {
    final FontWeight fontWeight = switch (weight) {
      TfWeight.regular => FontWeight.w400,
      TfWeight.medium => FontWeight.w500,
      TfWeight.semibold || TfWeight.bold => FontWeight.w600,
    };
    return TextStyle(
      fontFamily: TfFamily.inter,
      fontSize: size,
      fontWeight: fontWeight,
    );
  }
}

/// Registra las licencias SIL OFL 1.1 de las fuentes en LicenseRegistry.
/// La carcasa la llama al arrancar.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const <String>['Inter'],
      await rootBundle.loadString('assets/licenses/LICENSE-Inter.txt'),
    );
    yield LicenseEntryWithLineBreaks(
      const <String>['Space Grotesk'],
      await rootBundle.loadString('assets/licenses/LICENSE-SpaceGrotesk.txt'),
    );
  });
}
