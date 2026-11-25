import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/record/record_store.dart';
import 'package:toneforge/features/record/sheets/add_part_sheet.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_dropdown.dart';

import '../../support/harness.dart';

Json fx(String path) =>
    (json.decode(File('../Contract/fixtures/$path.json').readAsStringSync()) as Map).cast<String, Object?>();

Future<MockCore> openSheet(WidgetTester tester) async {
  setTestSurface(tester, const Size(900, 700));
  final core = MockCore()
    ..result('study.open', <String, Object?>{})
    ..result('record.open', fx('record/record.open.result'))
    ..result('audio.settings', fx('audio/audio.settings.result'))
    ..result('audio.setMeters', fx('audio/audio.setMeters.result'))
    ..result('record.addPart', fx('record/record.addPart.result'));
  late ProviderContainer c;
  await tester.pumpWidget(ProviderScope(
    overrides: [coreClientProvider.overrideWithValue(core)],
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
          builder: (context) {
            c = ProviderScope.containerOf(context);
            return GestureDetector(
              key: const ValueKey('open'),
              behavior: HitTestBehavior.opaque,
              onTap: () => showAddPartSheet(context),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    ),
  ));
  await tester.runAsync(() => c.read(recordStoreProvider.notifier).open('p1'));
  await tester.tap(find.byKey(const ValueKey('open')));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return core;
}

void main() {
  testWidgets('«Añadir» deshabilitado con nombre vacío o en blanco', (t) async {
    await openSheet(t);
    expect(find.text('Añadir parte'), findsOneWidget);
    TfPrimaryButton add() => t.widget<TfPrimaryButton>(find.byKey(const ValueKey('addpart-add')));
    expect(add().onPressed, isNull);
    await t.enterText(find.byType(EditableText), '   ');
    await t.pump();
    expect(add().onPressed, isNull);
    await t.enterText(find.byType(EditableText), 'Solo');
    await t.pump();
    expect(add().onPressed, isNotNull);
  });

  testWidgets('el selector ofrece «Ninguna» y los roles de guitarra del snapshot', (t) async {
    await openSheet(t);
    final dd = t.widget<TfDropdown<String?>>(find.byKey(const ValueKey('addpart-replaces')));
    expect(dd.items.first.label, 'Ninguna (parte añadida)');
    expect(dd.items.first.value, isNull);
    expect(dd.items.length, greaterThan(1));
  });

  testWidgets('Añadir envía record.addPart con el nombre recortado y cierra', (t) async {
    final core = await openSheet(t);
    await t.enterText(find.byType(EditableText), ' Solo ');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('addpart-add')));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final call = core.calls.singleWhere((x) => x.method == 'record.addPart');
    expect(call.params, {'name': 'Solo'});
    expect(find.text('Añadir parte'), findsNothing);
  });
}
