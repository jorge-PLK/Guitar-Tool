import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/features/backing/widgets/chord_diagram.dart';
import 'package:toneforge/features/backing/widgets/chord_shape.dart';
import 'package:toneforge/theme/tokens.dart';

import '../../support/harness.dart';

const ChordShape _doOpen = ChordShape(frets: <int?>[null, 3, 2, 0, 1, 0]);
const ChordShape _fa = ChordShape(
  frets: <int?>[1, 3, 3, 2, 1, 1],
  barre: ChordBarre(fret: 1, from: 0, to: 5),
);
// Sol# con cejilla en el traste 4.
const ChordShape _solSharp = ChordShape(
  frets: <int?>[4, 6, 6, 5, 4, 4],
  baseFret: 4,
  barre: ChordBarre(fret: 4, from: 0, to: 5),
);

void main() {
  test('base: traste más bajo > 1 sin cuerdas al aire', () {
    expect(ChordDiagramPainter.baseOf(_solSharp), 4);
    expect(ChordDiagramPainter.baseOf(_fa), 1);
    expect(ChordDiagramPainter.baseOf(_doOpen), 1);
    const ChordShape withOpen = ChordShape(frets: <int?>[0, 5, 5, null, null, null], baseFret: 2);
    expect(ChordDiagramPainter.baseOf(withOpen), 2);
  });

  testWidgets('diagramas golden', (WidgetTester tester) async {
    Widget cell(ChordShape? s) => Padding(
          padding: const EdgeInsets.all(TfSpace.s8),
          child: ChordDiagram(shape: s),
        );
    await pumpK5(
      tester,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[cell(_doOpen), cell(_fa), cell(_solSharp), cell(null)],
      ),
      size: const Size(400, 110),
    );
    expect(tester.getSize(find.byType(ChordDiagram).first), const Size(72, 84));
    await expectLater(find.byKey(k5Boundary), matchesGoldenFile('goldens/chord_diagram.png'));
  });
}
