import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/frame_channel.dart';
import 'package:toneforge/core/frame_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/record/sheets/take_viewer_sheet.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_slider.dart';
import 'package:toneforge/widgets/tf_video_surface.dart';

import '../../support/harness.dart';

Json fx(String path) =>
    (json.decode(File('../Contract/fixtures/$path.json').readAsStringSync()) as Map).cast<String, Object?>();

const takeId = '00000000-0000-0000-0000-000000000002';

Json snap(String name, [Json extra = const {}]) => {...fx('takeview/takeview.$name.result'), ...extra};

MockCore newCore() => MockCore()
  ..result('takeview.open', snap('open'))
  ..result('takeview.close', <String, Object?>{})
  ..result('takeview.pause', snap('pause'))
  ..result('takeview.seek', snap('seek'))
  ..result('takeview.setBacking', snap('setBacking'))
  ..result('takeview.play', snap('open', {'playing': true, 'epoch': 1}))
  ..result('record.markBest', <String, Object?>{});

Future<void> openViewer(WidgetTester tester, MockCore core) async {
  setTestSurface(tester, const Size(900, 700));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      coreClientProvider.overrideWithValue(core),
      frameChannelProvider(FrameChannelId.take).overrideWithValue(null),
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
          builder: (context) => GestureDetector(
            key: const ValueKey('open'),
            behavior: HitTestBehavior.opaque,
            onTap: () => showTakeViewer(context, projectId: 'p', takeId: takeId),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.byKey(const ValueKey('open')));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

int count(MockCore c, String m) => c.calls.where((x) => x.method == m).length;
TfSlider slider(WidgetTester t) => t.widget<TfSlider>(find.byType(TfSlider));
List<TfSecondaryButton> actions(WidgetTester t) => t.widgetList<TfSecondaryButton>(find.byType(TfSecondaryButton)).toList();

void main() {
  testWidgets('abre: llama a takeview.open y muestra vídeo y controles', (t) async {
    final core = newCore();
    await openViewer(t, core);
    expect(core.calls.first.method, 'takeview.open');
    expect(core.calls.first.params, {'projectId': 'p', 'takeId': takeId});
    expect(find.byType(TfVideoSurface), findsOneWidget);
    expect(slider(t).onChanged, isNotNull);
    expect(find.text('0:00'), findsOneWidget);
    expect(find.text('0:03'), findsOneWidget);
    expect(find.text('Backing'), findsOneWidget);
  });

  testWidgets('sin vídeo: «Sin vídeo: solo audio»', (t) async {
    final core = newCore()..result('takeview.open', fx('takeview/takeview.open.no-video.result'));
    await openViewer(t, core);
    expect(find.text('Sin vídeo: solo audio'), findsOneWidget);
    expect(find.byType(TfVideoSurface), findsNothing);
  });

  testWidgets('play envía play, luego pausa; la posición avanza con el evento', (t) async {
    final core = newCore();
    await openViewer(t, core);
    await t.tap(find.byKey(const ValueKey('viewer-play')));
    await t.pump(const Duration(milliseconds: 100));
    expect(count(core, 'takeview.play'), 1);
    await t.tap(find.byKey(const ValueKey('viewer-play')));
    await t.pump(const Duration(milliseconds: 100));
    expect(count(core, 'takeview.pause'), 1);
    core.emit('takeview.position', {'seconds': 1.0, 'playing': true, 'rate': 1.0, 'at': 100.0, 'epoch': 5});
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('0:01'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 1100));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('0:02'), findsOneWidget);
  });

  testWidgets('seek desde el slider envía takeview.seek', (t) async {
    final core = newCore();
    await openViewer(t, core);
    await t.tap(find.byType(TfSlider));
    await t.pump(const Duration(milliseconds: 100));
    final seeks = core.calls.where((c) => c.method == 'takeview.seek').toList();
    expect(seeks, hasLength(1));
    final secs = ((seeks.single.params as Map)['seconds'] as num).toDouble();
    expect(secs, inInclusiveRange(1.0, 2.0));
  });

  testWidgets('sin backing: el botón queda deshabilitado', (t) async {
    final core = newCore()..result('takeview.open', snap('open', {'hasBacking': false, 'backingOn': false}));
    await openViewer(t, core);
    await t.tap(find.byKey(const ValueKey('viewer-backing')), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 100));
    expect(count(core, 'takeview.setBacking'), 0);
    expect(find.text('Backing mudo'), findsOneWidget);
  });

  testWidgets('con backing: pulsar envía setBacking', (t) async {
    final core = newCore();
    await openViewer(t, core);
    await t.tap(find.byKey(const ValueKey('viewer-backing')));
    await t.pump(const Duration(milliseconds: 100));
    expect(count(core, 'takeview.setBacking'), 1);
  });

  testWidgets('error: línea de error, controles deshabilitados, acciones activas', (t) async {
    final core = newCore()..failWith('takeview.open', const CoreError('open-failed', 'sin audio'));
    await openViewer(t, core);
    expect(find.text('No se pudo preparar la toma (sin audio).'), findsOneWidget);
    expect(slider(t).onChanged, isNull);
    await t.tap(find.byKey(const ValueKey('viewer-play')), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 100));
    expect(count(core, 'takeview.play'), 0);
    final a = actions(t);
    expect(a, hasLength(2));
    expect(a.every((b) => b.onPressed != null), isTrue);
  });

  testWidgets('cerrar llama a takeview.close', (t) async {
    final core = newCore();
    await openViewer(t, core);
    await t.tap(find.byKey(const ValueKey('viewer-close')));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(count(core, 'takeview.close'), 1);
    expect(find.byType(TfSlider), findsNothing);
  });
}
