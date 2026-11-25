import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/playlist.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/library/playlist_store.dart';
import 'package:toneforge/features/library/sheets/playlist_queue_view.dart';
import 'package:toneforge/features/library/sheets/playlist_review_view.dart';
import 'package:toneforge/features/library/sheets/playlist_summary_view.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_accent_bar.dart';
import 'package:toneforge/widgets/tf_buttons.dart';

import '../../support/harness.dart';

class _FakeStore extends PlaylistStore {
  _FakeStore(this.snap);

  final PlaylistSnapshot snap;
  final calls = <String>[];

  @override
  PlaylistState build() => PlaylistState(snapshot: snap, sheetOpen: true);

  @override
  Future<CoreError?> choose(String id, String candidateId) async {
    calls.add('choose:$id:$candidateId');
    return null;
  }

  @override
  Future<CoreError?> skip(String id) async {
    calls.add('skip:$id');
    return null;
  }

  @override
  Future<CoreError?> start() async {
    calls.add('start');
    return null;
  }

  @override
  Future<CoreError?> resume() async {
    calls.add('resume');
    return null;
  }

  @override
  Future<CoreError?> retryFailed() async {
    calls.add('retryFailed');
    return null;
  }
}

late _FakeStore _store;

Future<PlaylistSnapshot> _load(WidgetTester tester, String name) async {
  final raw = await tester.runAsync(() async {
    final src = (await DirectoryFixtureSource.find())!;
    return src.read('playlist/playlist.changed.$name.event.json');
  });
  return PlaylistSnapshot.fromJson(jsonDecode(raw!) as Map<String, dynamic>);
}

Future<void> _mount(WidgetTester tester, PlaylistSnapshot snap, Widget view, String? golden) async {
  await tester.runAsync(loadTfFonts);
  setTestSurface(tester, const Size(880, 700));
  _store = _FakeStore(snap);
  final c = ProviderContainer(overrides: [playlistStoreProvider.overrideWith(() => _store)]);
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
        home: RepaintBoundary(
          key: const ValueKey('sheet'),
          child: ColoredBox(
            color: TfColors.card,
            child: DefaultTextStyle(
              style: TfText.body().copyWith(color: TfColors.text),
              child: Padding(padding: const EdgeInsets.all(TfSpace.s20), child: view),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
  if (golden != null) {
    await expectLater(find.byKey(const ValueKey('sheet')), matchesGoldenFile('goldens/$golden.png'));
  }
}

void main() {
  testWidgets('Revisar: cifras, chip dudoso, elegir y omitir, botones', (tester) async {
    final snap = await _load(tester, 'review');
    await _mount(tester, snap, const PlaylistReviewView(), 'playlist_review');
    final r = _store.state.review!;
    expect(find.text('${r.proposed} con candidato · ${r.doubtful} dudosos · ${r.skipped} omitidos'), findsOneWidget);
    expect(find.text('dudoso'), r.doubtful > 0 ? findsWidgets : findsNothing);
    final b = _store.state.buttons;
    expect(find.text('Descargar y procesar (${b.startCount})'), findsOneWidget);
    expect(find.text('Seguir buscando'), b.showSearchMore ? findsOneWidget : findsNothing);

    final first = _store.state.reviewRows.first;
    final cand = _store.state.reviewRows.firstWhere((i) => i.candidates.isNotEmpty);
    await tester.tap(find.text(cand.chosen?.title ?? cand.candidates.first.title).first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Omitir este tema'));
    await tester.pump();
    expect(_store.calls, contains('skip:${cand.id}'));
    await tester.tap(find.text(cand.chosen?.title ?? cand.candidates.first.title).first);
    await tester.pump(const Duration(milliseconds: 200));
    final other = cand.candidates.last;
    await tester.tap(find.textContaining(other.title).last);
    await tester.pump();
    expect(_store.calls.any((c) => c.startsWith('choose:${cand.id}:')), isTrue);
    expect(first.id.isNotEmpty, isTrue);
  });

  testWidgets('Cola en marcha: estados de fila y botones', (tester) async {
    final snap = await _load(tester, 'running');
    await _mount(tester, snap, const PlaylistQueueView(), 'playlist_queue');
    expect(find.text('Descargando, importando y separando'), findsOneWidget);
    expect(find.byType(TfAccentBar), findsWidgets);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Cerrar'), findsOneWidget);
    expect(find.text('Reanudar'), findsNothing);
    final q = _store.state.queue!;
    expect(find.text('${q.done} de ${q.total} temas'), findsOneWidget);
    final statuses = {for (final i in snap.items.where((i) => i.selected)) i.status};
    if (statuses.contains(PlaylistItemStatus.imported)) expect(find.text('Importado'), findsWidgets);
    if (statuses.contains(PlaylistItemStatus.pending)) expect(find.text('En cola'), findsWidgets);
    if (statuses.contains(PlaylistItemStatus.downloading)) {
      expect(find.textContaining('Descargando'), findsWidgets);
    }
  });

  testWidgets('Cola detenida: banner, actualizar y reintentar', (tester) async {
    final snap = await _load(tester, 'stopped');
    await _mount(tester, snap, const PlaylistQueueView(), null);
    expect(find.text('Cola detenida'), findsOneWidget);
    expect(find.textContaining('yt-dlp puede estar desactualizado'), findsOneWidget);
    expect(find.text('Actualizar y reintentar'), findsOneWidget);
    expect(find.text('Cancelar'), findsNothing);
    expect(find.text('Reanudar'), findsNothing);
  });

  testWidgets('Resumen: cifras y Fallidos en danger solo si > 0', (tester) async {
    final snap = await _load(tester, 'summary');
    await _mount(tester, snap, const PlaylistSummaryView(), 'playlist_summary');
    final t = _store.state.summary!;
    expect(find.text('Importación terminada'), findsOneWidget);
    for (final v in {t.imported, t.skipped, t.inLibrary, t.failed}) {
      expect(find.text('$v'), findsWidgets);
    }
    Color colorOf(String label) {
      final box = find.ancestor(of: find.text(label.toUpperCase()), matching: find.byType(Column)).first;
      final num = find.descendant(of: box, matching: find.byType(Text)).last;
      return tester.widget<Text>(num).style!.color!;
    }

    expect(colorOf('Fallidos'), t.failed > 0 ? TfColors.danger : TfColors.text2);
    expect(colorOf('Importados'), TfColors.ok);
    final b = _store.state.buttons;
    expect(find.text('Reintentar fallidos (${b.retryFailedCount})'), b.showRetryFailed ? findsOneWidget : findsNothing);
    expect(find.text('FALLIDOS'), _store.state.failedRows.isEmpty ? findsOneWidget : findsNWidgets(2));
    expect(find.byType(TfPrimaryButton), findsOneWidget);
  });

  testWidgets('Resumen con 0 fallidos: Fallidos en text2', (tester) async {
    final snap = await _load(tester, 'summary');
    final clean = PlaylistSnapshot.fromJson({
      ...jsonDecode(jsonEncode(_rawOf(snap))) as Map<String, dynamic>,
    });
    await _mount(tester, clean, const PlaylistSummaryView(), null);
    final box = find.ancestor(of: find.text('FALLIDOS'), matching: find.byType(Column)).first;
    final num = find.descendant(of: box, matching: find.byType(Text)).last;
    expect(tester.widget<Text>(num).style!.color, TfColors.text2);
    expect(find.text('Reintentar fallidos (0)'), findsNothing);
  });
}

// Sin copia estructurada del DTO: el snapshot ya cargado se reutiliza tal cual.
Map<String, dynamic> _rawOf(PlaylistSnapshot s) => {
  'step': 'summary',
  'name': s.name,
  'source': 'youtube',
  'kind': 'playlist',
  'mayBeTruncated': false,
  'isLive': false,
  'progress': 1,
  'warnings': <String>[],
  'items': <Object>[],
  'totals': {'total': 0, 'selected': 0, 'imported': 1, 'skipped': 0, 'failed': 0, 'inLibrary': 0, 'remaining': 0, 'queued': 0, 'duplicates': 0},
  'summary': {'imported': 1, 'skipped': 0, 'inLibrary': 0, 'failed': 0, 'remaining': 0, 'cancelled': false},
  'update': {'alreadyLatest': false, 'updating': false},
};
