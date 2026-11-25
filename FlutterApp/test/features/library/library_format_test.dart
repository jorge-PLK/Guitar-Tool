import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/features/library/library_format.dart';

void main() {
  test('formatBytes', () {
    expect(formatBytes(1234567, 'es'), '1,2 MB');
    expect(formatBytes(1234567, 'en'), '1.2 MB');
  });

  test('formatRate', () {
    expect(formatRate(44100, 'es'), '44,1 kHz');
    expect(formatRate(44100, 'en'), '44.1 kHz');
  });

  test('formatClock', () {
    expect(formatClock(null), '–');
    expect(formatClock(65), '1:05');
  });

  test('formatShortDate', () {
    final d = DateTime(2026, 1, 5, 14, 7);
    expect(formatShortDate(d, 'es'), '5 ene 2026, 14:07');
    expect(formatShortDate(d, 'en'), 'Jan 5, 2026, 2:07 PM');
  });
}
