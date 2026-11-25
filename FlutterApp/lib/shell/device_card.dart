import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/audio.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/widgets/tf_sidebar_cards.dart';

import 'shell_providers.dart';

/// Estado de la salida elegida (AudioDeviceMonitor.swift): `uid == null` = salida del sistema.
@immutable
class DeviceStatus {
  const DeviceStatus({this.uid, this.name, this.connected = false});

  final String? uid;
  final String? name;
  final bool connected;

  @override
  bool operator ==(Object other) =>
      other is DeviceStatus && other.uid == uid && other.name == name && other.connected == connected;

  @override
  int get hashCode => Object.hash(uid, name, connected);
}

/// Se deduce de `audio.settings` (`outputDeviceUID`) y `audio.devices` (`outputs`); se refresca con
/// `audio.devicesChanged`, `audio.state` y al cambiar de pantalla (el perfil se edita en Ajustes).
final deviceStatusProvider = NotifierProvider<DeviceStatusNotifier, DeviceStatus>(DeviceStatusNotifier.new);

class DeviceStatusNotifier extends Notifier<DeviceStatus> {
  String? _lastName;
  bool _alive = true;

  @override
  DeviceStatus build() {
    final core = ref.watch(coreClientProvider);
    _alive = true;
    final subs = <StreamSubscription<Object?>>[
      core.on('audio.devicesChanged', AudioDevices.fromJson).listen((_) => _refresh(), onError: _ignore),
      core.on('audio.state', AudioState.fromJson).listen((_) => _refresh(), onError: _ignore),
    ];
    ref.listen(shellRouteProvider, (_, _) => _refresh());
    ref.onDispose(() {
      _alive = false;
      for (final s in subs) {
        s.cancel();
      }
    });
    Future<void>.microtask(_refresh);
    return const DeviceStatus();
  }

  static void _ignore(Object _) {}

  Future<void> _refresh() async {
    final core = ref.read(coreClientProvider);
    try {
      final settings = await core.call('audio.settings', const <String, Object?>{}, AudioSettings.fromJson);
      final devices = await core.call('audio.devices', const <String, Object?>{}, AudioDevices.fromJson);
      if (!_alive) return;
      final uid = (settings.outputDeviceUID?.isEmpty ?? true) ? null : settings.outputDeviceUID;
      if (uid == null) {
        state = const DeviceStatus();
        return;
      }
      AudioDeviceItem? found;
      for (final d in devices.outputs) {
        if (d.uid == uid && d.connected) found = d;
      }
      if (found != null) _lastName = found.name;
      state = DeviceStatus(uid: uid, name: found?.name ?? _lastName, connected: found != null);
    } catch (_) {
      // Sin núcleo o sin respuesta: se conserva lo último visto.
    }
  }
}

/// Tarjeta de salida de la barra lateral (RootView.swift:92-103).
class DeviceCard extends ConsumerWidget {
  const DeviceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(deviceStatusProvider);
    final system = s.uid == null;
    return TfDeviceCard(
      title: system ? l.settings_audio_systemOutput : (s.name ?? l.settings_audio_chosenFallback),
      subtitle: system
          ? l.shell_deviceDefault
          : (s.connected ? l.shell_deviceConnected : l.shell_deviceNotConnected),
      connected: system || s.connected, // punto verde también con la salida del sistema (RootView.swift:95)
      titleMaxLines: 2, // RootView.swift:96: Text sin lineLimit (envuelve)
    );
  }
}
