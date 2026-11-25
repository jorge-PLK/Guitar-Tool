import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/features/backing/widgets/position_bar.dart';
import 'package:toneforge/l10n/app_localizations.dart';

void main() {
  testWidgets('Semantics de la barra: etiqueta, valor y ±5 s', (WidgetTester tester) async {
    final SemanticsHandle h = tester.ensureSemantics();
    final List<double> seeks = <double>[];
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Localizations(
        locale: const Locale('es'),
        delegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 400, child: PositionBar(position: 62, duration: 200, onSeek: seeks.add)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final SemanticsNode n = tester.getSemantics(find.bySemanticsLabel('Posición'));
    expect(n.label, 'Posición');
    expect(n.value, '1:02 de 3:20');
    tester.semantics.performAction(find.semantics.byLabel('Posición'), SemanticsAction.increase);
    tester.semantics.performAction(find.semantics.byLabel('Posición'), SemanticsAction.decrease);
    expect(seeks, <double>[67, 57]);
    h.dispose();
  });
}
