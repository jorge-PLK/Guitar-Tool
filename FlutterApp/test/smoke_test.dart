import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:toneforge/app.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';

void main() {
  testWidgets('la app monta y muestra el título', (tester) async {
    // La pantalla inicial (Biblioteca) ya habla con el núcleo: sin dylib en tests, un MockCore.
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final core = await tester.runAsync(() async => MockCore.load((await DirectoryFixtureSource.find())!));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [coreClientProvider.overrideWithValue(core!)],
        child: const ToneForgeApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ToneForge'), findsOneWidget);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).theme?.brightness, Brightness.dark);
  });
}
