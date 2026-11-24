import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/theme/fmt.dart';

void main() {
  group('TfFmt.bytes', () {
    // Valores de ByteCountFormatter(.file) en es_ES (sonda sobre SwiftUI).
    const cases = <(int, String, String)>[
      (0, 'Zero KB', 'Zero KB'),
      (1, '1 byte', '1 byte'),
      (500, '500 bytes', '500 bytes'),
      (999, '999 bytes', '999 bytes'),
      (1000, '1 KB', '1 KB'),
      (1023, '1 KB', '1 KB'),
      (1500, '2 KB', '2 KB'),
      (999949, '1 MB', '1 MB'),
      (999999, '1 MB', '1 MB'),
      (1000000, '1 MB', '1 MB'),
      (1234567, '1,2 MB', '1.2 MB'),
      (1500000, '1,5 MB', '1.5 MB'),
      (2500000000, '2,5 GB', '2.5 GB'),
      (1000000000000, '1 TB', '1 TB'),
    ];
    for (final (n, es, en) in cases) {
      test('$n', () {
        expect(TfFmt.bytes(n, 'es'), es);
        expect(TfFmt.bytes(n, 'en'), en);
      });
    }
  });

  group('TfFmt.percent', () {
    const cases = <(double, String)>[
      (0, '0 %'),
      (0.5, '50 %'),
      (1, '100 %'),
      (1.5, '150 %'),
      (0.125, '13 %'),
      (-0.125, '-13 %'),
      (-0.001, '0 %'),
    ];
    for (final (f, expected) in cases) {
      test('$f', () {
        expect(TfFmt.percent(f), expected);
      });
    }
  });

  group('TfFmt.duration', () {
    const cases = <(double, String)>[
      (0, '0:00'),
      (5, '0:05'),
      (59.4, '0:59'),
      (59.5, '1:00'),
      (60, '1:00'),
      (125.6, '2:06'),
      (3599.4, '59:59'),
      (3600, '60:00'),
      (-5, '0:-5'),
    ];
    for (final (s, expected) in cases) {
      test('$s', () {
        expect(TfFmt.duration(s), expected);
      });
    }
  });

  group('TfFmt.rate', () {
    const cases = <(double, String, String)>[
      (44100, '44,1 kHz', '44.1 kHz'),
      (48000, '48 kHz', '48 kHz'),
      (96000, '96000 Hz', '96000 Hz'),
      (22050, '22050 Hz', '22050 Hz'),
      (44100.9, '44100 Hz', '44100 Hz'),
      (0, '0 Hz', '0 Hz'),
    ];
    for (final (hz, es, en) in cases) {
      test('$hz', () {
        expect(TfFmt.rate(hz, 'es'), es);
        expect(TfFmt.rate(hz, 'en'), en);
      });
    }
  });

  group('TfFmt.db', () {
    const cases = <(double, String, String)>[
      (-6.0, '-6,0 dB', '-6.0 dB'),
      (0, '0,0 dB', '0.0 dB'),
      (-0.04, '-0,0 dB', '-0.0 dB'),
      (3.25, '3,2 dB', '3.2 dB'),
      (3.75, '3,8 dB', '3.8 dB'),
      (-6.25, '-6,2 dB', '-6.2 dB'),
      (0.35, '0,3 dB', '0.3 dB'),
      (-12.34, '-12,3 dB', '-12.3 dB'),
      (6.0, '6,0 dB', '6.0 dB'),
    ];
    for (final (v, es, en) in cases) {
      test('$v', () {
        expect(TfFmt.db(v, 'es'), es);
        expect(TfFmt.db(v, 'en'), en);
      });
    }
  });

  group('TfFmt.clock', () {
    const cases = <(double, String)>[
      (0, '0:00'),
      (5.9, '0:05'),
      (59.99, '0:59'),
      (60, '1:00'),
      (125.6, '2:05'),
      (3599.9, '59:59'),
      (3600, '60:00'),
      (-3, '0:00'),
    ];
    for (final (s, expected) in cases) {
      test('$s', () {
        expect(TfFmt.clock(s), expected);
      });
    }
  });

  group('TfFmt.number', () {
    const cases = <(double, int, String, String)>[
      (50.02, 2, '50,02', '50.02'),
      (12345.6, 1, '12.345,6', '12,345.6'),
      (0, 1, '0,0', '0.0'),
      (-3.5, 1, '-3,5', '-3.5'),
    ];
    for (final (v, digits, es, en) in cases) {
      test('$v ($digits)', () {
        expect(TfFmt.number(v, digits, 'es'), es);
        expect(TfFmt.number(v, digits, 'en'), en);
      });
    }
  });
}
