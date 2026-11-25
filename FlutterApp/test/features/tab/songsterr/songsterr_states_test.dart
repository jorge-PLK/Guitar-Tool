import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/features/tab/songsterr_pairing_row.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_accent_bar.dart';
import 'package:toneforge/widgets/tf_dropdown.dart';

import '../../../support/harness.dart';
import '../tab_test_support.dart';
import 'songsterr_sheet_test.dart' hide main;

const _base = <String, Object?>{
  'open': true,
  'results': <Object?>[],
  'busy': false,
  'canUse': false,
};

Map<String, Object?> _last = const {};

Future<Rig> bootWith(WidgetTester tester, Map<String, Object?> state) async {
  final rig = await boot(tester, open: false);
  _last = state;
  rig.core.emit('tab.songsterr.state', {..._base, ...state});
  await tester.runAsync(settle);
  await tester.pump();
  return rig;
}

Finder _btn(String label) => find.text(label);

Future<void> _tap(WidgetTester tester, Rig rig, String label) async {
  await tester.tap(_btn(label));
  await tester.runAsync(settle);
  // La respuesta del mock puede cambiar de etapa: se restablece el estado de la prueba.
  rig.core.emit('tab.songsterr.state', {..._base, ..._last});
  await tester.runAsync(settle);
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await loadTfFonts();
    await findFixtures();
  });

  testWidgets('working: texto, barra indeterminada y Cancelar vuelve atrás', (tester) async {
    final rig = await bootWith(tester, {
      'stage': 'working',
      'busy': true,
      'workingText': 'Leyendo Songsterr…',
    });
    expect(find.text('Leyendo Songsterr…'), findsOneWidget);
    expect(find.byType(TfAccentBar), findsOneWidget);
    expect(tester.getSize(find.byType(TfAccentBar)).width, 260);
    await _tap(tester, rig, 'Cancelar');
    expect(rig.methods, contains('tab.songsterr.back'));
  });

  testWidgets('failed: mensaje, Reintentar, Volver y Transcribir automáticamente',
      (tester) async {
    final rig = await bootWith(tester, {
      'stage': 'failed',
      'failure': {
        'kind': 'offline',
        'message': 'sin red',
        'canRetry': true,
      },
    });
    expect(find.text('No se pudo conectar con Songsterr. Comprueba la conexión.'),
        findsOneWidget);
    await _tap(tester, rig, 'Reintentar');
    expect(rig.methods, contains('tab.songsterr.retryImport'));
    await _tap(tester, rig, 'Volver');
    expect(rig.methods, contains('tab.songsterr.back'));
    await _tap(tester, rig, 'Transcribir automáticamente');
    expect(rig.methods, contains('tab.songsterr.automatic'));
  });

  testWidgets('pairing: filas, solos, extras, avisos y acciones al store', (tester) async {
    final rig = await bootWith(
        tester, fixture('tab.songsterr.state.result.pairingSolos.json'));
    expect(find.textContaining('Qué pista de Songsterr va con cada stem'), findsOneWidget);
    expect(find.text('Guitarra'), findsOneWidget);
    expect(find.text('Bajo'), findsOneWidget);
    expect(find.text('Solo 1 (0:12)'), findsOneWidget);
    expect(find.text('Solo 2 (1:01)'), findsOneWidget);
    expect(find.text('82 %'), findsOneWidget);
    expect(find.text('80 %'), findsOneWidget);
    expect(find.text('Pistas extra, sin stem: Rítmica. Entran en la tablatura y en el .gp y '
        'solo suenan con «Oír transcripción».'), findsOneWidget);
    expect(find.text('La estructura del tema difiere de la del audio.'), findsOneWidget);
    expect(find.byType(TfDropdown<int>), findsNWidgets(3));

    await tester.tap(find.byType(TfDropdown<int>).last);
    await tester.pump();
    await tester.tap(find.text('Rítmica (82 %)').last);
    await tester.runAsync(settle);
    await tester.pump();
    expect(rig.methods, contains('tab.songsterr.assign'));
    expect(rig.core.calls.last.params, {'stemId': 'bass', 'track': 0});

    await _tap(tester, rig, 'Atrás');
    expect(rig.methods, contains('tab.songsterr.back'));
    await _tap(tester, rig, 'Todo automático');
    expect(rig.methods, contains('tab.songsterr.allAutomatic'));
    await _tap(tester, rig, 'Aceptar');
    expect(rig.methods, contains('tab.songsterr.accept'));
    await _tap(tester, rig, 'Cancelar');
    expect(rig.methods, contains('tab.songsterr.close'));
  });

  testWidgets('pairing con solista sin secciones y sin pista elegida', (tester) async {
    await bootWith(tester, {
      'stage': 'pairing',
      'pairing': {
        'intro': '',
        'extraNames': <Object?>[],
        'warnings': <Object?>[],
        'slots': [
          {
            'stemId': 'guitar',
            'name': 'Guitarra',
            'kind': 'guitar',
            'role': 'lead',
            'choices': <Object?>[],
            'solos': <Object?>[],
          },
          {
            'stemId': 'bass',
            'name': 'Bajo',
            'kind': 'bass',
            'role': 'bass',
            'choices': <Object?>[],
            'solos': <Object?>[],
          },
        ],
      },
    });
    expect(find.text('Transcripción automática (el tema no tiene secciones de solo)'),
        findsOneWidget);
    expect(find.text('sin medir'), findsNothing);
    expect(find.byType(TfDropdown<int>), findsOneWidget);
  });

  test('confianza: tramos 0,6 y 0,35 exactos', () {
    expect(songsterrConfidenceColor(0.6), TfColors.ok);
    expect(songsterrConfidenceColor(0.59), TfColors.accent);
    expect(songsterrConfidenceColor(0.35), TfColors.accent);
    expect(songsterrConfidenceColor(0.34), TfColors.danger);
    expect(songsterrConfidenceColor(null), TfColors.muted);
  });
}
