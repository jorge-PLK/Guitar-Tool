import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/link_resolve.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/library/link_import_store.dart';
import 'package:toneforge/features/library/sheets/candidate_row.dart';
import 'package:toneforge/features/library/sheets/import_banner.dart';
import 'package:toneforge/features/library/sheets/import_sheet.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/fmt.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_accent_bar.dart';
import 'package:toneforge/widgets/tf_buttons.dart';

import '../../support/harness.dart';

class _FakeLinkStore extends LinkImportStore {
  _FakeLinkStore(this.initial);

  final LinkImportState initial;
  final manual = <String>[];
  final opened = <String>[];
  int cancels = 0;

  @override
  LinkImportState build() => initial;

  void put(LinkImportState s) => state = s;

  @override
  void reset() {}

  @override
  Future<void> addManual(String url) async => manual.add(url);

  @override
  Future<void> openSpotify(String url, {String? fallback}) async => opened.add(url);

  @override
  Future<void> cancel() async => cancels++;
}

late _FakeLinkStore _store;
late BuildContext _ctx;
late Map<String, dynamic> _base;

Map<String, dynamic> _cand(String id, String title, {bool close = false, bool live = false, double? diff, bool lib = false}) => {
  'id': id,
  'title': title,
  'artist': 'Canal $id',
  'duration': 253,
  'source': 'youtube',
  'url': 'https://www.youtube.com/watch?v=$id',
  'isClose': close,
  'isLive': live,
  'difference': ?diff,
  if (lib) 'inLibrary': {'id': 'P9', 'title': 'Ya está', 'artist': 'Otro'},
};

LinkResolveResult _resolved(List<Map<String, dynamic>> cands, {bool noClose = false, Map<String, dynamic>? possible}) =>
    LinkResolveResult.fromJson({
      ..._base,
      'candidates': cands,
      'noCloseCandidate': noClose,
      'possibleDuplicate': ?possible,
    });

LinkImportState _cs(LinkResolveResult r, {String? selected, String title = 'Tema'}) => LinkImportState(
  screen: LinkImportScreen.candidates,
  resolved: r,
  title: title,
  artist: 'Otro',
  selectedId: selected,
);

final _list = [
  _cand('a', 'Versión A', close: true, diff: 1.2),
  _cand('b', 'Versión B en directo', live: true, diff: -4.5),
  _cand('c', 'Versión C', lib: true, diff: 0.4),
];

Future<void> _open(WidgetTester tester, LinkImportState Function() build) async {
  await tester.runAsync(loadTfFonts);
  setTestSurface(tester, const Size(1100, 860));
  final (core, base) = (await tester.runAsync(() async {
    final src = (await DirectoryFixtureSource.find())!;
    final core = await MockCore.load(src);
    final json = jsonDecode(await src.read('link/link.resolve.youtube.result.json'));
    return (core, json);
  }))!;
  _base = Map<String, dynamic>.from(base as Map);
  _store = _FakeLinkStore(build());
  final c = ProviderContainer(
    overrides: [coreClientProvider.overrideWithValue(core), linkImportStoreProvider.overrideWith(() => _store)],
  );
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: WidgetsApp(
        color: TfColors.bg,
        debugShowCheckedModeBanner: false,
        locale: const Locale('es'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) =>
            PageRouteBuilder<T>(settings: s, pageBuilder: (ctx, a, b2) => b(ctx)),
        home: ColoredBox(
          color: TfColors.bg,
          child: DefaultTextStyle(
            style: TfText.body().copyWith(color: TfColors.text),
            child: Builder(
              builder: (ctx) {
                _ctx = ctx;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    ),
  );
  unawaited(showImportSheet(_ctx));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _put(WidgetTester tester, LinkImportState s) async {
  _store.put(s);
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

AppLocalizations get _l => AppLocalizations.of(_ctx);

TfPrimaryButton get _go => find.byType(TfPrimaryButton).evaluate().single.widget as TfPrimaryButton;

Finder get _sheet => find.byType(ImportSheetBody);

void main() {
  testWidgets('candidatos: Importar deshabilitado sin candidato y sin título; seleccionar habilita', (tester) async {
    late LinkResolveResult r;
    await _open(tester, () => const LinkImportState());
    r = _resolved(_list);
    await _put(tester, _cs(r));
    expect(_go.onPressed, isNull);
    await tester.tap(find.text('Versión A'));
    await tester.pump();
    expect(_store.state.selectedId, 'a');
    await tester.pump(const Duration(milliseconds: 400));
    expect(_go.onPressed, isNotNull);
    await _put(tester, _cs(r, selected: 'a', title: ' '));
    expect(_go.onPressed, isNull);
    await expectLater(_sheet, matchesGoldenFile('goldens/import_candidates.png'));
  });

  testWidgets('fila En la biblioteca: no seleccionable, opacidad 0,7, chips y diferencia con signo', (tester) async {
    await _open(tester, () => const LinkImportState());
    await _put(tester, _cs(_resolved(_list)));
    expect(find.text(_l.library_importChipClose), findsOneWidget);
    expect(find.text(_l.library_importChipLive), findsOneWidget);
    expect(find.text(_l.library_importChipInLibrary), findsOneWidget);
    expect(find.text('+1,2 s'), findsOneWidget);
    expect(find.text('-4,5 s'), findsOneWidget);
    final row = find.ancestor(of: find.text('Versión C'), matching: find.byType(CandidateRow));
    expect(find.descendant(of: row, matching: find.byType(Opacity)).evaluate().isNotEmpty, isTrue);
    final op = tester.widget<Opacity>(find.ancestor(of: find.text('Versión C'), matching: find.byType(Opacity)).first);
    expect(op.opacity, closeTo(0.7, 0.001));
    await tester.tap(find.text('Versión C'));
    await tester.pump();
    expect(_store.state.selectedId, isNull);
  });

  testWidgets('añadir manual envía la URL; vacío deshabilitado', (tester) async {
    await _open(tester, () => const LinkImportState());
    await _put(tester, _cs(_resolved(_list)));
    final add = find.widgetWithText(TfSecondaryButton, _l.library_importManualAdd);
    expect(tester.widget<TfSecondaryButton>(add).onPressed, isNull);
    await tester.enterText(find.byType(EditableText).last, 'https://youtu.be/zzz');
    await tester.pump();
    expect(tester.widget<TfSecondaryButton>(add).onPressed, isNotNull);
    await tester.tap(add);
    await tester.pump();
    expect(_store.manual, ['https://youtu.be/zzz']);
  });

  testWidgets('sin cercano: aviso; confirmación de un vídeo único', (tester) async {
    await _open(tester, () => const LinkImportState());
    await _put(tester, _cs(_resolved([_cand('b', 'Lejos', diff: 9)], noClose: true)));
    expect(find.byType(ImportBanner), findsOneWidget);
    expect(find.text(_l.library_importNoClose(3)), findsOneWidget);
    await _put(tester, _cs(_resolved([_cand('a', 'Único', close: true)])));
    expect(find.text(_l.library_importVideoLabel), findsOneWidget);
    expect(find.byType(CandidateRow), findsNothing);
    expect(_go.onPressed, isNotNull);
    await expectLater(_sheet, matchesGoldenFile('goldens/import_confirm.png'));
  });

  testWidgets('posible repetido: banda y golden', (tester) async {
    await _open(tester, () => const LinkImportState());
    final r = _resolved(_list, possible: {'id': 'P1', 'title': 'Parecido', 'artist': 'Otro'});
    await _put(tester, _cs(r, selected: 'a'));
    expect(find.text(_l.library_importPossible('Parecido · Otro')), findsOneWidget);
    await expectLater(_sheet, matchesGoldenFile('goldens/import_possible_dup.png'));
  });

  testWidgets('trabajando: fases, porcentaje y barra', (tester) async {
    await _open(tester, () => const LinkImportState());
    LinkImportState w(LinkWorkPhase p, [double? prog]) => LinkImportState(
      screen: LinkImportScreen.working,
      title: 'Tema',
      artist: 'Otro',
      workPhase: p,
      progress: prog,
    );
    await _put(tester, w(LinkWorkPhase.downloading, 0.42));
    expect(find.text(_l.library_importDownloading), findsOneWidget);
    expect(find.text(TfFmt.percent(0.42)), findsOneWidget);
    expect(tester.widget<TfAccentBar>(find.byType(TfAccentBar)).value, 0.42);
    expect(tester.widget<TfSecondaryButton>(find.byType(TfSecondaryButton)).onPressed, isNotNull);
    await expectLater(_sheet, matchesGoldenFile('goldens/import_working.png'));
    await _put(tester, w(LinkWorkPhase.converting, 0.9));
    expect(find.text(_l.library_importConverting), findsOneWidget);
    await _put(tester, w(LinkWorkPhase.importing));
    expect(find.text(_l.library_importImporting), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(tester.widget<TfAccentBar>(find.byType(TfAccentBar)).value, isNull);
    expect(tester.widget<TfSecondaryButton>(find.byType(TfSecondaryButton)).onPressed, isNull);
    await _put(tester, w(LinkWorkPhase.updating));
    expect(find.text(_l.library_importUpdating), findsOneWidget);
  });

  testWidgets('Esc no cierra con trabajo sin cancelar; sí cuando se puede', (tester) async {
    await _open(tester, () => const LinkImportState());
    await _put(
      tester,
      const LinkImportState(screen: LinkImportScreen.working, workPhase: LinkWorkPhase.importing, title: 'T'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    expect(_sheet, findsOneWidget);
  });

  test('signedSeconds', () {
    expect(signedSeconds(1.2, 'es'), '+1,2 s');
    expect(signedSeconds(-0.04, 'en'), '-0.0 s');
    expect(signedSeconds(3, 'en'), '+3.0 s');
  });
}
