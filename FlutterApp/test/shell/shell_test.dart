import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/app.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/features/backing/backing_screen.dart';
import 'package:toneforge/features/library/library_screen.dart';
import 'package:toneforge/features/montage/montage_screen.dart';
import 'package:toneforge/features/record/record_screen.dart';
import 'package:toneforge/features/settings/settings_audio_tab.dart';
import 'package:toneforge/features/settings/settings_library_tab.dart';
import 'package:toneforge/features/settings/settings_screen.dart';
import 'package:toneforge/features/settings/settings_video_tab.dart';
import 'package:toneforge/features/tab/tab_screen.dart';
import 'package:toneforge/shell/shell_providers.dart';
import 'package:toneforge/shell/shell_route.dart';
import 'package:toneforge/shell/snapshot.dart';

import '../support/shell_harness.dart';

const _mock = LaunchOptions(mock: true, locale: 'es');

void main() {
  group('shell navegación', () {
    testWidgets('las 6 rutas se alcanzan desde la barra lateral', (tester) async {
      final c = await pumpShell(tester);
      expect(find.byType(LibraryScreen), findsOneWidget);
      final steps = <(String, Type, ShellRoute)>[
        ('Backing track', BackingScreen, ShellRoute.backing),
        ('Tablatura', TabScreen, ShellRoute.tab),
        ('Grabar', RecordScreen, ShellRoute.record),
        ('Montaje', MontageScreen, ShellRoute.montage),
        ('Ajustes', SettingsScreen, ShellRoute.settings),
        ('Biblioteca', LibraryScreen, ShellRoute.library),
      ];
      for (final (label, screen, route) in steps) {
        await tester.tap(find.text(label).first);
        await tester.pump();
        expect(c.read(shellRouteProvider), route, reason: label);
        expect(find.byType(screen), findsOneWidget, reason: label);
      }
    });

    testWidgets('--screen elige la ruta inicial', (tester) async {
      final c = await pumpShell(tester, options: const LaunchOptions(mock: true, locale: 'es', screen: 'montage'));
      expect(c.read(shellRouteProvider), ShellRoute.montage);
      expect(find.byType(MontageScreen), findsOneWidget);
    });

    testWidgets('--screen settings-video abre Ajustes en Cámara y vídeo', (tester) async {
      await pumpShell(tester, options: const LaunchOptions(mock: true, locale: 'es', screen: 'settings-video'));
      expect(find.byType(SettingsVideoTab), findsOneWidget);
    });

    testWidgets('--locale en traduce la barra lateral', (tester) async {
      await pumpShell(tester, options: const LaunchOptions(mock: true, locale: 'en'));
      expect(find.text('Library'), findsWidgets);
      expect(find.text('Biblioteca'), findsNothing);
    });
  });

  group('shell ajustes', () {
    testWidgets('cambia de pestaña', (tester) async {
      final c = await pumpShell(tester, options: const LaunchOptions(mock: true, locale: 'es', screen: 'settings'));
      expect(find.byType(SettingsAudioTab), findsOneWidget);
      await tester.tap(find.text('Cámara y vídeo'));
      await tester.pump();
      expect(find.byType(SettingsVideoTab), findsOneWidget);
      expect(c.read(settingsTabProvider), SettingsTab.video);
      await tester.tap(find.text('Biblioteca').last);
      await tester.pump();
      expect(find.byType(SettingsLibraryTab), findsOneWidget);
    });
  });

  group('shell snapshot', () {
    testWidgets('escribe un PNG válido al tamaño lógico y sale', (tester) async {
      final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('tf_shell_')))!;
      addTearDown(() => dir.delete(recursive: true));
      final out = '${dir.path}/shell.png';
      var exited = false;
      await pumpShell(
        tester,
        options: LaunchOptions(mock: true, locale: 'es', snapshot: out, snapshotDelay: 0),
        onExit: () => exited = true,
      );
      for (var i = 0; i < 100 && !exited; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(exited, isTrue);
      final bytes = (await tester.runAsync(() => File(out).readAsBytes()))!;
      expect(bytes.sublist(1, 4), 'PNG'.codeUnits);
      final image = (await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(bytes);
        return (await codec.getNextFrame()).image;
      }))!;
      expect((image.width, image.height), (1440, 900));
    });

    testWidgets('writeBoundaryPng vuelca el límite a PNG', (tester) async {
      await pumpShell(tester, options: _mock);
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
      final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('tf_shell_')))!;
      addTearDown(() => dir.delete(recursive: true));
      await tester.runAsync(() => writeBoundaryPng(boundary, 1, '${dir.path}/a.png'));
      expect(File('${dir.path}/a.png').lengthSync(), greaterThan(100));
    });
  });

  group('shell goldens', () {
    testWidgets('Biblioteca', (tester) async {
      await pumpShell(tester);
      await expectLater(find.byType(ToneForgeApp), matchesGoldenFile('goldens/shell_library.png'));
    });

    testWidgets('Ajustes', (tester) async {
      await pumpShell(tester, options: const LaunchOptions(mock: true, locale: 'es', screen: 'settings'));
      await expectLater(find.byType(ToneForgeApp), matchesGoldenFile('goldens/shell_settings.png'));
    });
  });
}
