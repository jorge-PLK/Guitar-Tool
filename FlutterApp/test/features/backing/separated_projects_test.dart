import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/features/backing/separated_projects.dart';

ProjectSummary _project(String id, String title, String createdAt) => ProjectSummary.fromJson({
  'id': id,
  'title': title,
  'folderName': id,
  'duration': 1.0,
  'sampleRate': 44100.0,
  'createdAt': createdAt,
  'updatedAt': createdAt,
  'separationState': 'done',
  'stemCount': 0,
  'takeCount': 0,
  'rigCount': 0,
  'hasAnalysis': false,
  'guitars': <String>[],
});

void main() {
  test('sortByCreatedAtDesc pone el tema más reciente primero, no por título', () {
    final list = [
      _project('a', 'Aquellas Cosas Que Solíamos Hacer', '2026-02-01T00:00:00Z'),
      _project('t', 'Tornado Of Souls', '2026-05-01T00:00:00Z'),
      _project('e', 'El roce de tu cuerpo', '2026-03-01T00:00:00Z'),
    ];
    expect(sortByCreatedAtDesc(list).map((p) => p.id), ['t', 'e', 'a']);
  });

  test('empate de fecha conserva el orden de entrada', () {
    final list = [
      _project('b', 'Beta', '2026-01-01T00:00:00Z'),
      _project('a', 'Alfa', '2026-01-01T00:00:00Z'),
    ];
    expect(sortByCreatedAtDesc(list).map((p) => p.id), ['b', 'a']);
  });

  test('fecha no parseable va al final', () {
    final list = [
      _project('x', 'Equis', 'no-es-fecha'),
      _project('n', 'Ene', '2026-01-01T00:00:00Z'),
    ];
    expect(sortByCreatedAtDesc(list).map((p) => p.id), ['n', 'x']);
  });
}
