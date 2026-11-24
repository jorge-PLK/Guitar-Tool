import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_accent_bar.dart';
import 'package:toneforge/widgets/tf_card.dart';
import 'package:toneforge/widgets/tf_chip.dart';
import 'package:toneforge/widgets/tf_divider.dart';
import 'package:toneforge/widgets/tf_progress.dart';
import 'package:toneforge/widgets/tf_song_cover.dart';

import '../../support/harness.dart';

void main() {
  setUpAll(loadTfFonts);

  Future<void> golden(String name) =>
      expectLater(find.byKey(const ValueKey<String>('k1')), matchesGoldenFile('goldens/$name.png'));

  group('k1 chip', () {
    for (final TfChipKind k in TfChipKind.values) {
      testWidgets('chip ${k.name}', (WidgetTester t) async {
        await t.pumpWidget(k1Frame(TfChip('Etiqueta', kind: k)));
        await golden('k1_chip_${k.name}');
      });
    }
  });

  group('k1 card', () {
    testWidgets('card con contenido', (WidgetTester t) async {
      await t.pumpWidget(k1Frame(const TfCard(child: SizedBox(width: 120, height: 60))));
      await golden('k1_card');
      expect(t.getSize(find.byType(TfCard)), const Size(120, 60));
    });
  });

  group('k1 accent bar', () {
    for (final double v in <double>[0, 0.5, 1]) {
      testWidgets('valor $v', (WidgetTester t) async {
        await t.pumpWidget(k1Frame(SizedBox(width: 200, child: TfAccentBar(value: v))));
        await golden('k1_accentbar_${(v * 10).round()}');
      });
    }
    testWidgets('sin valor a t=0.25 (400 ms)', (WidgetTester t) async {
      await t.pumpWidget(k1Frame(const SizedBox(width: 200, child: TfAccentBar())));
      await t.pump(const Duration(milliseconds: 400));
      await golden('k1_accentbar_indeterminate');
      await t.pumpWidget(const SizedBox());
    });
    testWidgets('alto por defecto 6 y personalizado', (WidgetTester t) async {
      await t.pumpWidget(k1Frame(const SizedBox(width: 200, child: TfAccentBar(value: 0.3))));
      expect(t.getSize(find.byType(TfAccentBar)), const Size(200, 6));
      await t.pumpWidget(k1Frame(const SizedBox(width: 200, child: TfAccentBar(value: 0.3, height: 8))));
      expect(t.getSize(find.byType(TfAccentBar)).height, 8);
    });
  });

  group('k1 progress, spinner, divider', () {
    testWidgets('progress 0.4', (WidgetTester t) async {
      await t.pumpWidget(k1Frame(const SizedBox(width: 160, child: TfProgress(value: 0.4))));
      await golden('k1_progress');
    });
    testWidgets('spinner small y mini', (WidgetTester t) async {
      await t.pumpWidget(k1Frame(const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[TfSpinner.small(), SizedBox(width: 12), TfSpinner.mini()],
      )));
      await t.pump(const Duration(milliseconds: 250));
      expect(t.getSize(find.byType(TfSpinner).first), const Size(16, 16));
      expect(t.getSize(find.byType(TfSpinner).last), const Size(10, 10));
      await golden('k1_spinner');
      await t.pumpWidget(const SizedBox());
    });
    testWidgets('divider horizontal y vertical', (WidgetTester t) async {
      await t.pumpWidget(k1Frame(const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(width: 80, child: TfDivider()),
          SizedBox(width: 12),
          TfDivider.vertical(),
        ],
      )));
      expect(t.getSize(find.byType(TfDivider).first), const Size(80, 1));
      expect(t.getSize(find.byType(TfDivider).last), const Size(1, 28));
      await golden('k1_divider');
    });
  });

  group('k1 cover', () {
    testWidgets('sin carátula', (WidgetTester t) async {
      await t.pumpWidget(k1Frame(const TfSongCover()));
      expect(t.getSize(find.byType(TfSongCover)), const Size(44, 44));
      await golden('k1_cover_empty');
    });
    testWidgets('con imagen', (WidgetTester t) async {
      late ImageProvider provider;
      await t.runAsync(() async {
        final ui.PictureRecorder rec = ui.PictureRecorder();
        ui.Canvas(rec).drawRect(
          const Rect.fromLTWH(0, 0, 8, 8),
          ui.Paint()..color = TfColors.accent,
        );
        final ui.Image img = await rec.endRecording().toImage(8, 8);
        final ByteData? bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        provider = MemoryImage(bytes!.buffer.asUint8List());
        await precacheImageForTest(provider);
      });
      await t.pumpWidget(k1Frame(TfSongCover(image: provider)));
      await t.pump();
      expect(find.byType(Image), findsOneWidget);
      await golden('k1_cover_image');
    });
    testWidgets('imagen corrupta cae al marcador', (WidgetTester t) async {
      await t.pumpWidget(k1Frame(TfSongCover(image: MemoryImage(Uint8List.fromList(<int>[1, 2, 3])))));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump();
      expect(find.byType(TfIconView), findsOneWidget);
    });
  });
}

Future<void> precacheImageForTest(ImageProvider p) {
  final Completer<void> c = Completer<void>();
  p.resolve(ImageConfiguration.empty).addListener(ImageStreamListener((ImageInfo i, bool _) => c.complete()));
  return c.future;
}
