import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tf_probe/probe6_snapshot.dart';

void main() {
  test('sin --snapshot devuelve null', () {
    expect(SnapshotArgs.parse(['--screen', 'x']), isNull);
  });

  test('valores por defecto', () {
    final a = SnapshotArgs.parse(['--snapshot', 'a.png'])!;
    expect(a.path, 'a.png');
    expect(a.delay, 2.0);
    expect(a.size, const Size(1440, 900));
  });

  test('retardo y ventana explícitos', () {
    final a = SnapshotArgs.parse([
      '--snapshot', 'b.png', '--snapshot-delay', '0.5', '--window', '800x600',
    ])!;
    expect(a.delay, 0.5);
    expect(a.size, const Size(800, 600));
  });
}
