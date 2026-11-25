import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/widgets/tf_dropdown.dart';

const List<TfDropdownItem<String>> _items = <TfDropdownItem<String>>[
  TfDropdownItem<String>(value: 'a', label: 'Uno'),
  TfDropdownItem<String>(value: 'b', label: 'Dos'),
  TfDropdownItem<String>(value: 'c', label: 'Tres'),
];

Future<void> _pump(WidgetTester tester, Size surface, {required Alignment at, double inset = 0}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFF000000),
      pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) =>
          PageRouteBuilder<T>(settings: s, pageBuilder: (c, a, s2) => b(c)),
      home: Padding(
        padding: EdgeInsets.only(top: inset, bottom: inset),
        child: Align(
          alignment: at,
          child: TfDropdown<String>(items: _items, value: 'a', onChanged: (_) {}),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byType(TfDropdown<String>));
  await tester.pumpAndSettle();
}

Finder _inMenu(String t) =>
    find.descendant(of: find.byType(SingleChildScrollView), matching: find.text(t));

void main() {
  testWidgets('cerca del borde inferior abre hacia arriba y queda dentro', (tester) async {
    const Size surface = Size(800, 300);
    await _pump(tester, surface, at: Alignment.bottomLeft, inset: 20);
    final Rect button = tester.getRect(find.byType(TfDropdown<String>));
    expect(button.bottom, 280);
    await _open(tester);
    for (final String label in <String>['Dos', 'Tres']) {
      final Rect r = tester.getRect(_inMenu(label));
      expect(Offset.zero & surface, containsRect(r), reason: label);
      expect(r.bottom, lessThanOrEqualTo(button.top), reason: label);
    }
    final Rect menu = tester.getRect(find.byType(SingleChildScrollView));
    expect(menu.bottom, lessThanOrEqualTo(button.top));
  });

  testWidgets('arriba en la ventana abre hacia abajo', (tester) async {
    await _pump(tester, const Size(800, 300), at: Alignment.topLeft, inset: 20);
    final Rect button = tester.getRect(find.byType(TfDropdown<String>));
    await _open(tester);
    expect(tester.getRect(_inMenu('Dos')).top, greaterThanOrEqualTo(button.bottom));
    expect(tester.getRect(_inMenu('Tres')).top, greaterThanOrEqualTo(button.bottom));
  });

  testWidgets('superficie diminuta: el menú queda dentro y hace scroll', (tester) async {
    const Size surface = Size(300, 90);
    await _pump(tester, surface, at: Alignment.center);
    await _open(tester);
    final Rect menu = tester.getRect(find.byType(SingleChildScrollView));
    expect(Offset.zero & surface, containsRect(menu));
    final ScrollableState scroll = tester.state(find.byType(Scrollable));
    expect(scroll.position.maxScrollExtent, greaterThan(0));
  });
}

Matcher containsRect(Rect inner) => _ContainsRect(inner);

class _ContainsRect extends Matcher {
  const _ContainsRect(this.inner);

  final Rect inner;

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) =>
      item is Rect &&
      item.left <= inner.left + 0.01 &&
      item.top <= inner.top + 0.01 &&
      item.right >= inner.right - 0.01 &&
      item.bottom >= inner.bottom - 0.01;

  @override
  Description describe(Description d) => d.add('contains $inner');
}
