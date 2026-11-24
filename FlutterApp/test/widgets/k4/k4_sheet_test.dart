import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_menu.dart';
import 'package:toneforge/widgets/tf_popover.dart';
import 'package:toneforge/widgets/tf_scroll.dart';
import 'package:toneforge/widgets/tf_sheet.dart';

import '../../support/harness.dart';

void main() {
  setUpAll(loadTfFonts);

  group('k4 lamina', () {
    testWidgets('lamina de capas estaticas', (tester) async {
      await pumpK4(
        tester,
        Padding(
          padding: const EdgeInsets.all(TfSpace.s24),
          child: Wrap(
            spacing: TfSpace.s24,
            runSpacing: TfSpace.s24,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: <Widget>[
              const TfSheetScaffold(
                width: 480,
                title: 'Bienvenido',
                body: Text('Elige la carpeta donde guardar tus proyectos.'),
                actions: <Widget>[
                  K4Button(label: 'Cancelar'),
                  K4Button(label: 'Continuar', primary: true),
                ],
              ),
              const TfSheetScaffold(
                width: 540,
                padding: TfSpace.s28,
                background: TfColors.bg,
                title: 'Calibracion',
                body: Text('Toca una cuerda al aire y espera.'),
                actions: <Widget>[
                  K4Button(label: 'Repetir'),
                  K4Button(label: 'Aceptar', primary: true),
                ],
              ),
              TfPopoverSurface(
                child: Padding(
                  padding: const EdgeInsets.all(TfSpace.s16),
                  child: Text(
                    'Popover sin flecha',
                    style: TfText.body(13).copyWith(color: TfColors.text),
                  ),
                ),
              ),
              const TfMenuPanelPreview(),
              SizedBox(
                width: 200,
                height: 160,
                child: TfScroll(
                  alwaysVisible: true,
                  builder: (BuildContext c, ScrollController controller) =>
                      ListView(
                    controller: controller,
                    children: <Widget>[
                      for (int i = 0; i < 20; i++)
                        Text(
                          'Fila $i',
                          style: TfText.body(13).copyWith(color: TfColors.text),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        size: const Size(1200, 640),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(WidgetsApp),
        matchesGoldenFile('goldens/k4_sheet.png'),
      );
    });
  });
}

/// Menú estático dentro de su superficie, para la lámina.
class TfMenuPanelPreview extends StatelessWidget {
  const TfMenuPanelPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return TfPopoverSurface(
      child: TfMenuPanel(
        onClose: () {},
        entries: <TfMenuEntry>[
          TfMenuItem(label: 'Renombrar', onSelected: () {}),
          TfMenuItem(label: 'Duplicar', enabled: false, onSelected: () {}),
          const TfMenuDivider(),
          TfMenuItem(label: 'Borrar', destructive: true, onSelected: () {}),
        ],
      ),
    );
  }
}
