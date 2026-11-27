import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/contract/montage.dart';
import 'package:toneforge/core/core_client.dart' show CoreError, Json;
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/frame_channel.dart';
import 'package:toneforge/core/frame_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/library/library_store.dart';
import 'package:toneforge/features/montage/montage_preview.dart';
import 'package:toneforge/features/montage/montage_screen.dart';
import 'package:toneforge/features/montage/montage_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/shell/shell_providers.dart';
import 'package:toneforge/shell/shell_route.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_progress.dart';

import '../../support/harness.dart';

const String _pid = '00000000-0000-0000-0000-000000000005';

Json _fx(String name) =>
    (json.decode(File('../Contract/fixtures/montage/montage.$name.json').readAsStringSync()) as Map).cast<String, Object?>();

class _FakeLibrary extends LibraryStore {
  @override
  LibraryState build() => LibraryState(
        projectsFolder: '/Users/x/Projects',
        entries: <ProjectSummary>[
          ProjectSummary.fromJson(<String, Object?>{
            'id': _pid,
            'title': 'Delta',
            'folderName': 'Delta',
            'duration': 10,
            'sampleRate': 48000,
            'createdAt': 'x',
            'updatedAt': 'x',
            'separationState': 'done',
            'stemCount': 1,
            'takeCount': 4,
            'rigCount': 0,
            'hasAnalysis': false,
            'guitars': <String>[],
          }),
        ],
      );
}

class _TwoSongsLibrary extends LibraryStore {
  @override
  LibraryState build() => LibraryState(
        projectsFolder: '/Users/x/Projects',
        entries: <ProjectSummary>[
          for (final (String id, String title) in <(String, String)>[
            ('00000000-0000-0000-0000-000000000001', 'Tornado Of Souls'),
            ('00000000-0000-0000-0000-000000000002', 'El roce de tu cuerpo'),
          ])
            ProjectSummary.fromJson(<String, Object?>{
              'id': id,
              'title': title,
              'folderName': title,
              'duration': 10,
              'sampleRate': 48000,
              'createdAt': 'x',
              'updatedAt': 'x',
              'separationState': 'done',
              'stemCount': 1,
              'takeCount': 2,
              'rigCount': 0,
              'hasAnalysis': false,
              'guitars': <String>[],
            }),
        ],
      );
}

class _EmptyLibrary extends LibraryStore {
  @override
  LibraryState build() => const LibraryState(projectsFolder: '/Users/x/Projects');
}

/// Fixture `open.result` con el análisis terminado (el original está analizando).
Json _ready() => <String, Object?>{..._fx('open.result'), 'isAnalyzing': false};

MockCore _core({Json? open, CoreError? openError}) {
  final MockCore core = MockCore()
    ..result('montage.close', <String, Object?>{})
    ..result('montage.play', open ?? _ready())
    ..result('montage.pause', open ?? _ready())
    ..result('montage.startExport', open ?? _ready())
    ..result('montage.cancelExport', open ?? _ready())
    ..result('montage.dismissExport', open ?? _ready());
  if (openError != null) {
    core.failWith('montage.open', openError);
  } else {
    core.result('montage.open', open ?? _ready());
  }
  return core;
}

Widget _app(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: WidgetsApp(
        color: TfColors.bg,
        debugShowCheckedModeBanner: false,
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) =>
            PageRouteBuilder<T>(settings: s, pageBuilder: (c, a, b2) => b(c)),
        home: DefaultTextStyle(
          style: TfText.body().copyWith(color: TfColors.text),
          child: const RepaintBoundary(child: ColoredBox(color: TfColors.bg, child: MontageScreen())),
        ),
      ),
    );

Future<void> _settle(WidgetTester t) async {
  for (int i = 0; i < 6; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await t.pump();
  }
}

Future<void> _pump(WidgetTester t, MockCore core, {bool select = true, Size size = const Size(1440, 900)}) async {
  await t.runAsync(loadTfFonts);
  setTestSurface(t, size);
  final ProviderContainer c = _container(core);
  if (select) c.read(selectedProjectProvider.notifier).select(_pid);
  await t.pumpWidget(_app(c));
  await _settle(t);
}

class _FixedReady extends MontageStore {
  _FixedReady(this.snapshot);
  final MontageSnapshot snapshot;

  @override
  MontageState build() => MontageState(projectId: _pid, snapshot: snapshot);

  @override
  Future<void> close() async {}
}

class _Loading extends MontageStore {
  @override
  MontageState build() => const MontageState(projectId: _pid, loading: true);
}

ProviderContainer _container(MockCore core, {List<Override> extra = const <Override>[], bool twoSongs = false, bool empty = false}) {
  final ProviderContainer c = ProviderContainer(overrides: [
    ...extra,
    coreClientProvider.overrideWithValue(core),
    libraryStoreProvider.overrideWith(empty ? _EmptyLibrary.new : twoSongs ? _TwoSongsLibrary.new : _FakeLibrary.new),
    frameChannelProvider(FrameChannelId.montage).overrideWithValue(null),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<void> _golden(WidgetTester t, String name) =>
    expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('goldens/$name.png'));

List<String> _methods(MockCore c) => <String>[for (final MockCall m in c.calls) m.method];

void main() {
  testWidgets('sustituir la pantalla en el mismo frame no da de baja la textura que pinta la nueva', (t) async {
    await t.runAsync(loadTfFonts);
    setTestSurface(t, const Size(1440, 900));
    final Set<int> live = <int>{};
    final FrameChannel channel = FrameChannel(
      FrameChannelId.montage,
      createTexture: (_) {
        live.add(11);
        return 11;
      },
      disposeTexture: (_) => live.remove(11),
    );
    final Json open = _ready();
    open['preview'] = <String, Object?>{...(open['preview']! as Map).cast<String, Object?>(), 'phase': 'ready'};
    final ProviderContainer c = ProviderContainer(overrides: [
      coreClientProvider.overrideWithValue(_core(open: open)),
      libraryStoreProvider.overrideWith(_FakeLibrary.new),
      // Estado fijo: el `close` de la pantalla vieja no debe vaciar el tema de la nueva.
      montageStoreProvider.overrideWith(() => _FixedReady(MontageSnapshot.fromJson(open))),
      frameChannelProvider(FrameChannelId.montage).overrideWithValue(channel),
    ]);
    addTearDown(c.dispose);
    c.read(selectedProjectProvider.notifier).select(_pid);
    Widget host(int n) => UncontrolledProviderScope(
          container: c,
          child: WidgetsApp(
            color: TfColors.bg,
            locale: const Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) =>
                PageRouteBuilder<T>(settings: s, pageBuilder: (c, a, b2) => b(c)),
            home: DefaultTextStyle(
              style: TfText.body().copyWith(color: TfColors.text),
              child: KeyedSubtree(key: ValueKey<int>(n), child: const MontageScreen()),
            ),
          ),
        );
    await t.pumpWidget(host(1));
    await _settle(t);
    expect(live, <int>{11});
    expect(t.widget<Texture>(find.byType(Texture)).textureId, 11);

    await t.pumpWidget(host(2));
    await _settle(t);
    expect(live, <int>{11}, reason: 'la textura sigue registrada tras sustituir');
    expect(t.widget<Texture>(find.byType(Texture)).textureId, 11);
    expect(channel.holders, 1);

    await t.pumpWidget(const SizedBox());
    expect(live, isEmpty);
    expect(channel.holders, 0);
  });

  testWidgets('sin tema: selector con los temas con tomas', (t) async {
    final MockCore core = _core();
    await _pump(t, core, select: false);
    expect(find.text('Elige un tema'), findsOneWidget);
    expect(find.text('Delta'), findsOneWidget);
    await t.tap(find.text('Delta'));
    await _settle(t);
    expect(_methods(core), contains('montage.open'));
  });

  testWidgets('sin tema: lista con dos temas (golden)', (t) async {
    await t.runAsync(loadTfFonts);
    setTestSurface(t, const Size(1440, 900));
    final ProviderContainer c = _container(_core(), twoSongs: true);
    await t.pumpWidget(_app(c));
    await _settle(t);
    expect(find.text('Tornado Of Souls'), findsOneWidget);
    expect(find.text('El roce de tu cuerpo'), findsOneWidget);
    // Orden de `entries` (como Biblioteca y MV:28), sin reordenar por título.
    expect(t.getTopLeft(find.text('Tornado Of Souls')).dy, lessThan(t.getTopLeft(find.text('El roce de tu cuerpo')).dy));
    await _golden(t, 'montage_screen_no_song');
  });

  testWidgets('sin temas con tomas: Ir a Grabar cambia a la sección Grabar', (t) async {
    await t.runAsync(loadTfFonts);
    setTestSurface(t, const Size(1440, 900));
    final ProviderContainer c = _container(_core(), empty: true);
    await t.pumpWidget(_app(c));
    await _settle(t);
    expect(find.textContaining('Aún no hay temas con tomas'), findsOneWidget);
    c.read(shellRouteProvider.notifier).select(ShellRoute.montage);
    await t.tap(find.text('Ir a Grabar'));
    await _settle(t);
    expect(c.read(shellRouteProvider), ShellRoute.record);
    expect(c.read(selectedProjectProvider), isNull);
  });

  testWidgets('listo: cabecera, columnas y exportar habilitado (golden)', (t) async {
    final MockCore core = _core();
    await _pump(t, core);
    expect(_methods(core), contains('montage.open'));
    expect(find.text('Montaje'), findsOneWidget);
    expect(find.byType(MontagePreviewColumn), findsOneWidget);
    await t.tap(find.text('Exportar vídeo'));
    await _settle(t);
    expect(_methods(core), contains('montage.startExport'));
    await _golden(t, 'montage_screen_listo');
  });

  testWidgets('cargando: spinner', (t) async {
    await t.runAsync(loadTfFonts);
    setTestSurface(t, const Size(1440, 900));
    final ProviderContainer c = _container(_core(), extra: <Override>[montageStoreProvider.overrideWith(_Loading.new)]);
    await t.pumpWidget(_app(c));
    await t.pump();
    expect(find.byType(TfSpinner), findsOneWidget);
  });

  testWidgets('error de carga: mensaje y reintento', (t) async {
    final MockCore core = _core(openError: const CoreError('x', 'Fallo al abrir'));
    await _pump(t, core);
    expect(find.text('Fallo al abrir'), findsOneWidget);
    await t.tap(find.text('Reintentar'));
    await _settle(t);
    expect(_methods(core).where((String m) => m == 'montage.open').length, greaterThanOrEqualTo(2));
  });

  testWidgets('sin tomas con vídeo: tarjeta (golden)', (t) async {
    await _pump(t, _core(open: _fx('open.no-takes.result')));
    expect(find.text('Aún no hay tomas con vídeo'), findsOneWidget);
    expect(find.byType(MontagePreviewColumn), findsNothing);
    await _golden(t, 'montage_screen_no_takes');
  });

  testWidgets('sin tomas con vídeo: Ir a Grabar cambia a Grabar y conserva el tema', (t) async {
    await t.runAsync(loadTfFonts);
    setTestSurface(t, const Size(1440, 900));
    final ProviderContainer c = _container(_core(open: _fx('open.no-takes.result')));
    c.read(selectedProjectProvider.notifier).select(_pid);
    c.read(shellRouteProvider.notifier).select(ShellRoute.montage);
    await t.pumpWidget(_app(c));
    await _settle(t);
    await t.tap(find.text('Ir a Grabar'));
    await _settle(t);
    expect(c.read(shellRouteProvider), ShellRoute.record);
    expect(c.read(selectedProjectProvider), _pid);
  });

  testWidgets('vista previa: «m:ss · sección» según la posición del tema', (t) async {
    final MockCore core = _core();
    await _pump(t, core);
    // Fixture: posición 2 s y sección «Estrofa» [0.5, 2): el borde final queda fuera (MV:116, t < end).
    expect(find.textContaining('Estrofa'), findsNothing);
    core.emit('montage.position', <String, Object?>{'seconds': 1.0, 'videoSeconds': 0.0, 'playing': false});
    await _settle(t);
    expect(find.text('0:01 · Estrofa'), findsOneWidget);
    core.emit('montage.position', <String, Object?>{'seconds': 2.0, 'videoSeconds': 0.0, 'playing': false});
    await _settle(t);
    expect(find.textContaining('Estrofa'), findsNothing);
  });

  testWidgets('compact (ancho < 900) (golden)', (t) async {
    await _pump(t, _core(), size: const Size(960, 900));
    expect(find.byType(MontagePreviewColumn), findsOneWidget);
    await _golden(t, 'montage_screen_compact');
  });

  testWidgets('vertical (golden)', (t) async {
    await _pump(t, _core(open: _fx('open.portrait.result')));
    expect(find.text('Vista previa · 1080 × 1920'), findsOneWidget);
    await _golden(t, 'montage_screen_vertical');
  });

  testWidgets('analizando: Exportar deshabilitado', (t) async {
    final MockCore core = _core(open: _fx('open.analyzing.result'));
    await _pump(t, core);
    await t.tap(find.text('Exportar vídeo'), warnIfMissed: false);
    await _settle(t);
    expect(_methods(core), isNot(contains('montage.startExport')));
  });

  testWidgets('exportando: banner y Cancelar (golden)', (t) async {
    final MockCore core = _core(open: _fx('open.exporting.result'));
    await _pump(t, core);
    expect(find.text('Exportar vídeo'), findsNothing);
    await t.tap(find.text('Cancelar exportación'));
    await _settle(t);
    expect(_methods(core), contains('montage.cancelExport'));
    await _golden(t, 'montage_screen_exporting');
  });

  testWidgets('exportado: banner con el resultado (golden)', (t) async {
    await _pump(t, _core(open: _fx('open.exported.result')));
    expect(find.textContaining('Vídeo exportado'), findsOneWidget);
    await _golden(t, 'montage_screen_exported');
  });

  testWidgets('fallo de exportación (golden)', (t) async {
    await _pump(t, _core(open: _fx('open.export-failed.result')));
    expect(find.textContaining('No se pudo exportar'), findsOneWidget);
    await _golden(t, 'montage_screen_export_failed');
  });

  testWidgets('aviso de audio del transporte', (t) async {
    final Json open = _ready();
    final Json transport = Map<String, Object?>.from(open['transport']! as Map)..['audioError'] = 'Sin salida de audio';
    await _pump(t, _core(open: <String, Object?>{...open, 'transport': transport}));
    expect(find.text('Sin salida de audio'), findsOneWidget);
  });

  testWidgets('cambiar el tema elegido reabre el montaje; null vuelve al selector', (t) async {
    const String other = '00000000-0000-0000-0000-000000000009';
    final MockCore core = _core();
    await t.runAsync(loadTfFonts);
    setTestSurface(t, const Size(1440, 900));
    final ProviderContainer c = _container(core);
    c.read(selectedProjectProvider.notifier).select(_pid);
    await t.pumpWidget(_app(c));
    await _settle(t);
    List<Object?> opens() => <Object?>[
          for (final MockCall m in core.calls)
            if (m.method == 'montage.open') (m.params as Map)['projectId'],
        ];
    expect(opens(), <Object?>[_pid]);
    c.read(selectedProjectProvider.notifier).select(_pid);
    await _settle(t);
    expect(opens(), <Object?>[_pid]);
    c.read(selectedProjectProvider.notifier).select(other);
    await _settle(t);
    expect(opens(), <Object?>[_pid, other]);
    c.read(selectedProjectProvider.notifier).select(null);
    await _settle(t);
    expect(find.text('Elige un tema'), findsOneWidget);
    expect(_methods(core), contains('montage.close'));
  });

  testWidgets('al salir se llama a montage.close', (t) async {
    final MockCore core = _core();
    await _pump(t, core);
    await t.pumpWidget(const SizedBox());
    await _settle(t);
    expect(_methods(core), contains('montage.close'));
  });
}
