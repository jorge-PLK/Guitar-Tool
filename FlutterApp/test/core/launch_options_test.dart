import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/launch_options.dart';

void main() {
  test('vacío', () {
    final o = LaunchOptions.parse([]);
    expect(o.mock, isFalse);
    expect(o.toCoreArgs(), isEmpty);
  });

  test('todos los flags, con espacio e igual', () {
    final o = LaunchOptions.parse([
      '/ruta/toneforge', '--projects-folder', '/p', '--support-dir=/s', '--screen', 'study',
      '--project', 'abc', '--snapshot', '/o.png', '--snapshot-delay', '1.5', '--window', '1280x800',
      '--audio', 'simulated', '--camera', 'simulated', '--mock', '--locale', 'en', '--core-lib', '/l.dylib',
    ]);
    expect(o.projectsFolder, '/p');
    expect(o.supportDir, '/s');
    expect(o.screen, 'study');
    expect(o.project, 'abc');
    expect(o.snapshot, '/o.png');
    expect(o.snapshotDelay, 1.5);
    expect(o.window, (width: 1280, height: 800));
    expect(o.audio, 'simulated');
    expect(o.camera, 'simulated');
    expect(o.mock, isTrue);
    expect(o.locale, 'en');
    expect(o.coreLib, '/l.dylib');
  });

  test('toCoreArgs no incluye los de solo Dart', () {
    final o = LaunchOptions.parse(['--mock', '--locale', 'es', '--core-lib', 'x', '--screen', 'home', '--window', '800x600']);
    expect(o.toCoreArgs(), ['--screen', 'home', '--window', '800x600']);
  });

  test('valores inválidos se ignoran', () {
    final o = LaunchOptions.parse(['--window', 'ax5', '--snapshot-delay', '-1', '--locale', 'fr', '--screen']);
    expect(o.window, isNull);
    expect(o.snapshotDelay, isNull);
    expect(o.locale, isNull);
    expect(o.screen, isNull);
  });
}
