import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_sheet.dart';

import '../support/harness.dart';

void main() {
  setUpAll(loadTfFonts);

  Text labelOf(WidgetTester t, String s) => t.widget<Text>(find.text(s));

  testWidgets('TfSecondaryButton: weight y color', (WidgetTester t) async {
    await t.pumpWidget(k1Frame(TfSecondaryButton(
      label: 'Ir',
      weight: TfWeight.semibold,
      color: TfColors.text2,
      hPadding: TfSpace.s18,
      onPressed: () {},
    )));
    final TextStyle st = labelOf(t, 'Ir').style!;
    expect(st.fontWeight, FontWeight.w600);
    expect(st.color, TfColors.text2);
    expect(t.getSize(find.byType(TfSecondaryButton)).height, TfSize.controlLg);
  });

  testWidgets('TfSecondaryButton: por defecto medium y text', (WidgetTester t) async {
    await t.pumpWidget(k1Frame(TfSecondaryButton(label: 'Ir', onPressed: () {})));
    final TextStyle st = labelOf(t, 'Ir').style!;
    expect(st.fontWeight, FontWeight.w500);
    expect(st.color, TfColors.text);
    expect(find.byType(TfIconView), findsNothing);
  });

  testWidgets('TfSecondaryButton: icon a la izquierda', (WidgetTester t) async {
    await t.pumpWidget(k1Frame(TfSecondaryButton(label: 'Play', icon: TfIcon.playpauseFill, onPressed: () {})));
    expect(find.byType(TfIconView), findsOneWidget);
    expect(t.getTopLeft(find.byType(TfIconView)).dx, lessThan(t.getTopLeft(find.text('Play')).dx));
  });

  testWidgets('TfSheetScaffold: titleTrailing y spacing', (WidgetTester t) async {
    await t.pumpWidget(k1Frame(const TfSheetScaffold(
      width: 400,
      title: 'Titulo',
      titleTrailing: Text('chip'),
      spacing: 18,
      body: SizedBox(height: 10, child: Text('cuerpo')),
      actions: <Widget>[Text('pie')],
    )));
    expect(t.getCenter(find.text('chip')).dy, closeTo(t.getCenter(find.text('Titulo')).dy, 6));
    expect(t.getTopLeft(find.text('chip')).dx, greaterThan(t.getTopRight(find.text('Titulo')).dx));
    final double gap1 = t.getTopLeft(find.text('cuerpo')).dy - t.getBottomLeft(find.text('Titulo')).dy;
    expect(gap1, closeTo(18, 8));
    final double gap2 = t.getTopLeft(find.text('pie')).dy - t.getBottomLeft(find.text('cuerpo')).dy;
    expect(gap2, closeTo(18, 8));
  });

  test('TfText tabular', () {
    expect(TfText.body(12).fontFeatures, isNull);
    expect(TfText.display(12).fontFeatures, isNull);
    expect(TfText.body(12, TfWeight.regular, true).fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(TfText.display(12, TfWeight.bold, true).fontFeatures, contains(const FontFeature.tabularFigures()));
  });
}
