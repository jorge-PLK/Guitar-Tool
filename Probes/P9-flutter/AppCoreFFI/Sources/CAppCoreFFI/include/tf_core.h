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

#ifdef __cplusplus
}
#endif

#endif
