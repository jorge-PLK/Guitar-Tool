import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/library.dart';
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

class _Loading extends MontageStore {
  @override
  MontageState build() => const MontageState(projectId: _pid, loading: true);
}

ProviderContainer _container(MockCore core, {List<Override> extra = const <Override>[]}) {
  final ProviderContainer c = ProviderContainer(overrides: [
    ...extra,
    coreClientProvider.overrideWithValue(core),
    libraryStoreProvider.overrideWith(_FakeLibrary.new),
    frameChannelProvider(FrameChannelId.montage).overrideWithValue(null),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<void> _golden(WidgetTester t, String name) =>
    expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('goldens/$name.png'));

List<String> _methods(MockCore c) => <String>[for (final MockCall m in c.calls) m.method];

void main() {
  testWidgets('sin tema: selector con los temas con tomas', (t) async {
    final MockCore core = _core();
    await _pump(t, core, select: false);
    expect(find.text('Elige un tema'), findsOneWidget);
    expect(find.text('Delta'), findsOneWidget);
    await t.tap(find.text('Delta'));
    await _settle(t);
    expect(_methods(core), contains('montage.open'));
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

  testWidgets('al salir se llama a montage.close', (t) async {
    final MockCore core = _core();
    await _pump(t, core);
    await t.pumpWidget(const SizedBox());
    await _settle(t);
    expect(_methods(core), contains('montage.close'));
  });
}
