#ifndef TF_CORE_H
#define TF_CORE_H

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

#ifdef __cplusplus
}
#endif

#endif
