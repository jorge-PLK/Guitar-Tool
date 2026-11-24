import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:toneforge/app.dart';

void main() {
  testWidgets('la app monta y muestra el título', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ToneForgeApp()));
    await tester.pumpAndSettle();
    expect(find.text('ToneForge'), findsOneWidget);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).theme?.brightness, Brightness.dark);
  });
}
