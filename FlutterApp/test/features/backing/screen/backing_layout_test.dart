import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/features/backing/backing_layout.dart';

Widget _host(double available, List<Widget> kids) => Directionality(
      textDirection: TextDirection.ltr,
      child: SingleChildScrollView(
        child: FillLastLayout(
          available: available,
          spacing: 14,
          lastMinHeight: 270,
          lastIdealHeight: 346,
          children: kids,
        ),
      ),
    );

Widget _box(Key k, double h) => SizedBox(key: k, height: h);

void main() {
  const a = Key('a'), b = Key('b'), last = Key('last');

  testWidgets('el ultimo recibe el minimo cuando falta sitio', (t) async {
    await t.pumpWidget(_host(300, [_box(a, 100), _box(last, 10)]));
    expect(t.getSize(find.byKey(last)).height, 270);
  });

  testWidgets('el ultimo se limita al ideal', (t) async {
    await t.pumpWidget(_host(2000, [_box(a, 100), _box(last, 10)]));
    expect(t.getSize(find.byKey(last)).height, 346);
  });

  testWidgets('el ultimo rellena entre minimo e ideal', (t) async {
    await t.pumpWidget(_host(450, [_box(a, 100), _box(last, 10)]));
    expect(t.getSize(find.byKey(last)).height, 450 - 100 - 14);
  });

  testWidgets('exceso: el total supera available y hay scroll', (t) async {
    await t.pumpWidget(_host(300, [_box(a, 100), _box(last, 10)]));
    expect(t.getSize(find.byType(FillLastLayout)).height, 100 + 14 + 270);
    expect(t.getTopLeft(find.byKey(last)).dy, 114);
  });

  testWidgets('hijo de alto <= 0,5 no suma hueco', (t) async {
    await t.pumpWidget(_host(2000, [_box(a, 100), _box(b, 0), _box(last, 10)]));
    expect(t.getTopLeft(find.byKey(last)).dy, 114);
  });
}
