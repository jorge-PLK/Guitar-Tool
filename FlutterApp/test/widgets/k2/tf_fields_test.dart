import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/widgets/tf_number_field.dart';
import 'package:toneforge/widgets/tf_text_field.dart';

import '../../support/harness.dart';

Future<void> _type(WidgetTester tester, String text) async {
  await tester.tap(find.byType(EditableText));
  await tester.pump();
  await tester.enterText(find.byType(EditableText), text);
  await tester.pump();
}

void main() {
  setUpAll(loadTfFonts);

  group('k2 TfNumberField', () {
    testWidgets('Intro confirma un número válido', (tester) async {
      final List<double> log = <double>[];
      await pumpK2(tester, TfNumberField(value: 10, onChanged: log.add));
      await _type(tester, '42');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(log, <double>[42]);
    });

    testWidgets('acepta coma decimal', (tester) async {
      final List<double> log = <double>[];
      await pumpK2(tester, TfNumberField(value: 10, decimals: 1, onChanged: log.add));
      await _type(tester, '2,5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(log, <double>[2.5]);
    });

    testWidgets('número inválido se rechaza y revierte el texto', (tester) async {
      final List<double> log = <double>[];
      await pumpK2(tester, TfNumberField(value: 10, onChanged: log.add));
      await _type(tester, '1.2.3');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(log, isEmpty);
      expect(find.text('10'), findsOneWidget);
    });

    testWidgets('fuera de rango se ajusta al límite', (tester) async {
      final List<double> log = <double>[];
      await pumpK2(tester, TfNumberField(value: 10, min: 0, max: 100, onChanged: log.add));
      await _type(tester, '500');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(log, <double>[100]);
    });

    testWidgets('al perder el foco confirma', (tester) async {
      final List<double> log = <double>[];
      await pumpK2(tester, TfNumberField(value: 10, onChanged: log.add));
      await _type(tester, '7');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(log, <double>[7]);
    });

    testWidgets('Esc descarta lo escrito', (tester) async {
      final List<double> log = <double>[];
      await pumpK2(tester, TfNumberField(value: 10, onChanged: log.add));
      await _type(tester, '99');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('10'), findsOneWidget);
      expect(log, isEmpty);
    });

    testWidgets('deshabilitado no se edita', (tester) async {
      await pumpK2(tester, const TfNumberField(value: 10, onChanged: null));
      await tester.tap(find.byType(EditableText));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('k2 golden campo numérico', (tester) async {
      await pumpK2(
        tester,
        Column(
          children: <Widget>[
            k2Row('reposo', TfNumberField(value: 120, onChanged: (_) {})),
            k2Row('con foco', TfNumberField(value: 120, onChanged: (_) {})),
            k2Row('deshabilitado', const TfNumberField(value: 120, onChanged: null)),
          ],
        ),
        size: const Size(240, 140),
      );
      await tester.tap(find.byType(TfNumberField).at(1));
      await tester.pump();
      await expectLater(k2Screen(), matchesGoldenFile('goldens/tf_number_field.png'));
    });
  });

  group('k2 TfTextField', () {
    testWidgets('escribir avisa y Intro envía', (tester) async {
      final List<String> changed = <String>[];
      final List<String> sent = <String>[];
      await pumpK2(
        tester,
        TfTextField(search: true, width: 240, onChanged: changed.add, onSubmitted: sent.add),
      );
      await _type(tester, 'ac');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(changed, <String>['ac']);
      expect(sent, <String>['ac']);
    });

    testWidgets('búsqueda: borrar vacía y avisa', (tester) async {
      final TextEditingController c = TextEditingController(text: 'abc');
      addTearDown(c.dispose);
      final List<String> changed = <String>[];
      await pumpK2(
        tester,
        TfTextField(
          search: true,
          width: 240,
          controller: c,
          onChanged: changed.add,
          clearSemanticLabel: 'Borrar',
        ),
      );
      await tester.tap(find.bySemanticsLabel('Borrar'));
      await tester.pump();
      expect(c.text, '');
      expect(changed, <String>['']);
      expect(find.bySemanticsLabel('Borrar'), findsNothing);
    });

    testWidgets('alturas: búsqueda 36, enlace 32', (tester) async {
      await pumpK2(tester, const TfTextField(search: true, width: 200));
      expect(tester.getSize(find.byType(TfTextField)).height, 36);
      await pumpK2(tester, const TfTextField(width: 200));
      expect(tester.getSize(find.byType(TfTextField)).height, 32);
    });

    testWidgets('deshabilitado no recibe foco', (tester) async {
      await pumpK2(tester, const TfTextField(width: 200, enabled: false));
      await tester.tap(find.byType(EditableText), warnIfMissed: false);
      await tester.pump();
      expect(tester.state<EditableTextState>(find.byType(EditableText)).widget.focusNode.hasFocus, isFalse);
    });

    testWidgets('k2 golden campo de texto', (tester) async {
      final TextEditingController filled = TextEditingController(text: 'Hotel California');
      addTearDown(filled.dispose);
      await pumpK2(
        tester,
        Column(
          children: <Widget>[
            k2Row('búsqueda', const TfTextField(search: true, width: 200, hint: 'Buscar tema o artista')),
            k2Row('con texto', TfTextField(search: true, width: 200, controller: filled)),
            k2Row('enlace', const TfTextField(width: 200, hint: 'O pega un enlace')),
            k2Row('deshabilitado', const TfTextField(search: true, width: 200, hint: 'Buscar', enabled: false)),
          ],
        ),
        size: const Size(340, 220),
      );
      await expectLater(k2Screen(), matchesGoldenFile('goldens/tf_text_field.png'));
    });
  });
}
