import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/features/montage/montage_cut_menu.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

import '../../support/harness.dart';

const _a = '00000000-0000-0000-0000-000000000001';
const _b = '00000000-0000-0000-0000-000000000002';

Future<void> pumpMenu(WidgetTester t, {required List<String?> picked, required List<String> deleted, String? selected = _a}) async {
  await t.runAsync(loadTfFonts);
  setTestSurface(t, const Size(320, 220));
  await t.pumpWidget(WidgetsApp(
    color: TfColors.bg,
    debugShowCheckedModeBanner: false,
    locale: const Locale('es'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) => PageRouteBuilder<T>(settings: s, pageBuilder: (a, _, _) => b(a)),
    home: DefaultTextStyle(
      style: TfText.body().copyWith(color: TfColors.text),
      child: RepaintBoundary(
        key: const ValueKey('shot'),
        child: ColoredBox(
          color: TfColors.bg,
          child: Align(
            alignment: Alignment.topLeft,
            child: MontageCutMenu(
              time: 3,
              selectedPartId: selected,
              choices: const [
                MontageCutChoice(id: _a, name: 'Guitarra', eligible: true),
                MontageCutChoice(id: _b, name: 'Bajo', eligible: false),
              ],
              onSelectPart: picked.add,
              onDelete: () => deleted.add('x'),
            ),
          ),
        ),
      ),
    ),
  ));
  await t.pump();
}

void main() {
  testWidgets('parte no elegible no llama a onSelectPart; la elegible si', (t) async {
    final picked = <String?>[];
    await pumpMenu(t, picked: picked, deleted: []);
    await t.tap(find.byKey(const ValueKey('montage-cut-part-$_b')));
    await t.pump();
    expect(picked, isEmpty);
    await t.tap(find.byKey(const ValueKey('montage-cut-part-$_a')));
    await t.tap(find.byKey(const ValueKey('montage-cut-auto')));
    expect(picked, [_a, null]);
  });

  testWidgets('el check marca solo la parte elegida y eliminar llama a onDelete', (t) async {
    final deleted = <String>[];
    await pumpMenu(t, picked: [], deleted: deleted);
    Finder check(String k) => find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(TfIconView));
    expect(check('montage-cut-part-$_a'), findsOneWidget);
    expect(check('montage-cut-part-$_b'), findsNothing);
    expect(check('montage-cut-auto'), findsNothing);
    expect(find.text('Desde 0:03 manda'), findsOneWidget);
    await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('goldens/montage_cut_menu.png'));
    await t.tap(find.byKey(const ValueKey('montage-cut-delete')));
    expect(deleted, hasLength(1));
  });

  testWidgets('sin parte elegida el check esta en Automatico', (t) async {
    await pumpMenu(t, picked: [], deleted: [], selected: null);
    expect(find.descendant(of: find.byKey(const ValueKey('montage-cut-auto')), matching: find.byType(TfIconView)), findsOneWidget);
  });
}
