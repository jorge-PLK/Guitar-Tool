import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/features/montage/montage_frame_image.dart';

void main() {
  test('misma ruta y distinta version: proveedores y claves de caché distintos', () {
    final a = framingFrameImage('/t/cache/montage/framing-x.png', 1);
    final b = framingFrameImage('/t/cache/montage/framing-x.png', 2);
    expect(a, isNot(b));
    expect(a.hashCode, isNot(b.hashCode));
  });

  test('misma ruta y misma version: misma clave', () {
    final a = framingFrameImage('/t/cache/montage/framing-x.png', 3);
    final b = framingFrameImage('/t/cache/montage/framing-x.png', 3);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
