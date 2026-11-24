import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/theme/typography.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TfText.display (Space Grotesk)', () {
    test('por defecto es bold 700', () {
      final TextStyle style = TfText.display(20);
      expect(style.fontFamily, 'SpaceGrotesk');
      expect(style.fontSize, 20);
      expect(style.fontWeight, FontWeight.w700);
    });

    test('regular y medium mapean a 500', () {
      expect(TfText.display(16, TfWeight.regular).fontWeight, FontWeight.w500);
      expect(TfText.display(16, TfWeight.medium).fontWeight, FontWeight.w500);
    });

    test('semibold y bold mapean a 700', () {
      expect(TfText.display(16, TfWeight.semibold).fontWeight, FontWeight.w700);
      expect(TfText.display(16, TfWeight.bold).fontWeight, FontWeight.w700);
    });
  });

  group('TfText.body (Inter)', () {
    test('por defecto es 14 regular 400', () {
      final TextStyle style = TfText.body();
      expect(style.fontFamily, 'Inter');
      expect(style.fontSize, 14);
      expect(style.fontWeight, FontWeight.w400);
    });

    test('regular 400, medium 500', () {
      expect(TfText.body(13, TfWeight.regular).fontWeight, FontWeight.w400);
      expect(TfText.body(13, TfWeight.medium).fontWeight, FontWeight.w500);
    });

    test('semibold y bold mapean a 600 (SemiBold)', () {
      expect(TfText.body(15, TfWeight.semibold).fontWeight, FontWeight.w600);
      expect(TfText.body(11, TfWeight.bold).fontWeight, FontWeight.w600);
    });
  });

  test('las 5 caras cargan con FontLoader', () async {
    const List<(String, String)> faces = <(String, String)>[
      (TfFamily.inter, 'assets/fonts/inter-latin-400.ttf'),
      (TfFamily.inter, 'assets/fonts/inter-latin-500.ttf'),
      (TfFamily.inter, 'assets/fonts/inter-latin-600.ttf'),
      (TfFamily.spaceGrotesk, 'assets/fonts/space-grotesk-latin-500.ttf'),
      (TfFamily.spaceGrotesk, 'assets/fonts/space-grotesk-latin-700.ttf'),
    ];
    for (final (String family, String path) in faces) {
      final FontLoader loader = FontLoader(family)
        ..addFont(rootBundle.load(path));
      await loader.load();
    }
  });

  test('registerFontLicenses registra las licencias OFL', () async {
    registerFontLicenses();
    final List<String> packages = (await LicenseRegistry.licenses.toList())
        .expand((entry) => entry.packages)
        .toList();
    expect(packages, containsAll(<String>['Inter', 'Space Grotesk']));
  });
}
