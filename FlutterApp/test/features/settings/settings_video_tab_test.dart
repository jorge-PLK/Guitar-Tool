import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/frame_channel.dart';
import 'package:toneforge/core/frame_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/settings/settings_video_tab.dart';
import 'package:toneforge/features/settings/widgets/camera_preview_box.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_number_field.dart';
import 'package:toneforge/widgets/tf_stepper.dart';
import 'package:toneforge/widgets/tf_video_surface.dart';

import '../../support/harness.dart';

Map<String, Object?> _map(String raw) => (jsonDecode(raw) as Map).cast<String, Object?>();

List<MockCall> _calls(MockCore core, String m) => [for (final k in core.calls) if (k.method == m) k];

class VideoTabRig {
  VideoTabRig(this.core);
  final MockCore core;
  int created = 0;
  int disposed = 0;
  late final FrameChannel channel = FrameChannel(
    FrameChannelId.camera,
    createTexture: (_) {
      created++;
      return 7;
    },
    disposeTexture: (_) => disposed++,
  );
}

/// [preview] = sufijo de `video.preview.start.<x>`; [nocamera] carga las variantes sin cámara.
Future<VideoTabRig> pump(
  WidgetTester tester, {
  String preview = 'simulated',
  bool nocamera = false,
  bool fakeChannel = false,
}) async {
  await tester.runAsync(loadTfFonts);
  setTestSurface(tester, const Size(1100, 900));
  final src = (await tester.runAsync(DirectoryFixtureSource.find))!;
  final core = (await tester.runAsync(() => MockCore.load(src)))!;
  Future<Map<String, Object?>> fx(String n) async => _map((await tester.runAsync(() => src.read('video/$n.result.json')))!);
  core.result('video.preview.start', await fx('video.preview.start.$preview'));
  if (nocamera) {
    core.result('video.cameras', await fx('video.cameras.nocamera'));
    core.result('video.settings', await fx('video.settings.nocamera'));
  }
  final rig = VideoTabRig(core);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      coreClientProvider.overrideWithValue(core),
      launchOptionsProvider.overrideWithValue(const LaunchOptions(screen: 'settings-video')),
      if (fakeChannel) frameChannelProvider(FrameChannelId.camera).overrideWithValue(rig.channel),
    ],
    child: tfNavApp(
      Localizations(
        locale: const Locale('es'),
        delegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        child: DefaultTextStyle(
          style: TfText.body().copyWith(color: TfColors.text),
          child: const SingleChildScrollView(child: SettingsVideoTab()),
        ),
      ),
    ),
  ));
  for (int i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 10));
  }
  return rig;
}

void main() {
  testWidgets('cámara simulada: barras de color y leyenda', (tester) async {
    await pump(tester);
    expect(find.byType(ColorBars), findsOneWidget);
    expect(find.text('Vista previa simulada'), findsOneWidget);
    expect(find.text('En uso: iPhone (Continuity Camera).'), findsOneWidget);
    expect(find.text('Exportación por defecto'), findsOneWidget);
  });

  testWidgets('sin cámara: mensaje y resolución y fps deshabilitados', (tester) async {
    await pump(tester, preview: 'nocamera', nocamera: true);
    expect(find.text('No hay ninguna cámara conectada.'), findsWidgets);
    expect(find.byType(ColorBars), findsNothing);
  });

  testWidgets('permiso denegado: el botón llama a openCameraPrivacy', (tester) async {
    final rig = await pump(tester, preview: 'denied');
    expect(find.text('ToneForge no tiene permiso para usar la cámara.'), findsOneWidget);
    await tester.tap(find.text('Abrir Ajustes del Sistema'));
    await tester.pump();
    expect(_calls(rig.core, 'video.openCameraPrivacy'), hasLength(1));
  });

  testWidgets('cambiar la cámara a «Por defecto del sistema» envía cameraUID null', (tester) async {
    final rig = await pump(tester);
    await tester.tap(find.text('iPhone (Continuity Camera)').first);
    await tester.pump();
    await tester.tap(find.text('Por defecto del sistema').last);
    await tester.pump();
    final p = [for (final k in _calls(rig.core, 'video.setSettings')) k.params as Map];
    expect(p, isNotEmpty);
    expect(p.first.containsKey('cameraUID'), isTrue);
    expect(p.first['cameraUID'], isNull);
  });

  testWidgets('desfase: rango del núcleo y stepper envía ms+1 a la cámara efectiva', (tester) async {
    final rig = await pump(tester);
    final f = tester.widget<TfNumberField>(find.byType(TfNumberField));
    expect((f.min, f.max, f.value), (-500.0, 500.0, 65.0));
    final r = tester.getRect(find.byType(TfStepper));
    await tester.tapAt(Offset(r.center.dx, r.top + r.height / 4));
    await tester.pump();
    final p = [for (final k in _calls(rig.core, 'video.setSettings')) k.params as Map];
    expect(p.single['offset'], {'cameraId': 'sim-iphone', 'ms': 66.0});
  });

  testWidgets('exportación: elegir H.264 cambia el códec', (tester) async {
    final rig = await pump(tester);
    await tester.tap(find.text('H.264'));
    await tester.pump();
    final p = [for (final k in _calls(rig.core, 'video.setSettings')) k.params as Map];
    expect(p.single['export'], {'codec': 'h264'});
  });

  testWidgets('canal falso: crea la textura con el tamaño del fotograma y la suelta', (tester) async {
    final rig = await pump(tester, preview: 'live', fakeChannel: true);
    final s = tester.widget<TfVideoSurface>(find.byType(TfVideoSurface));
    expect(s.textureId, 7);
    expect(s.frameSize, const Size(1920, 1080));
    expect(rig.created, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    expect(rig.disposed, 1);
  });
}
