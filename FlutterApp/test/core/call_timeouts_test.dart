import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/call_timeouts.dart';

void main() {
  const t = CallTimeouts();
  test('por defecto 15 s', () => expect(t.of('study.state'), const Duration(seconds: 15)));
  test('valores de la tabla', () {
    expect(t.of('link.classify'), const Duration(seconds: 3));
    expect(t.of('tab.songsterr.search'), const Duration(seconds: 10));
    expect(t.of('link.search'), const Duration(seconds: 30));
    expect(t.of('audio.calibrate'), const Duration(seconds: 60));
    expect(t.of('link.resolve'), const Duration(seconds: 120));
    expect(t.of('tools.updateYtDlp'), const Duration(seconds: 200));
    expect(t.of('tab.export'), const Duration(minutes: 10));
    expect(t.of('import.file'), const Duration(minutes: 60));
    expect(t.of('library.relocate'), const Duration(minutes: 60));
  });
  test('diálogos sin límite', () {
    for (final m in ['host.pickAudioFile', 'host.pickAudioFiles', 'host.chooseFolder', 'host.pickProjectsFolder']) {
      expect(t.of(m), isNull, reason: m);
    }
  });
  test('overrides', () => expect(const CallTimeouts(overrides: {'a': null}).of('a'), isNull));
}
