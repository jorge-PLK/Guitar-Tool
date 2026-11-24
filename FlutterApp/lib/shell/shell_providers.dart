import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/core/core_providers.dart';

import 'shell_route.dart';

/// Ruta actual; la inicial sale de `--screen`.
final shellRouteProvider = NotifierProvider<ShellRouteNotifier, ShellRoute>(ShellRouteNotifier.new);

class ShellRouteNotifier extends Notifier<ShellRoute> {
  @override
  ShellRoute build() => ShellRoute.fromScreen(ref.read(launchOptionsProvider).screen);

  void select(ShellRoute route) => state = route;
}

/// Pestaña de Ajustes; la inicial sale de `--screen settings-*`.
final settingsTabProvider = NotifierProvider<SettingsTabNotifier, SettingsTab>(SettingsTabNotifier.new);

class SettingsTabNotifier extends Notifier<SettingsTab> {
  @override
  SettingsTab build() => SettingsTab.fromScreen(ref.read(launchOptionsProvider).screen);

  void select(SettingsTab tab) => state = tab;
}

/// Una llamada barata (`app.info`) al arrancar: arranca el núcleo y deja traza de que responde.
final coreProbeProvider = FutureProvider<void>((ref) async {
  final core = ref.watch(coreClientProvider);
  final info = await core.call<Map<String, Object?>>('app.info', const <String, Object?>{}, (j) => j);
  debugPrint('tf: app.info ok (${info.length} campos)');
});

/// Tope total del cierre del núcleo antes de salir.
const Duration coreShutdownLimit = Duration(seconds: 6);

/// Cierra el núcleo (espera `core.shutdown`, con tope) y sale del proceso. Los tests lo sustituyen.
final appExitProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final core = ref.read(coreClientProvider);
    Map<String, Object?>? event;
    final sub = core.on<Map<String, Object?>>('core.shutdown', (j) => j).listen((j) => event = j);
    try {
      await core.shutdown().timeout(coreShutdownLimit);
    } catch (e) {
      debugPrint('tf: cierre del núcleo sin confirmar: $e');
    }
    await sub.cancel();
    debugPrint('tf: core.shutdown clean=${event?['clean']}');
    exit(0);
  };
});
