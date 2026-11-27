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
  int _refs = 0;

  /// Id de la textura, o nulo si no está creada o no hay texturas.
  int? get textureId => _textureId;

  /// Propietarios actuales de la textura.
  int get holders => _refs;

  /// Toma una referencia: la primera registra la textura; las siguientes comparten el mismo id.
  /// Devuelve el id o −1 (sin texturas). Cada `acquire` se empareja con un único `release`.
  ///
  /// Con conteo, el orden «el State nuevo hace `acquire` antes de que el viejo haga `release`» (Flutter
  /// sustituye un elemento así) no da de baja la textura que el nuevo va a pintar.
  int acquire() {
    _refs++;
    final current = _textureId;
    if (current != null) return current;
    final t = _create(id.value);
    if (t >= 0) _textureId = t;
    return t;
  }

  /// Suelta una referencia; la textura se da de baja solo al soltar la última. Un `release` de más se ignora.
  void release() {
    if (_refs == 0) return;
    _refs--;
    if (_refs > 0 || _textureId == null) return;
    _textureId = null;
    _dispose(id.value);
  }
}
