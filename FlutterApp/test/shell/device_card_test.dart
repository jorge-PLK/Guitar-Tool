import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/device_card.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_sidebar_cards.dart';

import '../support/harness.dart';

Future<MockCore> _pump(WidgetTester tester, {String? uid, bool connected = true}) async {
  await tester.runAsync(loadTfFonts);
  final src = (await tester.runAsync(DirectoryFixtureSource.find))!;
  final core = (await tester.runAsync(() => MockCore.load(src)))!;
  final base = jsonDecode((await tester.runAsync(() => src.read('audio/audio.settings.result.json')))!)
      as Map<String, Object?>;
  core.result('audio.settings', <String, Object?>{...base, 'outputDeviceUID': ?uid});
  core.result('audio.devices', <String, Object?>{
    'inputs': <Object?>[],
    'outputs': <Object?>[
      <String, Object?>{
        'uid': 'hr',
        'name': 'HeadRush Flex Prime (USB)',
        'channels': 2,
        'connected': connected,
        'label': 'x',
      },
    ],
  });
  setTestSurface(tester, const Size(300, 200));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [coreClientProvider.overrideWithValue(core)],
      child: Localizations(
        locale: const Locale('es'),
        delegates: const [AppLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
        child: const Directionality(textDirection: TextDirection.ltr, child: DeviceCard()),
      ),
    ),
  );
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump();
  return core;
}

void main() {
  testWidgets('conectado: nombre, punto verde y «Conectado»', (tester) async {
    await _pump(tester, uid: 'hr');
    expect(find.text('HeadRush Flex Prime (USB)'), findsOneWidget);
    expect(find.text('Conectado'), findsOneWidget);
    expect(tester.widget<TfDeviceCard>(find.byType(TfDeviceCard)).connected, isTrue);
  });

  testWidgets('sin dispositivo elegido: «Salida del sistema» y «Por defecto»', (tester) async {
    await _pump(tester);
    expect(find.text('Salida del sistema'), findsOneWidget);
    expect(find.text('Por defecto'), findsOneWidget);
  });

  testWidgets('desconectado: «Sin conectar» con punto apagado', (tester) async {
    await _pump(tester, uid: 'hr', connected: false);
    expect(find.text('Dispositivo elegido'), findsOneWidget);
    expect(find.text('Sin conectar'), findsOneWidget);
    expect(tester.widget<TfDeviceCard>(find.byType(TfDeviceCard)).connected, isFalse);
    expect(TfColors.muted, isNotNull);
  });
}
