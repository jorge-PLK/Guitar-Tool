import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/widgets/tf_middle_ellipsis.dart';
import 'package:toneforge/widgets/tf_settings_group.dart';

Widget _wrap(Widget child, {double width = 400}) => Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[SizedBox(width: width, child: child)],
        ),
      ),
    );

void main() {
  testWidgets('TfSettingsGroup sin nota no pinta Text de nota y es más bajo', (tester) async {
    const body = SizedBox(height: 10);
    await tester.pumpWidget(_wrap(const TfSettingsGroup(title: 'T', note: 'Una nota', children: [body])));
    final withNote = tester.getSize(find.byType(TfSettingsGroup)).height;
    expect(find.text('Una nota'), findsOneWidget);

    for (final note in <String?>[null, '']) {
      await tester.pumpWidget(_wrap(TfSettingsGroup(title: 'T', note: note, children: const [body])));
      expect(find.byType(Text), findsOneWidget);
      expect(tester.getSize(find.byType(TfSettingsGroup)).height, lessThan(withNote));
    }
  });

  testWidgets('TfMiddleEllipsisText: corto intacto, largo conserva extremos y cabe', (tester) async {
    const style = TextStyle(fontSize: 14);
    await tester.pumpWidget(_wrap(const TfMiddleEllipsisText('/a/b', style: style)));
    expect(find.text('/a/b'), findsOneWidget);

    const long = '/Users/jorge/Documents/ToneForge/Proyectos/MuyLargo/Carpeta-final';
    await tester.pumpWidget(_wrap(const TfMiddleEllipsisText(long, style: style), width: 200));
    final shown = tester.widget<Text>(find.byType(Text)).data!;
    expect(shown, contains('…'));
    expect(shown, startsWith('/Users'));
    expect(shown, endsWith('final'));
    expect(shown.length, lessThan(long.length));
    expect(tester.getSize(find.byType(Text)).width, lessThanOrEqualTo(200));
  });
}
