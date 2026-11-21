#pragma once
// Lanzamiento de procesos hijos sin ventana de consola (plan, «Fase 7c», paso 8). Lo usa `ChildProcess`
// (NativePlatform) en Windows en lugar de Foundation `Process`, que no pasa `CREATE_NO_WINDOW`: la app es de
// subsistema GUI, no tiene consola, y cada hijo de consola (tf-separate, yt-dlp, ffmpeg, tar) abría la suya.
// Solo existe en Windows; en el resto de plataformas el objetivo compila vacío.
//
// En C y no en Swift porque `PROC_THREAD_ATTRIBUTE_HANDLE_LIST` es una macro con función que Swift no importa.
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
/// Resultado de `tf_child_spawn`.
typedef struct {
    void *process;     ///< HANDLE del proceso (lo cierra el llamador con CloseHandle)
    uint32_t pid;
    int32_t in_job;    ///< 1 si entró en `job` antes de ejecutar su primera instrucción
} tf_child_info;

/// Handle estándar del proceso actual (0 entrada, 1 salida, 2 error); NULL si no tiene (app GUI).
void *tf_child_parent_std(int32_t which);

/// Lanza `command_line` (UTF-16, ejecutable citado en cabeza) con
/// `CREATE_NO_WINDOW | CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT`:
/// - `environment`: bloque UTF-16 `k=v\0…\0\0`, o NULL para heredar el del padre.
/// - `directory`: directorio de trabajo, o NULL para heredar.
/// - `std_in`, `std_out`, `std_err`: handles que verá el hijo (se duplican como heredables; los originales no se
///   tocan), o NULL para `NUL`. Con `STARTF_USESTDHANDLES` y una lista de handles heredables acotada a estos tres
///   (`PROC_THREAD_ATTRIBUTE_HANDLE_LIST`): el hijo no hereda tuberías de otros hijos lanzados a la vez.
/// - `job`: si no es NULL, el hijo entra en él estando suspendido y luego se reanuda (sus nietos ya nacen dentro).
/// Devuelve 0 y rellena `out`, o el `GetLastError` del fallo.
uint32_t tf_child_spawn(const uint16_t *command_line, const uint16_t *environment, const uint16_t *directory,
                        void *std_in, void *std_out, void *std_err, void *job, tf_child_info *out);
#endif

#ifdef __cplusplus
}
#endif
