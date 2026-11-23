#ifndef TF_CORE_H
#define TF_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/// Exportación de símbolos. En Windows la biblioteca (AppCoreFFI.dll) se construye con este código C enlazado
/// dentro, y Swift también importa esta cabecera: por eso es SIEMPRE dllexport (con dllimport Swift generaría
/// llamadas por la tabla de importación a símbolos que están en la misma DLL y fallaría el enlace). Quien carga
/// la DLL (Dart FFI, runner por LoadLibrary/GetProcAddress) no incluye esta cabecera.
#ifdef _WIN32
#define TF_API __declspec(dllexport)
#else
#define TF_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/// Mensaje del núcleo (UTF-8, sin terminador). El búfer es del núcleo hasta `tf_core_free(utf8)`.
/// Se invoca desde cualquier hilo.
typedef void (*tf_message_cb)(const uint8_t *utf8, int32_t len);

/// `optionsJSON` = {"args":["--projects-folder","...", ...]}. `textures` se ignora (nulo) en esta parte.
/// 0 ok; 1 ya arrancado; 2 opciones inválidas; 3 falló Bridge.init.
TF_API int32_t tf_core_start(const char *optionsJSON, tf_message_cb onMessage, const void *textures);

/// Entrega {id, method, params} a Bridge.receive. Copia los bytes antes de volver; no bloquea.
TF_API void tf_core_send(const uint8_t *utf8, int32_t len);

/// Libera un búfer entregado por callback.
TF_API void tf_core_free(const uint8_t *ptr);

/// Asíncrono: vuelve enseguida y emite {"event":"core.shutdown","payload":{"clean":bool}}.
TF_API void tf_core_shutdown(int32_t timeoutMs);

/// Solo prueba: búferes entregados y aún no liberados.
TF_API int64_t tf_debug_live_buffers(void);

/// Inicializa la API DL de Dart (= Dart_InitializeApiDL(data)); 0 = ok. Llamar antes de `tf_core_start_port`.
TF_API intptr_t tf_core_init_dart_api(void *data);

/// Como `tf_core_start`, pero el sumidero es un puerto nativo de Dart: cada mensaje se envía como
/// kExternalTypedData (Uint8) sin copia; Dart libera el búfer con el finalizador (tf_core_free).
TF_API int32_t tf_core_start_port(const char *optionsJSON, int64_t port);

/// Solo prueba: reloj monótono en ns.
TF_API int64_t tf_debug_now_ns(void);

/// Solo prueba: emisor sintético por el sumidero activo. hz <= 0 = ráfaga. 0 lanzado; 1 no arrancado; 2 ya en curso.
TF_API int32_t tf_debug_emit(int32_t hz, int32_t count, int32_t bytes);

/// Interno (usado desde Swift): envía un búfer malloc por el puerto como kExternalTypedData.
/// false si el puerto no acepta (el llamante conserva la propiedad y lo libera).
TF_API bool tf_post_external(int64_t port, uint8_t *ptr, intptr_t len);

/// Interno: guarda el id del hilo que llama como "hilo principal" (Windows; en otras plataformas no hace nada).
TF_API void tf_internal_mark_main_thread(void);

// ---- P9 prueba 7 (Fase 7f): hilos en Windows ----

/// Vía 1: llama a dispatchMain(); no vuelve. Solo desde el hilo principal del proceso.
TF_API void tf_core_run_main(void);

/// Vía 2: Windows = HANDLE de _dispatch_get_main_queue_handle_4CF(); otras plataformas = NULL.
TF_API void *tf_core_main_queue_handle(void);

/// Vía 2: Windows = _dispatch_main_queue_callback_4CF(NULL) (drena la cola principal de Swift); otras = no-op.
TF_API void tf_core_pump(void);

/// Solo prueba: lanza Task { @MainActor } y DispatchQueue.main.async y espera en un hilo aparte. Emite
/// {"event":"probe.mainactor","payload":{"mainActor":bool,"dispatchMain":bool,"ms":N}}. 0 lanzada; 1 núcleo sin arrancar.
TF_API int32_t tf_debug_mainactor_selftest(int32_t timeoutMs);

/// Solo prueba: Windows = CoGetApartmentType del hilo que llama (0 STA, 1 MTA, 2 NA, 3 MAINSTA, -1 sin COM); otras = -2.
TF_API int32_t tf_debug_apartment(void);

/// Solo prueba: 1 si el hilo que llama es el principal del proceso, 0 si no.
TF_API int32_t tf_debug_is_main_thread(void);

// ---- P9 prueba 3 (Fase 7f): fotogramas ----

#define TF_CHANNEL_CAMERA 0
#define TF_CHANNEL_MONTAGE 1

/// Tabla que da el runner (macOS). Se llama solo desde el hilo de plataforma salvo `frame_available`,
/// cuya implementación del runner reencola a main si hace falta.
typedef struct {
  int64_t (*register_texture)(int32_t channel);
  void (*frame_available)(int64_t id);
  void (*unregister_texture)(int64_t id);
} tf_texture_host;

/// Nulo = sin texturas. Antes de que Dart arranque el núcleo.
TF_API void tf_core_set_texture_host(const tf_texture_host *host);
/// host->register_texture; -1 si no hay host. Desde el hilo de plataforma.
TF_API int64_t tf_texture_create(int32_t channel);
TF_API void tf_texture_dispose(int32_t channel);
/// CVPixelBufferRef retenido (+1) del último fotograma o NULL (siempre NULL fuera de Apple). Thread-safe.
TF_API void *tf_frame_copy(int32_t channel);

/// Solo prueba. 0 bien.
TF_API int32_t tf_debug_frames_start(int32_t channel, int32_t width, int32_t height, int32_t fps);
TF_API void tf_debug_frames_stop(int32_t channel);
/// Copia el último fotograma a dst (BGRA8888 compacto). *outSeq es entrada (último visto) y salida.
/// Devuelve bytes escritos; 0 sin fotograma nuevo; -1 no cabe.
TF_API int32_t tf_debug_frame_bgra(int32_t channel, uint8_t *dst, int32_t capacity, int32_t *outWidth, int32_t *outHeight, int64_t *outSeq);
TF_API void tf_debug_frames_stats(int32_t channel, int64_t *produced, int64_t *textureCopies, int64_t *distinctTextureCopies, int64_t *bgraCopies);
/// Prueba 7 (P9.7f-B): out[0..n) = [0 copiasBgraDistintas, 1 peticiones, 2 peticionesRepetidas, 3 peticionesConHueco,
/// 4 secuenciasSaltadas, 5 peticionesConHuecoTardias(>40 ms), 6..12 productor, 13..19 peticiones]. Cada bloque de intervalos:
/// [cuenta, min, p50, p99, max (µs), <8 ms, >50 ms]. Contadores 1..19 desde el último tf_debug_frames_reset (ventana).
TF_API void tf_debug_frames_extra(int32_t channel, int64_t *out, int32_t n);
TF_API void tf_debug_frames_reset(int32_t channel);
/// Coste medio del generador, µs por fotograma.
TF_API int64_t tf_debug_frames_cost_us(int32_t channel);

#ifdef _WIN32
/// Interno (Windows, tf_d3d.c): textura D3D11 B8G8R8A8 compartida por canal (handle clásico de
/// IDXGIResource::GetSharedHandle, el que pide kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle).
/// Sube un fotograma BGRA compacto (la recrea si cambia el tamaño). 0 bien.
TF_API int32_t tf_d3d_upload(int32_t channel, const uint8_t *bgra, int32_t width, int32_t height);
/// Tamaño de la textura del canal. 0 bien; 1 no hay textura.
TF_API int32_t tf_d3d_size(int32_t channel, int32_t *width, int32_t *height);
/// HANDLE compartido de la última textura subida del canal, o NULL.
TF_API void *tf_d3d_handle(int32_t channel);
/// Libera la textura del canal.
TF_API void tf_d3d_release(int32_t channel);
/// Espera de alta resolución (CREATE_WAITABLE_TIMER_HIGH_RESOLUTION) en el hilo que llama. 0 bien.
TF_API int32_t tf_hr_sleep_ns(int64_t ns);
#endif

#ifdef __cplusplus
}
#endif

#endif
