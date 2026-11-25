import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/settings/settings_audio_tab.dart';
import 'package:toneforge/features/settings/widgets/audio_texts.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_dropdown.dart';

import '../../support/harness.dart';

Future<MockCore> _core(WidgetTester tester, {String? state}) async =>
    (await tester.runAsync(() => _load(state)))!;

Future<MockCore> _load(String? state) async {
  final src = await DirectoryFixtureSource.find();
  return MockCore.load(src!, state: state);
}

Future<void> _open(WidgetTester tester, MockCore core, {VoidCallback? onCalibrate}) async {
  setTestSurface(tester, const Size(1000, 1400));
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
        child: SingleChildScrollView(child: SettingsAudioTab(onCalibrate: onCalibrate)),
      ),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

TfSecondaryButton _calButton(WidgetTester t) => t
    .widgetList<TfSecondaryButton>(find.byType(TfSecondaryButton))
    .firstWhere((b) => b.label == 'Calibrar latencia');

void main() {
  testWidgets('dispositivos: tres grupos, selectores y frecuencia', (tester) async {
    await _open(tester, await _core(tester));
    expect(find.text('Dispositivo'), findsOneWidget);
    expect(find.text('Canales'), findsOneWidget);
    expect(find.text('Calibración'), findsOneWidget);
    expect(find.byType(TfDropdown<String?>), findsNWidgets(2));
    expect(find.text('Dispositivo de salida'), findsOneWidget);
    expect(find.text('Frecuencia de trabajo'), findsOneWidget);
    expect(find.text('44,1 kHz'), findsOneWidget);
    expect(find.text('Salidas 1 y 2 · estéreo'), findsWidgets);
  });

  testWidgets('sin entrada: motivo traducido por código y guitarra deshabilitada', (tester) async {
    await _open(tester, await _core(tester, state: 'noinput'));
    expect(find.text('Elige un dispositivo de entrada en Ajustes · Audio.'), findsOneWidget);
    expect(_calButton(tester).onPressed, isNull);
    expect(find.text('Ninguna'), findsWidgets);
    final dd = tester.widget<TfDropdown<int>>(find.byType(TfDropdown<int>).last);
    expect(dd.onChanged, isNull);
  });

  testWidgets('desajuste de frecuencia: aviso y «Usar la del dispositivo»', (tester) async {
    final core = await _core(tester, state: 'ratemismatch');
    await _open(tester, core);
    expect(find.text('El dispositivo está a 44,1 kHz y la frecuencia de trabajo es 48 kHz'),
        findsOneWidget);
    expect(find.text('Grabar y calibrar quedan bloqueados; el backing suena igual.'), findsOneWidget);
    expect(_calButton(tester).onPressed, isNull);
    await tester.tap(find.text('Usar 44,1 kHz como frecuencia de trabajo'));
    await tester.pump();
    final sent = core.calls.where((c) => c.method == 'audio.setSettings').toList();
    expect((sent.last.params! as Map)['workingSampleRate'], 44100);
  });

  testWidgets('dispositivo desconectado: opción «· desconectado» y bloqueo', (tester) async {
    await _open(tester, await _core(tester, state: 'disconnected'));
    expect(find.text('Dispositivo elegido · desconectado'), findsWidgets);
    expect(find.text('El dispositivo de entrada no está conectado.'), findsOneWidget);
    expect(_calButton(tester).onPressed, isNull);
  });

  testWidgets('sin calibrar: texto accent y botón activo que llama a onCalibrate', (tester) async {
    var n = 0;
    await _open(tester, await _core(tester), onCalibrate: () => n++);
    expect(find.text('Sin calibrar'), findsOneWidget);
    final b = _calButton(tester);
    expect(b.onPressed, isNotNull);
    b.onPressed!();
    expect(n, 1);
  });

  testWidgets('elegir «Ninguna» envía inputDeviceUID null explícito', (tester) async {
    final core = await _core(tester);
    await _open(tester, core);
    await tester.tap(find.byType(TfDropdown<String?>).at(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Ninguna').last);
    await tester.pump();
    final sent = core.calls.where((c) => c.method == 'audio.setSettings').toList();
    expect(sent, isNotEmpty);
    final p = sent.last.params! as Map;
    expect(p.containsKey('inputDeviceUID'), isTrue);
    expect(p['inputDeviceUID'], isNull);
  });

  test('blockSuffix pasa de kebab a camelCase y los desconocidos caen a message', () {
    expect(blockSuffix('audio-block-no-input-device'), 'noInputDevice');
    expect(blockSuffix('audio-block-busy'), 'busy');
  });
}
