import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart' show Json;
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/record/record_screen.dart';
import 'package:toneforge/features/record/widgets/parts_panel.dart';
import 'package:toneforge/features/record/widgets/punch_timeline.dart';
import 'package:toneforge/features/record/widgets/record_bar.dart';
import 'package:toneforge/features/record/widgets/record_header.dart';
import 'package:toneforge/features/record/widgets/record_mixer.dart';
import 'package:toneforge/features/record/widgets/record_preview.dart';
import 'package:toneforge/features/record/widgets/status_lines.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/shell/shell_providers.dart';
import 'package:toneforge/shell/shell_route.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_progress.dart';

import '../../support/harness.dart';

const String _done = '00000000-0000-0000-0000-000000000005';
const String _none = '00000000-0000-0000-0000-000000000001';

Json _fx(String path) =>
    (json.decode(File('../Contract/fixtures/$path.json').readAsStringSync()) as Map).cast<String, Object?>();

MockCore _core({Object? list, String open = 'record/record.open.result'}) {
  final MockCore core = MockCore()
    ..result('library.list', list ?? _fx('library/library.list.result'))
    ..result('study.open', <String, Object?>{})
    ..result('study.close', <String, Object?>{})
    ..result('audio.settings', _fx('audio/audio.settings.result'))
    ..result('audio.setMeters', _fx('audio/audio.setMeters.result'))
    ..result('record.close', <String, Object?>{});
  core.result('record.open', _fx(open));
  return core;
}

final ValueNotifier<bool> _shown = ValueNotifier<bool>(true);

Widget _app(MockCore core) => ProviderScope(
      overrides: [coreClientProvider.overrideWithValue(core)],
      child: tfNavApp(
        Localizations(
          locale: const Locale('es'),
          delegates: const <LocalizationsDelegate<dynamic>>[AppLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
          child: DefaultTextStyle(
            style: TfText.body().copyWith(color: TfColors.text),
            child: ValueListenableBuilder<bool>(
              valueListenable: _shown,
              builder: (BuildContext _, bool on, Widget? _) => on ? const RecordScreen() : const SizedBox(),
            ),
          ),
        ),
      ),
    );

ProviderContainer _c(WidgetTester t) => ProviderScope.containerOf(t.element(find.byType(RecordScreen)));

Future<void> _settle(WidgetTester t) async {
  for (int i = 0; i < 6; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await t.pump();
  }
}

Future<void> _pump(WidgetTester t, MockCore core, {String? project, Size size = const Size(1440, 900)}) async {
  await t.runAsync(loadTfFonts);
  setTestSurface(t, size);
  await t.pumpWidget(_app(core));
  await _settle(t);
  if (project != null) {
    _c(t).read(selectedProjectProvider.notifier).select(project);
    await _settle(t);
  }
}

List<String> _methods(MockCore c) => <String>[for (final MockCall m in c.calls) m.method];

void main() {
  setUp(() => _shown.value = true);
  testWidgets('sin proyecto: selector con los temas separados', (t) async {
    final MockCore core = _core();
    await _pump(t, core);
    expect(find.text('Grabar'), findsOneWidget);
    expect(find.text('Elige un tema'), findsOneWidget);
    expect(find.textContaining('Aún no hay temas'), findsNothing);
    expect(find.text('Alfa'), findsNothing);
    final Finder row = find.byType(GestureDetector);
    expect(row, findsOneWidget);
    await t.tap(row);
    await _settle(t);
    expect(_c(t).read(selectedProjectProvider), _done);
    expect(_methods(core), contains('record.open'));
  });

  testWidgets('sin proyecto y sin temas separados: mensaje vacío', (t) async {
    await _pump(t, _core(list: <String, Object?>{'projects': <Object?>[], 'skipped': <Object?>[]}));
    expect(find.textContaining('Aún no hay temas separados'), findsOneWidget);
    expect(find.text('Elige un tema'), findsNothing);
  });

  testWidgets('cargando tema: TfSpinner hasta que record.open responde', (t) async {
    final MockCore core = _core();
    await t.runAsync(loadTfFonts);
    setTestSurface(t, const Size(1440, 900));
    await t.pumpWidget(_app(core));
    expect(find.byType(TfSpinner), findsOneWidget);
    await _settle(t);
    _c(t).read(selectedProjectProvider.notifier).select(_done);
    await _settle(t);
    expect(find.byType(RecordHeader), findsOneWidget);
  });

  testWidgets('tema sin separar: tarjeta con aviso y botón a Biblioteca', (t) async {
    final MockCore core = _core();
    await _pump(t, core, project: _none);
    expect(find.text('Este tema aún no está separado'), findsOneWidget);
    expect(_methods(core), isNot(contains('record.open')));
    await t.tap(find.text('Ir a la biblioteca'));
    await t.pump();
    expect(_c(t).read(shellRouteProvider), ShellRoute.library);
  });

  testWidgets('preparado: cuerpo con todas las piezas y sin línea de punch', (t) async {
    final MockCore core = _core();
    await _pump(t, core, project: _done);
    for (final Type type in <Type>[
      RecordHeader,
      RecordPreview,
      RecordBar,
      RecordStatusLines,
      RecordMixer,
      PartsPanel,
    ]) {
      expect(find.byType(type), findsOneWidget, reason: '$type');
    }
    expect(find.byType(PunchTimeline), findsNothing);
    expect(find.textContaining('Multitoma'), findsOneWidget);
    expect(core.calls.firstWhere((MockCall m) => m.method == 'record.open').params, {'projectId': _done});
  });

  testWidgets('punch armado: aparece PunchTimeline', (t) async {
    await _pump(t, _core(open: 'record/record.state.punch-armed-marks.event'), project: _done);
    expect(find.byType(PunchTimeline), findsOneWidget);
  });

  testWidgets('mezclador expandido encoge la vista previa', (t) async {
    await _pump(t, _core(), project: _done, size: const Size(1100, 900));
    final double before = t.getSize(find.byType(RecordPreview)).height;
    await t.tap(find.text('Expandir'));
    await t.pump();
    expect(t.getSize(find.byType(RecordPreview)).height, lessThan(before));
  });

  testWidgets('salir cierra Grabar y el estudio', (t) async {
    final MockCore core = _core();
    await _pump(t, core, project: _done);
    _shown.value = false;
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(_methods(core), containsAllInOrder(<String>['record.close', 'study.close']));
  });

  testWidgets('Ir al montaje: cierra sin study.close y navega', (t) async {
    final MockCore core = _core();
    await _pump(t, core, project: _done);
    await t.tap(find.text('Ir al montaje'));
    await _settle(t);
    expect(_methods(core), contains('record.close'));
    expect(_methods(core), isNot(contains('study.close')));
    expect(_c(t).read(shellRouteProvider), ShellRoute.montage);
  });
}
