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

  test('resolveCoverPath', () {
    expect(resolveCoverPath('/p', 'A/source/cover.jpg'), '/p/A/source/cover.jpg');
    expect(resolveCoverPath('/p/', 'A/cover.jpg'), '/p/A/cover.jpg');
    expect(resolveCoverPath(r'C:\p', 'A/cover.jpg'), r'C:\p\A\cover.jpg');
    expect(resolveCoverPath(null, 'A/cover.jpg'), isNull);
    expect(resolveCoverPath('/p', null), isNull);
  });

  test('displayPath', () {
    expect(displayPath('/Users/a/Music/ToneForge', home: '/Users/a', windows: false), '~/Music/ToneForge');
    expect(displayPath('/Users/a', home: '/Users/a', windows: false), '~');
    expect(displayPath('/Users/ab/x', home: '/Users/a', windows: false), '/Users/ab/x');
    expect(displayPath('/opt/x', home: '/Users/a', windows: false), '/opt/x');
    expect(displayPath('/x', home: null, windows: false), '/x');
    expect(displayPath(r'C:\Users\a\Music', home: r'C:\Users\a', windows: true), r'C:\Users\a\Music');
  });

  test('formatShortDate septiembre', () {
    final d = DateTime(2026, 9, 1, 0, 0);
    expect(formatShortDate(d, 'es'), '1 sept 2026, 0:00');
    expect(formatShortDate(d, 'en'), 'Sep 1, 2026, 12:00 AM');
  });

  test('formatShortDate', () {
    final d = DateTime(2026, 1, 5, 14, 7);
    expect(formatShortDate(d, 'es'), '5 ene 2026, 14:07');
    expect(formatShortDate(d, 'en'), 'Jan 5, 2026, 2:07 PM');
  });
}
