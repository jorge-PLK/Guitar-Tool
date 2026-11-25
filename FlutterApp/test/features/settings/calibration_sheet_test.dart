import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/settings/sheets/calibration_sheet.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_accent_bar.dart';
import 'package:toneforge/widgets/tf_buttons.dart';

import '../../support/harness.dart';

Future<MockCore> _core({String? state}) async {
  final src = await DirectoryFixtureSource.find();
  return MockCore.load(src!, state: state);
}

Future<void> _pumpFew(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Monta la app, espera a que el store cargue y abre la hoja.
Future<void> _open(WidgetTester tester, MockCore core) async {
  setTestSurface(tester, const Size(900, 900));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      coreClientProvider.overrideWithValue(core),
      launchOptionsProvider.overrideWithValue(const LaunchOptions(screen: 'settings-audio')),
    ],
    child: WidgetsApp(
      color: TfColors.bg,
      debugShowCheckedModeBanner: false,
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) =>
          PageRouteBuilder<T>(settings: s, pageBuilder: (c, a, b2) => b(c)),
      home: DefaultTextStyle(
        style: const TextStyle(),
        child: Builder(
          builder: (ctx) => GestureDetector(
            onTap: () => showCalibrationSheet(ctx),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  ));
  await _pumpFew(tester);
  await tester.tap(find.text('abrir'));
  await _pumpFew(tester);
}

Future<void> _emit(WidgetTester tester, MockCore core, Map<String, Object?> payload) async {
  core.emit('audio.calibration', payload);
  await _pumpFew(tester);
}

List<MockCall> _calls(MockCore core, String m) => [for (final c in core.calls) if (c.method == m) c];

TfPrimaryButton _primary(WidgetTester t) => t.widget<TfPrimaryButton>(find.byType(TfPrimaryButton));

const _running = {'phase': 'running', 'progress': 0.4};

void main() {
  testWidgets('pasos: tres párrafos y «Empezar» envía audio.calibrate', (tester) async {
    final core = (await tester.runAsync(_core))!;
    await _open(tester, core);
    expect(find.text('Calibrar latencia'), findsOneWidget);
    expect(find.textContaining('Conecta con un cable'), findsOneWidget);
    expect(find.textContaining('Con una pedalera'), findsOneWidget);
    expect(find.textContaining('10 pitidos'), findsOneWidget);
    expect(_primary(tester).label, 'Empezar');
    expect(_primary(tester).onPressed, isNotNull);
    await tester.tap(find.text('Empezar'));
    await _pumpFew(tester);
    expect(_calls(core, 'audio.calibrate'), hasLength(1));
  });

  testWidgets('bloqueado: motivo en acento y «Empezar» deshabilitado', (tester) async {
    final core = (await tester.runAsync(() => _core(state: 'noinput')))!;
    await _open(tester, core);
    expect(find.text('Elige un dispositivo de entrada en Ajustes · Audio.'), findsOneWidget);
    expect(_primary(tester).onPressed, isNull);
  });

  testWidgets('midiendo: barra y porcentaje, sin botones y sin poder cerrar', (tester) async {
    final core = (await tester.runAsync(_core))!;
    await _open(tester, core);
    await _emit(tester, core, _running);
    expect(find.textContaining('Midiendo'), findsOneWidget);
    expect(find.byType(TfAccentBar), findsOneWidget);
    expect(tester.widget<TfAccentBar>(find.byType(TfAccentBar)).value, 0.4);
    expect(find.text('40 %'), findsOneWidget);
    expect(find.byType(TfPrimaryButton), findsNothing);
    expect(find.byType(TfSecondaryButton), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _pumpFew(tester);
    expect(find.text('Calibrar latencia'), findsOneWidget);
  });

  testWidgets('resultado ok: chip, filas del núcleo y «Cerrar» envía dismissCalibration', (tester) async {
    final core = (await tester.runAsync(_core))!;
    await _open(tester, core);
    await _emit(tester, core, {
      'phase': 'finished',
      'outcome': 'success',
      'success': {
        'latencyMS': 53.15,
        'latencySamples': 2551.2,
        'spreadMS': 0,
        'spreadSamples': 0,
        'correctedTakes': 0,
        'rows': [
          {'label': 'Latencia', 'value': '53,15 ms · 2551,2 muestras'},
          {'label': 'Dispersión', 'value': '0,000 ms · 0,0 muestras'},
        ],
      },
    });
    expect(find.text('Calibrada'), findsOneWidget);
    expect(find.text('Latencia'), findsOneWidget);
    expect(find.text('53,15 ms · 2551,2 muestras'), findsOneWidget);
    expect(find.byType(TfSecondaryButton), findsNothing);
    await tester.tap(find.text('Cerrar'));
    await _pumpFew(tester);
    expect(find.text('Calibrar latencia'), findsNothing);
    expect(_calls(core, 'audio.dismissCalibration'), hasLength(1));
    expect(_calls(core, 'audio.cancelCalibration'), isEmpty);
  });

  testWidgets('fallo: título y pista por motivo; «Repetir» descarta y vuelve a los pasos', (tester) async {
    final core = (await tester.runAsync(_core))!;
    await _open(tester, core);
    await _emit(tester, core, {
      'phase': 'finished',
      'outcome': 'failure',
      'failure': {'reason': 'noSignal', 'spreadMS': 0, 'title': 'x', 'hint': 'y'},
    });
    expect(find.text('No llegó la señal de prueba'), findsOneWidget);
    expect(find.textContaining('Comprueba el cable'), findsOneWidget);
    await tester.tap(find.text('Repetir'));
    await _pumpFew(tester);
    expect(_calls(core, 'audio.dismissCalibration'), hasLength(1));
    expect(find.text('Empezar'), findsOneWidget);
  });

  testWidgets('fallo inestable: la dispersión entra en el título', (tester) async {
    final core = (await tester.runAsync(_core))!;
    await _open(tester, core);
    await _emit(tester, core, {
      'phase': 'finished',
      'outcome': 'failure',
      'failure': {'reason': 'unstable', 'spreadMS': 3, 'title': 'x', 'hint': 'y'},
    });
    expect(find.textContaining('Las medidas no coinciden entre sí (dispersión de 3'), findsOneWidget);
    expect(find.text('Repetir'), findsOneWidget);
    expect(find.text('Cerrar'), findsOneWidget);
  });

  testWidgets('error: «No se pudo calibrar» y el mensaje', (tester) async {
    final core = (await tester.runAsync(_core))!;
    await _open(tester, core);
    await _emit(tester, core, {'phase': 'finished', 'outcome': 'error', 'error': 'Sin sesión de audio'});
    expect(find.text('No se pudo calibrar'), findsOneWidget);
    expect(find.text('Sin sesión de audio'), findsOneWidget);
    expect(find.text('Repetir'), findsOneWidget);
  });

  testWidgets('«Cancelar» en los pasos cierra y descarta', (tester) async {
    final core = (await tester.runAsync(_core))!;
    await _open(tester, core);
    await tester.tap(find.text('Cancelar'));
    await _pumpFew(tester);
    expect(find.text('Calibrar latencia'), findsNothing);
    expect(_calls(core, 'audio.dismissCalibration'), hasLength(1));
  });

  testWidgets('hoja destruida midiendo: audio.cancelCalibration', (tester) async {
    final core = (await tester.runAsync(_core))!;
    await _open(tester, core);
    await _emit(tester, core, _running);
    // Cierre forzado (cambio de pantalla, cierre de ventana): se retira la ruta a la fuerza.
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pop();
    await _pumpFew(tester);
    expect(find.text('Calibrar latencia'), findsNothing);
    expect(_calls(core, 'audio.cancelCalibration'), hasLength(1));
  });
}
