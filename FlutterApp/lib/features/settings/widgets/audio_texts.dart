import 'package:flutter/foundation.dart' show listEquals;
import 'package:intl/intl.dart';
import 'package:toneforge/contract/audio.dart';
import 'package:toneforge/contract/core_message.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/widgets/tf_dropdown.dart';

/// `audio-block-no-input-device` -> `noInputDevice`.
String blockSuffix(String code) {
  const String prefix = 'audio-block-';
  final String raw = code.startsWith(prefix) ? code.substring(prefix.length) : code;
  final List<String> parts = raw.split('-');
  return parts.first +
      parts.skip(1).map((String p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1)).join();
}

double? _num(Object? v) => v is num ? v.toDouble() : null;

/// Motivo por el que «Calibrar» está bloqueado, traducido por código; si el código no se conoce
/// (o falta un argumento) cae al `message` del núcleo, y sin mensaje con código usa [fallback].
String? calibrateBlockText(AppLocalizations l, CoreMessage? m, {String? fallback}) {
  if (m == null) return fallback;
  final Map<String, Object?> a = m.args;
  switch (blockSuffix(m.code)) {
    case 'busy':
      return l.settings_audio_block_busy;
    case 'invalidChannels':
      return l.settings_audio_block_invalidChannels;
    case 'inputDisconnected':
      return l.settings_audio_block_inputDisconnected;
    case 'loop':
      return l.settings_audio_block_loop;
    case 'noGuitarInput':
      return l.settings_audio_block_noGuitarInput;
    case 'noInputDevice':
      return l.settings_audio_block_noInputDevice;
    case 'outputDisconnected':
      return l.settings_audio_block_outputDisconnected;
    case 'rateMismatch':
      final double? d = _num(a['deviceHz']);
      final double? w = _num(a['workingHz']);
      if (d == null || w == null) return m.message;
      return l.settings_audio_block_rateMismatch(d / 1000, w / 1000);
    case 'sessionUnavailable':
      return l.settings_audio_block_sessionUnavailable(a['detail'] as String? ?? m.message);
    case 'speed':
      return l.settings_audio_block_speed(_num(a['rate']) ?? 1);
  }
  return m.message;
}

String deviceLabel(AppLocalizations l, AudioDeviceItem d) => d.connected
    ? l.settings_audio_deviceOption(d.name, d.channels)
    : l.settings_audio_deviceDisconnected(d.name);

/// Opciones de un selector de dispositivo: `null` primero (sistema / ninguna) y, si el elegido ya
/// no está en la lista, su entrada «Dispositivo elegido · desconectado».
List<TfDropdownItem<String?>> deviceItems(
  AppLocalizations l,
  List<AudioDeviceItem> devices,
  String? chosen, {
  required String nullLabel,
}) =>
    <TfDropdownItem<String?>>[
      TfDropdownItem<String?>(value: null, label: nullLabel),
      for (final AudioDeviceItem d in devices)
        TfDropdownItem<String?>(value: d.uid, label: deviceLabel(l, d)),
      if (chosen != null && !devices.any((AudioDeviceItem d) => d.uid == chosen))
        TfDropdownItem<String?>(
          value: chosen,
          label: l.settings_audio_deviceDisconnected(l.settings_audio_chosenFallback),
        ),
    ];

String backingLabel(AppLocalizations l, AudioBacking b) =>
    l.settings_audio_backingChoice('${b.left}', '${b.right}');

String guitarLabel(AppLocalizations l, AudioGuitarChoice g) {
  final List<int>? c = g.channels;
  if (c == null || c.isEmpty) return g.label;
  if (c.length == 1) return l.settings_audio_inputN(c[0]);
  return l.settings_audio_inputsNM(c[0], c[1]);
}

int guitarIndex(AudioSettings s) {
  final int i = s.guitarChoices
      .indexWhere((AudioGuitarChoice g) => g.channels != null && listEquals(g.channels, s.guitarIn));
  // Sin «Sin asignar» (M-7): si el valor no está en las opciones, se muestra la primera.
  return i >= 0 || s.guitarChoices.isEmpty ? i : 0;
}

int backingIndex(AudioSettings s) => s.backingChoices
    .indexWhere((AudioBacking b) => b.left == s.backingOut.left && b.right == s.backingOut.right);

/// Etiqueta de [rate] según la lista de frecuencias permitidas (la compone el núcleo), o null.
String? rateLabel(AudioSettings s, double rate) {
  for (final AudioSampleRate r in s.allowedSampleRates) {
    if (r.rate.round() == rate.round()) return r.label;
  }
  return null;
}

/// «Calibrada · 2,05 ms · 3 feb 2026». Sin fecha o sin formato de fecha cargado, usa el ISO.
String calibratedText(AppLocalizations l, AudioCalibrationSummary c) {
  final double ms = ((c.latencyMS ?? 0) * 100).round() / 100;
  final String raw = c.date ?? '';
  String date = raw.length >= 10 ? raw.substring(0, 10) : raw;
  final DateTime? t = DateTime.tryParse(raw);
  if (t != null) {
    try {
      date = DateFormat.yMMMd(l.localeName).format(t.toLocal());
    } on Object {
      // Sin datos de fecha del idioma: se queda el ISO.
    }
  }
  return l.settings_audio_calibrated(ms, date);
}
