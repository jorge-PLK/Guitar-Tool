import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/app.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/backing/backing_screen.dart';
import 'package:toneforge/features/library/library_screen.dart';
import 'package:toneforge/features/library/library_store.dart';
import 'package:toneforge/features/montage/montage_screen.dart';
import 'package:toneforge/features/record/record_screen.dart';
import 'package:toneforge/features/settings/settings_audio_tab.dart';
import 'package:toneforge/features/settings/settings_library_tab.dart';
import 'package:toneforge/features/settings/settings_screen.dart';
import 'package:toneforge/features/settings/settings_video_tab.dart';
import 'package:toneforge/features/tab/tab_screen.dart';
import 'package:toneforge/shell/library_detail.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/shell/shell_providers.dart';
import 'package:toneforge/shell/shell_route.dart';
import 'package:toneforge/shell/snapshot.dart';
import 'package:toneforge/widgets/tf_sidebar_cards.dart';

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

  group('shell soltar ficheros', () {
    Future<void> send(WidgetTester tester, String method, Object? args) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'desktop_drop',
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );
      await tester.pump();
    }

    testWidgets('soltar en cualquier sección importa solo wav/flac/mp3', (tester) async {
      final c = await pumpShell(tester, options: const LaunchOptions(mock: true, locale: 'es', screen: 'settings'));
      await send(tester, 'entered', <double>[700, 400]);
      await send(tester, 'performOperation', <String>['/x/a.wav', '/x/b.txt', '/x/c.mp3']);
      final core = c.read(coreClientProvider) as MockCore;
      final paths = [
        for (final call in core.calls)
          if (call.method == 'import.file') (call.params as Map)['path'],
      ];
      expect(paths, <Object?>['/x/a.wav', '/x/c.mp3']);
    });
  });

  group('shell tarjeta del tema seleccionado', () {
    Future<ProjectSummary> firstEntry(WidgetTester tester, ProviderContainer c) async {
      c.read(libraryStoreProvider);
      for (var i = 0; i < 40 && c.read(libraryStoreProvider).entries.isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
        await tester.pump();
      }
      return c.read(libraryStoreProvider).entries.first;
    }

    testWidgets('oculta sin selección, visible y activa según el detalle', (tester) async {
      final c = await pumpShell(tester);
      final e = await firstEntry(tester, c);
      expect(find.byType(TfSelectedTrackCard), findsNothing);

      c.read(selectedProjectProvider.notifier).select(e.id);
      await tester.pump();
      expect(find.byType(TfSelectedTrackCard), findsOneWidget);
      expect(tester.widget<TfSelectedTrackCard>(find.byType(TfSelectedTrackCard)).active, isFalse);

      await tester.tap(find.byType(TfSelectedTrackCard));
      await tester.pump();
      expect(c.read(libraryDetailProvider), e.id);
      expect(c.read(shellRouteProvider), ShellRoute.library);
      expect(tester.widget<TfSelectedTrackCard>(find.byType(TfSelectedTrackCard)).active, isTrue);

      await tester.tap(find.text('Biblioteca').first);
      await tester.pump();
      expect(c.read(libraryDetailProvider), isNull);
      expect(tester.widget<TfSelectedTrackCard>(find.byType(TfSelectedTrackCard)).active, isFalse);
    });

    testWidgets('pulsarla desde otra sección abre el detalle en Biblioteca', (tester) async {
      final c = await pumpShell(tester, options: const LaunchOptions(mock: true, locale: 'es', screen: 'montage'));
      final e = await firstEntry(tester, c);
      c.read(selectedProjectProvider.notifier).select(e.id);
      await tester.pump();
      await tester.tap(find.byType(TfSelectedTrackCard));
      await tester.pump();
      expect(c.read(shellRouteProvider), ShellRoute.library);
      expect(c.read(libraryDetailProvider), e.id);
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
