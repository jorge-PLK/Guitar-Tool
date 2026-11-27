import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/frame_channel.dart';
import 'package:toneforge/core/frame_providers.dart';
import 'package:toneforge/core/launch_options.dart';

void main() {
  test('con --mock no hay canal de fotogramas (marcador)', () {
    final c = ProviderContainer(overrides: [
      launchOptionsProvider.overrideWithValue(const LaunchOptions(mock: true)),
    ]);
    addTearDown(c.dispose);
    for (final id in FrameChannelId.values) {
      expect(c.read(frameChannelProvider(id)), isNull);
    }
  });

  test('el override por id devuelve el falso y no afecta a otros canales', () {
    final created = <int>[];
    final fake = FrameChannel(FrameChannelId.camera, createTexture: (id) {
      created.add(id);
      return 9;
    }, disposeTexture: (_) {});
    final c = ProviderContainer(overrides: [
      launchOptionsProvider.overrideWithValue(const LaunchOptions(mock: true)),
      frameChannelProvider(FrameChannelId.camera).overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);
    final got = c.read(frameChannelProvider(FrameChannelId.camera));
    expect(got, same(fake));
    expect(got!.acquire(), 9);
    expect(created, [FrameChannelId.camera.value]);
    expect(c.read(frameChannelProvider(FrameChannelId.take)), isNull);
  });
}
