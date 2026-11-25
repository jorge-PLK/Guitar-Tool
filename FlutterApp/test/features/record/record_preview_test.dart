import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/record_state.dart';
import 'package:toneforge/core/core_client.dart' show Json;
import 'package:toneforge/core/frame_channel.dart';
import 'package:toneforge/core/frame_providers.dart';
import 'package:toneforge/features/record/record_store.dart';
import 'package:toneforge/features/record/widgets/record_preview.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_progress.dart';
import 'package:toneforge/widgets/tf_video_surface.dart';

import '../../support/harness.dart';

Json fx(String name) => (json.decode(File('../Contract/fixtures/record/record.state.$name.event.json').readAsStringSync())
        as Map)
    .cast<String, Object?>();

/// Snapshot del fixture [name]; [camera] y [phase] pisan campos concretos.
RecordSnapshot snap(String name, {Json? camera, String? phase}) {
  final Json j = Map<String, Object?>.of(fx(name));
  if (camera != null) j['camera'] = <String, Object?>{...(j['camera']! as Map).cast<String, Object?>(), ...camera};
  if (phase != null) j['phase'] = phase;
  return RecordSnapshot.fromJson(j);
}

class _FakeStore extends RecordStore {
  _FakeStore(this.initial);
  final RecordState initial;
  int rotations = 0;

  @override
  RecordState build() => initial;

  @override
  Future<void> rotateCamera() async => rotations++;
}

class _Fake {
  _Fake(this.store);
  final _FakeStore store;
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

Future<_Fake> _pump(WidgetTester tester, RecordSnapshot s) async {
  await tester.runAsync(loadTfFonts);
  setTestSurface(tester, const Size(800, 450));
  final _Fake f = _Fake(_FakeStore(RecordState(snapshot: s, opened: true)));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recordStoreProvider.overrideWith(() => f.store),
        frameChannelProvider(FrameChannelId.camera).overrideWithValue(f.channel),
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
            child: const SizedBox(width: 800, height: 450, child: RecordPreview()),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return f;
}

bool dotIs(WidgetTester tester, Color color) {
  final DecoratedBox box = tester.widget<DecoratedBox>(find.byKey(const ValueKey<String>('rec-dot')));
  return (box.decoration as BoxDecoration).color == color;
}

void main() {
  const String noVideo = 'Sin vídeo: se grabará solo el audio';

  testWidgets('sin cámara (none): marcador sin vídeo, sin formato ni Rotar', (tester) async {
    await _pump(tester, snap('camera-none'));
    expect(find.text(noVideo), findsOneWidget);
    expect(find.textContaining('Rotar'), findsNothing);
    expect(find.byType(TfVideoSurface), findsNothing);
  });

  testWidgets('sin permiso (denied): mismo marcador que sin cámara', (tester) async {
    await _pump(tester, snap('camera-denied'));
    expect(find.text(noVideo), findsOneWidget);
    expect(find.textContaining('Rotar'), findsNothing);
  });

  testWidgets('cámara simulada: marcador con nombre, formato y Rotar', (tester) async {
    await _pump(tester, snap('camera-simulated'));
    expect(find.textContaining('Vista previa de la cámara · '), findsOneWidget);
    expect(find.textContaining('(simulada)'), findsOneWidget);
    expect(find.textContaining('fps'), findsOneWidget);
    expect(find.textContaining('Rotar'), findsOneWidget);
  });

  testWidgets('buscando cámara (estado aún desconocido): spinner', (tester) async {
    await _pump(tester, snap('camera-simulated', camera: {'state': 'idle'}));
    expect(find.byType(TfSpinner), findsOneWidget);
    expect(find.byType(TfVideoSurface), findsNothing);
  });

  testWidgets('live: TfVideoSurface con canal falso, tamaño y giro; se suelta al salir', (tester) async {
    final _Fake f = await _pump(tester, snap('camera-live'));
    final TfVideoSurface v = tester.widget(find.byType(TfVideoSurface));
    expect(v.textureId, 7);
    expect(v.frameSize, const Size(640, 360));
    expect(v.rotation, 90);
    expect(find.byType(Texture), findsOneWidget);
    expect(f.created, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(f.disposed, 1);
  });

  testWidgets('cuenta atrás: número y REC rojo con prefijo', (tester) async {
    await _pump(tester, snap('counting'));
    final int beat = snap('counting').countBeat!;
    expect(find.text('$beat'), findsOneWidget);
    expect(find.textContaining('REC · Toma '), findsOneWidget);
    expect(dotIs(tester, TfColors.recordLive), isTrue);
  });

  testWidgets('reposo: REC gris sin prefijo y sin número', (tester) async {
    await _pump(tester, snap('idle'));
    expect(find.textContaining('REC · '), findsNothing);
    expect(find.textContaining('Toma '), findsOneWidget);
    expect(dotIs(tester, TfColors.muted), isTrue);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('grabando: REC rojo y Rotar deshabilitado (no llama al store)', (tester) async {
    final _Fake f = await _pump(tester, snap('recording'));
    expect(dotIs(tester, TfColors.recordLive), isTrue);
    await tester.tap(find.textContaining('Rotar'), warnIfMissed: false);
    expect(f.store.rotations, 0);
  });

  testWidgets('ajustando desfase: REC gris', (tester) async {
    await _pump(tester, snap('adjusting'));
    expect(dotIs(tester, TfColors.muted), isTrue);
  });

  testWidgets('reposo: «Rotar · 90°» llama a rotateCamera', (tester) async {
    final _Fake f = await _pump(tester, snap('camera-live'));
    expect(find.text('Rotar · 90°'), findsOneWidget);
    await tester.tap(find.text('Rotar · 90°'));
    expect(f.store.rotations, 1);
  });
}
