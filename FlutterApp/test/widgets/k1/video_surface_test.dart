import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/frame_channel.dart';
import 'package:toneforge/widgets/tf_video_surface.dart';

import '../../support/harness.dart';

void main() {
  const Size frame = Size(1920, 1080);
  const Key marker = ValueKey<String>('placeholder');

  Widget host(Widget child) => Directionality(
        textDirection: TextDirection.ltr,
        child: Align(alignment: Alignment.topLeft, child: SizedBox(width: 400, height: 400, child: child)),
      );

  Rect texture(WidgetTester t) => globalBounds(t, find.byType(Texture));

  group('k1 video surface', () {
    testWidgets('contain 16:9 en 400x400', (WidgetTester t) async {
      await t.pumpWidget(host(const TfVideoSurface(textureId: 7, frameSize: frame)));
      final Rect r = texture(t);
      expect(r.width, closeTo(400, 0.01));
      expect(r.height, closeTo(225, 0.01));
      expect(r.center, const Offset(200, 200));
    });

    testWidgets('cover 16:9 en 400x400 desborda y se recorta', (WidgetTester t) async {
      await t.pumpWidget(host(const TfVideoSurface(textureId: 7, frameSize: frame, fit: TfVideoFit.cover)));
      final Rect r = texture(t);
      expect(r.height, closeTo(400, 0.01));
      expect(r.width, closeTo(400 * 16 / 9, 0.01));
      expect(t.getSize(find.byType(TfVideoSurface)), const Size(400, 400));
    });

    testWidgets('rotación 90 intercambia ancho y alto (contain)', (WidgetTester t) async {
      await t.pumpWidget(host(const TfVideoSurface(textureId: 7, frameSize: frame, rotation: 90)));
      final Rect r = texture(t);
      expect(r.width, closeTo(225, 0.01));
      expect(r.height, closeTo(400, 0.01));
    });

    testWidgets('rotación 270 y cover', (WidgetTester t) async {
      await t.pumpWidget(host(const TfVideoSurface(
        textureId: 7,
        frameSize: frame,
        rotation: 270,
        fit: TfVideoFit.cover,
      )));
      final Rect r = texture(t);
      expect(r.width, closeTo(400, 0.01));
      expect(r.height, closeTo(400 * 16 / 9, 0.01));
    });

    testWidgets('rotación 180 no intercambia', (WidgetTester t) async {
      await t.pumpWidget(host(const TfVideoSurface(textureId: 7, frameSize: frame, rotation: 180)));
      final Rect r = texture(t);
      expect(r.width, closeTo(400, 0.01));
      expect(r.height, closeTo(225, 0.01));
    });

    testWidgets('sin tamaño de fotograma rellena la caja', (WidgetTester t) async {
      await t.pumpWidget(host(const TfVideoSurface(textureId: 7)));
      expect(texture(t).size, const Size(400, 400));
    });

    testWidgets('recorta al radio', (WidgetTester t) async {
      await t.pumpWidget(host(const TfVideoSurface(textureId: 7, frameSize: frame, radius: 12)));
      expect(t.widget<ClipRRect>(find.byType(ClipRRect)).borderRadius, BorderRadius.circular(12));
    });

    for (final int? id in <int?>[null, -1]) {
      testWidgets('textura $id: placeholder y sin Texture', (WidgetTester t) async {
        await t.pumpWidget(host(TfVideoSurface(
          textureId: id,
          frameSize: frame,
          placeholder: const SizedBox(key: marker),
        )));
        expect(find.byKey(marker), findsOneWidget);
        expect(find.byType(Texture), findsNothing);
        expect(t.getSize(find.byKey(marker)), const Size(400, 400));
      });
    }

    testWidgets('.channel toma el id del FrameChannel; sin textura, placeholder', (WidgetTester t) async {
      final FrameChannel ok = FrameChannel(FrameChannelId.camera, createTexture: (_) => 5, disposeTexture: (_) {})
        ..create();
      await t.pumpWidget(host(TfVideoSurface.channel(ok, frameSize: frame)));
      expect(t.widget<Texture>(find.byType(Texture)).textureId, 5);

      final FrameChannel none = FrameChannel(FrameChannelId.camera, createTexture: (_) => -1, disposeTexture: (_) {})
        ..create();
      await t.pumpWidget(host(TfVideoSurface.channel(none, frameSize: frame, placeholder: const SizedBox(key: marker))));
      expect(find.byType(Texture), findsNothing);
      expect(find.byKey(marker), findsOneWidget);
    });
  });
}
