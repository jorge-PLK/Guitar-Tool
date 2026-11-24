import 'ffi_bindings.dart';

/// Canales de fotogramas (`TF_CHANNEL_*` de tf_core.h).
enum FrameChannelId {
  camera(0),
  montage(1),
  take(2);

  const FrameChannelId(this.value);
  final int value;
}

/// Textura de un canal de fotogramas. El núcleo entrega los fotogramas al runner; Dart solo pinta `Texture(textureId)`.
/// Sin copia de píxeles. Llamar desde el hilo de plataforma (es el de UI).
class FrameChannel {
  FrameChannel(
    this.id, {
    required int Function(int channel) createTexture,
    required void Function(int channel) disposeTexture,
  })  : _create = createTexture,
        _dispose = disposeTexture;

  factory FrameChannel.ffi(FrameChannelId id, TfBindings b) => FrameChannel(id,
      createTexture: b.textureCreate, disposeTexture: b.textureDispose);

  final FrameChannelId id;
  final int Function(int) _create;
  final void Function(int) _dispose;
  int? _textureId;

  /// Id de la textura, o nulo si no está creada o no hay texturas.
  int? get textureId => _textureId;

  /// Registra la textura; devuelve su id o −1 (sin texturas). Idempotente mientras exista.
  int create() {
    final current = _textureId;
    if (current != null) return current;
    final t = _create(id.value);
    if (t >= 0) _textureId = t;
    return t;
  }

  void dispose() {
    if (_textureId == null) return;
    _textureId = null;
    _dispose(id.value);
  }
}
