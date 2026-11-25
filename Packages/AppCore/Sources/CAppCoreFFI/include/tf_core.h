#ifndef TF_CORE_H
#define TF_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// ABI de AppCoreFFI, congelada al cerrar P9 (docs/flutter/arquitectura.md, «AppCoreFFI (Swift)»).
// Cambiar una firma, añadir o quitar una función es una pregunta a Jorge.

/// Exportación de símbolos. En Windows la biblioteca (AppCoreFFI.dll) se construye con este código C enlazado
/// dentro, y Swift también importa esta cabecera: por eso es SIEMPRE dllexport (con dllimport Swift generaría
/// llamadas por la tabla de importación a símbolos que están en la misma DLL y fallaría el enlace). Quien carga
/// la DLL (Dart FFI, runner por LoadLibrary/GetProcAddress) no incluye esta cabecera.
#ifdef _WIN32
#define TF_API __declspec(dllexport)
#define TF_INTERNAL
#else
#define TF_API __attribute__((visibility("default")))
#define TF_INTERNAL __attribute__((visibility("hidden")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/// Inicializa la API DL de Dart (= Dart_InitializeApiDL(data)); 0 = ok. Dart, una vez, antes de `tf_core_start`.
TF_API intptr_t tf_core_init_dart_api(void *data);

/// `optionsJSON` = {"args":["--projects-folder","...", ...]}. El sumidero es el puerto nativo de Dart: cada mensaje
/// se envía como kExternalTypedData (Uint8) sin copia y Dart libera el búfer con `tf_core_free`.
/// 0 ok; 1 ya arrancado; 2 opciones inválidas; 3 falló Bridge.init.
TF_API int32_t tf_core_start(const char *optionsJSON, int64_t port);

/// Entrega {id, method, params} o {hostResponse} a Bridge.receive. Copia los bytes antes de volver; no bloquea.
TF_API void tf_core_send(const uint8_t *utf8, int32_t len);

/// Libera un búfer entregado por el puerto (finalizador del Uint8List externo).
TF_API void tf_core_free(const uint8_t *ptr);

/// Asíncrono: vuelve enseguida y emite {"event":"core.shutdown","payload":{"clean":bool}} al acabar el cierre
/// o al vencer el tope (que cubre el cierre entero).
TF_API void tf_core_shutdown(int32_t timeoutMs);

/// Windows, hilo principal del runner: sirve `DispatchQueue.main` / `@MainActor`; no vuelve. En Mac no hace nada.
TF_API void tf_core_run_main(void);

// ---- Fotogramas ----

#define TF_CHANNEL_CAMERA 0   // Grabar y vista previa de Ajustes · Vídeo
#define TF_CHANNEL_MONTAGE 1  // vista previa de Montaje
#define TF_CHANNEL_TAKE 2     // vídeo de la toma (Ver toma), reproductor nativo (Mac; en Windows `tf_frame_copy` da nulo por ahora)

/// Tabla que da el runner. `register_texture` y `unregister_texture`, desde el hilo de plataforma; `frame_available`,
/// desde cualquier hilo (el runner reencola si hace falta).
typedef struct {
  int64_t (*register_texture)(int32_t channel);
  void (*frame_available)(int64_t id);
  void (*unregister_texture)(int64_t id);
} tf_texture_host;

/// Nulo = sin texturas. El runner, antes de que arranque Dart.
TF_API void tf_core_set_texture_host(const tf_texture_host *host);
/// host->register_texture; -1 si no hay host. Desde el hilo de plataforma.
TF_API int64_t tf_texture_create(int32_t channel);
/// unregister_texture y, en Windows, libera las texturas D3D11 del canal.
TF_API void tf_texture_dispose(int32_t channel);
/// Mac: CVPixelBufferRef retenido (+1) del último fotograma o NULL. Windows: HANDLE DXGI compartido de la última
/// textura publicada o NULL. Cualquier hilo.
TF_API void *tf_frame_copy(int32_t channel);

// ---- Internos (no forman parte de la ABI: ocultos en Mac, sin dllexport en Windows) ----

/// Envía un búfer malloc por el puerto como kExternalTypedData.
/// false si el puerto no acepta (el llamante conserva la propiedad y lo libera).
TF_INTERNAL bool tf_post_external(int64_t port, uint8_t *ptr, intptr_t len);

#ifdef _WIN32
/// Windows, tf_d3d.c: textura D3D11 B8G8R8A8 compartida por canal (handle clásico de IDXGIResource::GetSharedHandle,
/// el que pide kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle). Sube un fotograma BGRA compacto (la recrea si cambia
/// el tamaño). 0 bien.
TF_INTERNAL int32_t tf_d3d_upload(int32_t channel, const uint8_t *bgra, int32_t width, int32_t height);
/// HANDLE compartido de la última textura publicada del canal, o NULL.
TF_INTERNAL void *tf_d3d_handle(int32_t channel);
/// Libera la textura del canal.
TF_INTERNAL void tf_d3d_release(int32_t channel);
#endif

#ifdef __cplusplus
}
#endif

#endif
