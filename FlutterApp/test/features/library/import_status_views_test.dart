import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/link_resolve.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/library/link_import_store.dart';
import 'package:toneforge/features/library/sheets/import_status_views.dart';
import 'package:toneforge/features/library/source_messages.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

import '../../support/harness.dart';

final _calls = <String>[];

class _FakeStore extends LinkImportStore {
  _FakeStore(this.initial);

  final LinkImportState initial;

  @override
  LinkImportState build() {
    super.build();
    return initial;
  }

  @override
  Future<void> cancel() async => _calls.add('cancel');
  @override
  Future<void> retry() async => _calls.add('retry');
  @override
  Future<void> updateAndRetry() async => _calls.add('updateAndRetry');
  @override
  void reset() => _calls.add('reset');
  @override
  void setText(String t) => _calls.add('setText:$t');
}

late ProviderContainer _c;
var _closed = 0;

Future<AppLocalizations> _pump(WidgetTester tester, LinkImportState state, Widget Function() view) async {
  _calls.clear();
  _closed = 0;
  await tester.runAsync(loadTfFonts);
  setTestSurface(tester, const Size(620, 420));
  final core = (await tester.runAsync(() async => MockCore.load((await DirectoryFixtureSource.find())!)))!;
  _c = ProviderContainer(
    overrides: [
      coreClientProvider.overrideWithValue(core),
      linkImportStoreProvider.overrideWith(() => _FakeStore(state)),
    ],
  );
  addTearDown(_c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _c,
      child: WidgetsApp(
        color: TfColors.bg,
        debugShowCheckedModeBanner: false,
        locale: const Locale('es'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) =>
            PageRouteBuilder<T>(settings: s, pageBuilder: (ctx, a, b2) => b(ctx)),
        home: RepaintBoundary(
          key: k5Boundary,
          child: ColoredBox(
            color: TfColors.bg,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 560,
                child: Padding(
                  padding: const EdgeInsets.all(TfSpace.s20),
                  child: DefaultTextStyle(
                    style: TfText.body().copyWith(color: TfColors.text),
                    child: view(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return AppLocalizations.of(tester.element(find.byKey(k5Boundary)));
}

LinkImportState _error(String code, {String message = 'm', bool latest = false}) => LinkImportState(
  screen: LinkImportScreen.error,
  error: LinkImportError(code: code, message: message),
  alreadyLatest: latest,
);

void _close() => _closed++;

void main() {
  testWidgets('sourceErrorTexts: todos los códigos con título y regla de detalle', (tester) async {
    final l = await _pump(tester, const LinkImportState(), () => const SizedBox());
    const codes = [
      'offline', 'unsupported-link', 'spotify-unreadable', 'age-restricted', 'region', 'private-video',
      'removed', 'no-audio-format', 'extractor-broken', 'ffmpeg-failed', 'helper-missing', 'launch-failed',
      'http-status', 'timed-out', 'cancelled', 'checksum-mismatch', 'update-failed', 'rate-limited',
      'no-audio-produced',
    ];
    const long = 'a\nb\nc\nd\ne\nf';
    for (final c in codes) {
      final t = sourceErrorTexts(l, LinkImportError(code: c, message: long));
      expect(t.title, isNotEmpty, reason: c);
      if (c == 'cancelled') {
        expect(t.detail, isEmpty);
      } else {
        expect(t.detail, isNotEmpty, reason: c);
      }
    }
    for (final c in ['ffmpeg-failed', 'launch-failed', 'update-failed']) {
      expect(sourceErrorTexts(l, LinkImportError(code: c, message: long)).detail, 'c\nd\ne\nf');
    }
    expect(sourceErrorTexts(l, const LinkImportError(code: 'unsupported-link', message: 'x')).detail, l.library_importSupported);
    expect(
      sourceErrorTexts(l, const LinkImportError(code: 'extractor-broken', message: 'yt-dlp (versión 2026.1)')).title,
      l.library_srcExtractorBrokenTitleVersion('2026.1'),
    );
    expect(
      sourceErrorTexts(l, const LinkImportError(code: 'extractor-broken', message: 'yt-dlp')).title,
      l.library_srcExtractorBrokenTitle,
    );
    final unknown = sourceErrorTexts(l, const LinkImportError(code: 'zzz', message: 'raro'));
    expect(unknown.detail, 'raro');
  });

  testWidgets('resolviendo: metadatos y búsqueda; Cancelar', (tester) async {
    var l = await _pump(tester, const LinkImportState(screen: LinkImportScreen.resolving), () => const ImportResolvingView());
    expect(find.text(l.library_importReadingMeta), findsOneWidget);
    expect(find.text(l.library_importSlow), findsNothing);
    await tester.tap(find.text(l.library_importCancel));
    expect(_calls, ['cancel']);
    l = await _pump(
      tester,
      const LinkImportState(screen: LinkImportScreen.resolving, resolvePhase: LinkResolvePhase.searching),
      () => const ImportResolvingView(),
    );
    expect(find.text(l.library_importSearchingYt), findsOneWidget);
    expect(find.text(l.library_importSlow), findsOneWidget);
    await expectLater(find.byKey(k5Boundary), matchesGoldenFile('goldens/import_resolving.png'));
  });

  testWidgets('preparando: texto y Cancelar', (tester) async {
    final l = await _pump(tester, const LinkImportState(screen: LinkImportScreen.preparing), () => const ImportPreparingView());
    expect(find.text(l.library_importPreparing), findsOneWidget);
    await tester.tap(find.text(l.library_importCancel));
    expect(_calls, ['cancel']);
    await expectLater(find.byKey(k5Boundary), matchesGoldenFile('goldens/import_preparing.png'));
  });

  testWidgets('error: botón por cada LinkErrorAction', (tester) async {
    final cases = <(LinkImportState, LinkErrorAction, String Function(AppLocalizations), List<String>)>[
      (_error('extractor-broken'), LinkErrorAction.updateAndRetry, (l) => l.library_importUpdateRetry, ['updateAndRetry']),
      (_error('unsupported-link'), LinkErrorAction.tryOtherLink, (l) => l.library_importOtherLink, ['setText:', 'reset']),
      (_error('spotify-unreadable'), LinkErrorAction.pasteYoutube, (l) => l.library_importPasteYt, ['setText:', 'reset']),
      (_error('offline'), LinkErrorAction.retry, (l) => l.library_importRetry, ['retry']),
    ];
    for (final (state, action, label, expected) in cases) {
      expect(state.errorAction, action);
      final l = await _pump(tester, state, () => const ImportErrorView(onClose: _close));
      await tester.tap(find.text(label(l)));
      expect(_calls, expected, reason: '$action');
      await tester.tap(find.text(l.library_importClose));
      expect(_closed, 1);
    }
  });

  testWidgets('error: ya es la última versión muestra aviso y sin botón principal', (tester) async {
    final l = await _pump(tester, _error('extractor-broken', latest: true), () => const ImportErrorView(onClose: _close));
    expect(find.text(l.library_importAlreadyLatest), findsOneWidget);
    expect(find.text(l.library_importRetry), findsNothing);
    expect(find.text(l.library_importUpdateRetry), findsNothing);
  });

  testWidgets('error: golden', (tester) async {
    await _pump(tester, _error('offline'), () => const ImportErrorView(onClose: _close));
    await expectLater(find.byKey(k5Boundary), matchesGoldenFile('goldens/import_error.png'));
  });

  testWidgets('hecho: avisos y Cerrar', (tester) async {
    final l = await _pump(
      tester,
      const LinkImportState(screen: LinkImportScreen.done, notices: ['Aviso uno', 'Aviso dos']),
      () => const ImportDoneView(onClose: _close),
    );
    expect(find.text(l.library_importDone), findsOneWidget);
    expect(find.text('Aviso uno'), findsOneWidget);
    expect(find.text('Aviso dos'), findsOneWidget);
    await tester.tap(find.text(l.library_importClose));
    expect(_closed, 1);
  });

  group('repetido', () {
    final state = LinkImportState(
      screen: LinkImportScreen.repeated,
      resolved: LinkResolveResult.fromJson({
        'link': 'youtube',
        'pastedURL': 'https://youtu.be/x',
        'title': 'Enter Sandman',
        'noCloseCandidate': false,
        'candidates': <Object>[],
        'existing': {'id': 'ABC', 'title': 'Enter Sandman', 'artist': 'Metallica'},
      }),
    );

    testWidgets('«Abrir» selecciona el tema y cierra', (tester) async {
      final l = await _pump(tester, state, () => const ImportRepeatedView(onClose: _close));
      expect(find.text('Metallica'), findsOneWidget);
      expect(find.text(l.library_importRepeatedBody), findsOneWidget);
      await tester.tap(find.text(l.library_importOpen));
      expect(_c.read(selectedProjectProvider), 'ABC');
      expect(_closed, 1);
    });

    testWidgets('golden', (tester) async {
      await _pump(tester, state, () => const ImportRepeatedView(onClose: _close));
      await expectLater(find.byKey(k5Boundary), matchesGoldenFile('goldens/import_repeated.png'));
    });
  });
}
