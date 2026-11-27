import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/frame_channel.dart';

void main() {
  late int created;
  late int disposed;
  late FrameChannel ch;

  setUp(() {
    created = 0;
    disposed = 0;
    ch = FrameChannel(
      FrameChannelId.montage,
      createTexture: (_) {
        created++;
        return 4;
      },
      disposeTexture: (_) => disposed++,
    );
  });

  test('acquire A, acquire B, release A: textura viva y mismo id; release B la da de baja una vez', () {
    expect(ch.acquire(), 4);
    expect(ch.acquire(), 4);
    expect(created, 1);
    ch.release();
    expect(disposed, 0);
    expect(ch.textureId, 4);
    ch.release();
    expect(disposed, 1);
    expect(ch.textureId, isNull);
  });

  test('release de más no da de baja dos veces ni baja de cero', () {
    ch.acquire();
    ch.release();
    ch.release();
    ch.release();
    expect(disposed, 1);
    expect(ch.holders, 0);
    expect(ch.acquire(), 4);
    expect(created, 2);
    expect(ch.holders, 1);
  });

  test('sin texturas (−1): acquire devuelve −1, sin id y sin baja', () {
    final FrameChannel none = FrameChannel(FrameChannelId.take,
        createTexture: (_) => -1, disposeTexture: (_) => disposed++);
    expect(none.acquire(), -1);
    expect(none.textureId, isNull);
    none.release();
    expect(disposed, 0);
  });
}
