import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_scroll.dart';

import '../../support/harness.dart';

Widget _list({bool alwaysVisible = true}) => Center(
      child: SizedBox(
        width: 240,
        height: 200,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: TfColors.card,
            borderRadius: BorderRadius.circular(TfRadius.control),
            border: Border.all(color: TfColors.line, width: TfStroke.hairline),
          ),
          child: TfScroll(
            alwaysVisible: alwaysVisible,
            builder: (BuildContext c, ScrollController controller) =>
                ListView.builder(
              controller: controller,
              itemCount: 30,
              itemBuilder: (_, int i) => Padding(
                padding: const EdgeInsets.all(TfSpace.s8),
                child: Text(
                  'Fila $i',
                  style: TfText.body(13).copyWith(color: TfColors.text),
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  setUpAll(loadTfFonts);

  group('k4 scroll', () {
    testWidgets('desplaza el contenido con su propio controlador', (tester) async {
      await pumpK4(tester, _list());
      expect(find.text('Fila 20'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('Fila 0'), findsNothing);
    });

    testWidgets('golden con barra', (tester) async {
      await pumpK4(tester, _list());
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(WidgetsApp),
        matchesGoldenFile('goldens/k4_scroll.png'),
      );
    });
  });
}
