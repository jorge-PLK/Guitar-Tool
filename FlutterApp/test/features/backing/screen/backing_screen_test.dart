import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/shell/shell_providers.dart';
import 'package:toneforge/shell/shell_route.dart';
import 'package:toneforge/widgets/tf_progress.dart';

import 'screen_support.dart';

void main() {
  group('selector de tema', () {
    testWidgets('con temas separados lista solo los done y elegir llama select', (tester) async {
      final rig = await pumpBacking(tester, project: null);
      expect(find.text(es.backing_title), findsOneWidget);
      expect(find.text(es.backing_chooserPick), findsOneWidget);
      expect(rig.methods, ['library.list']);
      final rows = find.byType(GestureDetector);
      expect(rows, findsOneWidget);
      await tester.tap(rows);
      await settleFrames(tester);
      expect(rig.container.read(selectedProjectProvider), separatedId);
    });

    testWidgets('sin temas separados muestra el mensaje vacío', (tester) async {
      await pumpBacking(
        tester,
        project: null,
        setup: (c) => c.result('library.list', <String, Object?>{'projects': <Object?>[], 'skipped': <Object?>[]}),
      );
      expect(find.text(es.backing_chooserEmpty), findsOneWidget);
      expect(find.text(es.backing_chooserPick), findsNothing);
    });
  });

  testWidgets('abriendo muestra el spinner centrado y luego el contenido', (tester) async {
    await pumpBacking(tester, settle: false);
    expect(find.byType(TfSpinner), findsOneWidget);
    expect(find.text(es.backing_title), findsNothing);
    await settleFrames(tester);
    expect(find.byType(TfSpinner), findsNothing);
    expect(find.text(es.backing_title), findsOneWidget);
  });

  group('tema sin separar', () {
    void noStems(Json o) {
      final t = (o['transport']! as Map).cast<String, Object?>();
      t['channels'] = <Object?>[];
      o['emptyStems'] = <Object?>[];
    }

    testWidgets('solo cabecera y tarjeta; el botón va a la biblioteca', (tester) async {
      final rig = await pumpBacking(tester, tweak: noStems);
      expect(find.text(es.backing_title), findsOneWidget);
      expect(find.text(es.backing_notSeparatedTitle), findsOneWidget);
      expect(find.text(es.backing_notSeparatedBody), findsOneWidget);
      expect(find.text(es.backing_analyze), findsNothing);
      rig.container.read(shellRouteProvider.notifier).select(ShellRoute.backing);
      await tester.tap(find.text(es.backing_goToLibrary));
      await settleFrames(tester);
      expect(rig.container.read(shellRouteProvider), ShellRoute.library);
    });

    testWidgets('con stems vacíos (pero declarados) sí es contenido', (tester) async {
      await pumpBacking(tester, tweak: (o) {
        noStems(o);
        o['emptyStems'] = <Object?>[
          <String, Object?>{'kind': 'vocals', 'name': 'Voz'},
        ];
      });
      expect(find.text(es.backing_notSeparatedTitle), findsNothing);
    });
  });

  group('error de apertura', () {
    testWidgets('muestra el mensaje del núcleo y Reintentar reabre', (tester) async {
      final rig = await pumpBacking(
        tester,
        setup: (c) => c.failWith('study.open', const CoreError('not-found', 'No existe')),
      );
      expect(find.text(es.backing_errorLoadStems('No existe')), findsOneWidget);
      expect(rig.methods.where((m) => m == 'study.open').length, 1);
      await tester.tap(find.text(es.backing_retry));
      await settleFrames(tester);
      expect(rig.methods.where((m) => m == 'study.open').length, 2);
    });
  });

  group('marco', () {
    for (final h in [900.0, 600.0]) {
      testWidgets('alto de ventana $h sin desbordes', (tester) async {
        await pumpBacking(tester, size: Size(1100, h));
        expect(tester.takeException(), isNull);
        expect(find.text(es.backing_title), findsOneWidget);
      });
    }
  });
}
