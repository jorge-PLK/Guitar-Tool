#ifndef TF_CORE_H
#define TF_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Mensaje del núcleo (UTF-8, sin terminador). El búfer es del núcleo hasta `tf_core_free(utf8)`.
/// Se invoca desde cualquier hilo.
typedef void (*tf_message_cb)(const uint8_t *utf8, int32_t len);

/// `optionsJSON` = {"args":["--projects-folder","...", ...]}. `textures` se ignora (nulo) en esta parte.
/// 0 ok; 1 ya arrancado; 2 opciones inválidas; 3 falló Bridge.init.
int32_t tf_core_start(const char *optionsJSON, tf_message_cb onMessage, const void *textures);

/// Entrega {id, method, params} a Bridge.receive. Copia los bytes antes de volver; no bloquea.
void tf_core_send(const uint8_t *utf8, int32_t len);

/// Libera un búfer entregado por callback.
void tf_core_free(const uint8_t *ptr);

/// Asíncrono: vuelve enseguida y emite {"event":"core.shutdown","payload":{"clean":bool}}.
void tf_core_shutdown(int32_t timeoutMs);

/// Solo prueba: búferes entregados y aún no liberados.
int64_t tf_debug_live_buffers(void);

/// Inicializa la API DL de Dart (= Dart_InitializeApiDL(data)); 0 = ok. Llamar antes de `tf_core_start_port`.
intptr_t tf_core_init_dart_api(void *data);

/// Como `tf_core_start`, pero el sumidero es un puerto nativo de Dart: cada mensaje se envía como
/// kExternalTypedData (Uint8) sin copia; Dart libera el búfer con el finalizador (tf_core_free).
int32_t tf_core_start_port(const char *optionsJSON, int64_t port);

/// Solo prueba: reloj monótono en ns.
int64_t tf_debug_now_ns(void);

/// Solo prueba: emisor sintético por el sumidero activo. hz <= 0 = ráfaga. 0 lanzado; 1 no arrancado; 2 ya en curso.
int32_t tf_debug_emit(int32_t hz, int32_t count, int32_t bytes);

/// Interno (usado desde Swift): envía un búfer malloc por el puerto como kExternalTypedData.
/// false si el puerto no acepta (el llamante conserva la propiedad y lo libera).
bool tf_post_external(int64_t port, uint8_t *ptr, intptr_t len);

#ifdef __cplusplus
}
#endif

#endif
