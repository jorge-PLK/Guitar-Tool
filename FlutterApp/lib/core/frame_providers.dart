import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core_providers.dart';
import 'ffi_bindings.dart';
import 'frame_channel.dart';

/// Canal de fotogramas por id. Con el núcleo real es `FrameChannel.ffi(id, bindings)`; con `--mock`
/// (y sin sobrescribir en tests) es nulo y `TfVideoSurface` pinta el marcador.
///
/// No es `autoDispose`: el ciclo `create()`/`dispose()` de la textura es de cada store (idempotente),
/// y mantener una sola instancia por canal evita dos registros de textura sobre el mismo canal
/// (Grabar y Ajustes · Vídeo comparten `camera`). Los tests lo sobrescriben con un `FrameChannel` falso.
final frameChannelProvider = Provider.family<FrameChannel?, FrameChannelId>((ref, id) {
  if (ref.watch(launchOptionsProvider).mock) return null;
  return FrameChannel.ffi(id, TfBindings.open(coreLib: ref.watch(launchOptionsProvider).coreLib));
});
