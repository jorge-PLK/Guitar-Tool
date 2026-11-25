import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/widgets/chord_shape.dart';

void main() {
  test('fromContract convierte las cuerdas de la cejilla (6 = grave → 0)', () {
    final s = StudyChordShape.fromJson({
      'frets': [null, 2, 4, 4, 4, 2],
      'baseFret': 1,
      'barre': {'fret': 2, 'fromString': 5, 'toString': 1},
    });
    final v = ChordShape.fromContract(s);
    expect(v.frets, [null, 2, 4, 4, 4, 2]);
    expect(v.baseFret, 1);
    expect(v.barre, const ChordBarre(fret: 2, from: 1, to: 5));
  });

  test('fromContract sin cejilla', () {
    final s = StudyChordShape.fromJson({
      'frets': [0, 2, 2, 1, 0, 0],
      'baseFret': 1,
    });
    expect(ChordShape.fromContract(s).barre, isNull);
  });
}
