import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/core/core_providers.dart';

/// Mapa de teclas de edición del núcleo (`tab.keyMap {}`): estático, se pide una vez y se cachea.
final tabKeyMapProvider = FutureProvider<TabKeyMapResult>(
  (ref) => ref.read(coreClientProvider).call(
        'tab.keyMap',
        const <String, Object?>{},
        TabKeyMapResult.fromJson,
      ),
);

/// ¿Reclama el núcleo esta tecla? `key` exacta; `ctrl`/`alt` iguales; `shift` igual salvo `null`.
/// [hasRange] = hay rango local (`tabStore.range`), que cuenta como tramo.
bool claims(
  TabKeyMapResult map, {
  required String key,
  required bool shift,
  required bool ctrl,
  required bool alt,
  required TabState tab,
  required bool hasRange,
}) {
  final bool ready = tab.phase == TabPhase.ready;
  final bool edit = ready && tab.editMode;
  TabTrackKind? kind;
  for (final t in tab.tracks) {
    if (t.id == tab.selectedTrack) kind = t.kind;
  }
  final bool drums = kind == TabTrackKind.drums;
  for (final r in map.rules) {
    if (r.key != key || r.ctrl != ctrl || r.alt != alt) continue;
    if (r.shift != null && r.shift != shift) continue;
    final bool applies = switch (r.when) {
      TabKeyWhen.span => ready && (tab.span != null || hasRange),
      TabKeyWhen.edit => edit,
      TabKeyWhen.editDrums => edit && drums,
      TabKeyWhen.editNotDrums => edit && !drums,
      TabKeyWhen.unknown => false,
    };
    if (applies) return true;
  }
  return false;
}
