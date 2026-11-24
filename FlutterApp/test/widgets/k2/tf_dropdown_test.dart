import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/widgets/tf_dropdown.dart';

import '../../support/harness.dart';

const List<TfDropdownItem<String>> _items = <TfDropdownItem<String>>[
  TfDropdownItem<String>(value: 'a', label: 'Alfa'),
  TfDropdownItem<String>(value: 'b', label: 'Bravo'),
  TfDropdownItem<String>(value: 'c', label: 'Charlie'),
];

void main() {
  setUpAll(loadTfFonts);

  const Size size = Size(320, 220);

  group('k2 TfDropdown', () {
    testWidgets('tap abre el menú y elegir avisa y cierra', (tester) async {
      final List<String> log = <String>[];
      await pumpK2(
        tester,
        TfDropdown<String>(items: _items, value: 'a', onChanged: log.add),
        size: size,
      );
      expect(find.text('Charlie').evaluate().length, 1); // solo la oculta de medida
      await tester.tap(find.byType(TfDropdown<String>));
      await tester.pump();
      expect(find.text('Charlie').evaluate().length, 2);
      await tester.tap(find.text('Charlie').last);
      await tester.pump();
      expect(log, <String>['c']);
      expect(find.text('Charlie').evaluate().length, 1); // solo la oculta de medida
    });

    testWidgets('teclado: Espacio abre, flechas mueven, Intro elige', (tester) async {
      final List<String> log = <String>[];
      await pumpK2(
        tester,
        TfDropdown<String>(items: _items, value: 'a', onChanged: log.add),
        size: size,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // no pasa del final
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(log, <String>['b']);
    });

    testWidgets('Esc cierra sin elegir', (tester) async {
      final List<String> log = <String>[];
      await pumpK2(
        tester,
        TfDropdown<String>(items: _items, value: 'a', onChanged: log.add),
        size: size,
      );
      await tester.tap(find.byType(TfDropdown<String>));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(log, isEmpty);
      expect(find.text('Charlie').evaluate().length, 1);
    });

    testWidgets('clic fuera cierra', (tester) async {
      final List<String> log = <String>[];
      await pumpK2(
        tester,
        TfDropdown<String>(items: _items, value: 'a', onChanged: log.add),
        size: size,
      );
      await tester.tap(find.byType(TfDropdown<String>));
      await tester.pump();
      await tester.tapAt(const Offset(300, 200));
      await tester.pump();
      expect(log, isEmpty);
      expect(find.text('Charlie').evaluate().length, 1);
    });

    testWidgets('ancho fijo respeta el ancho', (tester) async {
      await pumpK2(
        tester,
        TfDropdown<String>(items: _items, value: 'a', onChanged: (_) {}, width: 160),
        size: size,
      );
      expect(tester.getSize(find.byType(TfDropdown<String>)).width, 160);
    });

    testWidgets('deshabilitado no abre', (tester) async {
      await pumpK2(
        tester,
        const TfDropdown<String>(items: _items, value: 'a', onChanged: null),
        size: size,
      );
      await tester.tap(find.byType(TfDropdown<String>));
      await tester.pump();
      expect(find.text('Charlie').evaluate().length, 1);
    });

    testWidgets('k2 golden desplegable reposo y deshabilitado', (tester) async {
      await pumpK2(
        tester,
        Column(
          children: <Widget>[
            k2Row('contenido', TfDropdown<String>(items: _items, value: 'b', onChanged: (_) {})),
            k2Row('fijo 160', TfDropdown<String>(items: _items, value: 'c', onChanged: (_) {}, width: 160)),
            k2Row('deshabilitado', const TfDropdown<String>(items: _items, value: 'a', onChanged: null)),
          ],
        ),
        size: size,
      );
      await expectLater(k2Screen(), matchesGoldenFile('goldens/tf_dropdown.png'));
    });

    testWidgets('k2 golden desplegable abierto', (tester) async {
      await pumpK2(
        tester,
        TfDropdown<String>(items: _items, value: 'b', onChanged: (_) {}),
        size: size,
      );
      await tester.tap(find.byType(TfDropdown<String>));
      await tester.pump();
      await expectLater(k2Screen(), matchesGoldenFile('goldens/tf_dropdown_open.png'));
    });
  });
}
