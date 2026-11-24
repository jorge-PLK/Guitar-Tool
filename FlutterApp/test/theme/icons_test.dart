import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/theme/icons.dart';

void main() {
  test('todos los TfIcon tienen datos de trazo', () {
    expect(TfIcon.values, hasLength(56));
    for (final icon in TfIcon.values) {
      expect(tfIconCommandCount(icon), greaterThan(0), reason: icon.name);
    }
  });

  testWidgets('lamina de iconos (golden)', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            key: const ValueKey('sheet'),
            width: 528,
            child: ColoredBox(
              color: const Color(0xFFFFFFFF),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final icon in TfIcon.values)
                      TfIconView(icon, size: 48, color: const Color(0xFF000000)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byKey(const ValueKey('sheet')),
      matchesGoldenFile('goldens/icons_sheet.png'),
    );
  });
}
