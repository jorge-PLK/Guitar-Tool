import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tf_probe/probe6_snapshot.dart';

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
        Future.value(
          ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()),
        ),
      );
    }
    await loader.load();
  }

  await load('Inter', [
    'inter-latin-400.ttf',
    'inter-latin-500.ttf',
    'inter-latin-600.ttf',
  ]);
  await load('Space Grotesk', [
    'space-grotesk-latin-500.ttf',
    'space-grotesk-latin-700.ttf',
  ]);
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('pantalla de prueba 1440x900', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(child: ProbeScreen()),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('goldens/probe_screen.png'),
    );
  });
}
