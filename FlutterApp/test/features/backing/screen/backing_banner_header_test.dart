import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/shell/shell_providers.dart';
import 'package:toneforge/shell/shell_route.dart';
import 'package:toneforge/widgets/tf_progress.dart';

import 'screen_support.dart';

void analysis(Json o, String state, {String? error}) {
  final a = (o['analysis']! as Map).cast<String, Object?>();
  a['state'] = state;
  if (error != null) a['error'] = error;
}

void main() {
  group('banner de análisis', () {
    testWidgets('ready no pinta nada', (tester) async {
      await pumpBacking(tester);
      expect(find.text(es.backing_analyzing), findsNothing);
      expect(find.text(es.backing_analysisMissing), findsNothing);
      expect(find.text(es.backing_analyze), findsNothing);
      expect(find.byType(TfSpinner), findsNothing);
    });

    testWidgets('analyzing: spinner y texto', (tester) async {
      await pumpBacking(tester, tweak: (o) => analysis(o, 'analyzing'));
      expect(find.text(es.backing_analyzing), findsOneWidget);
      expect(find.byType(TfSpinner), findsOneWidget);
      expect(find.text(es.backing_analyze), findsNothing);
    });

    testWidgets('missing: «Analizar» llama a study.analyze', (tester) async {
      final rig = await pumpBacking(tester, tweak: (o) => analysis(o, 'missing'));
      expect(find.text(es.backing_analysisMissing), findsOneWidget);
      await tester.tap(find.text(es.backing_analyze));
      await settleFrames(tester);
      expect(rig.methods, contains('study.analyze'));
    });

    testWidgets('failed: mensaje y «Reintentar» llama a study.analyze', (tester) async {
      final rig = await pumpBacking(tester, tweak: (o) => analysis(o, 'failed', error: 'sin memoria'));
      expect(find.text(es.backing_analysisFailed('sin memoria')), findsOneWidget);
      await tester.tap(find.text(es.backing_retry));
      await settleFrames(tester);
      expect(rig.methods, contains('study.analyze'));
    });

    testWidgets('error de carga en una caja propia', (tester) async {
      await pumpBacking(tester, tweak: (o) => o['loadError'] = 'Stem ilegible');
      expect(find.text('Stem ilegible'), findsOneWidget);
    });
  });

  group('cabecera', () {
    testWidgets('artista · título y «Backing track»', (tester) async {
      await pumpBacking(tester);
      expect(find.text(es.backing_title), findsOneWidget);
      expect(find.textContaining('Banda · '), findsOneWidget);
    });

    testWidgets('sin artista solo el título', (tester) async {
      await pumpBacking(tester, tweak: (o) {
        o['artist'] = null;
        o['title'] = 'Solo título';
      });
      expect(find.text('Solo título'), findsOneWidget);
    });

    testWidgets('«Sin guitarras» aparece con guitarra y llama a study.setMix', (tester) async {
      final rig = await pumpBacking(tester);
      expect(find.text(es.backing_withoutGuitars), findsOneWidget);
      await tester.tap(find.text(es.backing_withoutGuitars));
      await settleFrames(tester);
      expect(rig.methods.where((m) => m == 'study.setMix'), isNotEmpty);
    });

    testWidgets('sin guitarra no hay píldora', (tester) async {
      await pumpBacking(tester, tweak: (o) {
        final t = (o['transport']! as Map).cast<String, Object?>();
        t['channels'] = [
          for (final c in (t['channels']! as List).cast<Map<String, dynamic>>())
            if (c['kind'] != 'guitar') c,
        ];
      });
      expect(find.text(es.backing_withoutGuitars), findsNothing);
      expect(find.text(es.backing_tabButton), findsOneWidget);
    });

    testWidgets('«Tablatura» navega a la pestaña', (tester) async {
      final rig = await pumpBacking(tester);
      rig.container.read(shellRouteProvider.notifier).select(ShellRoute.backing);
      await tester.tap(find.text(es.backing_tabButton));
      await settleFrames(tester);
      expect(rig.container.read(shellRouteProvider), ShellRoute.tab);
    });
  });
}
