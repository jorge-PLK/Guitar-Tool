#pragma once
// ONNX Runtime 1.32.0 por su API C (cabeceras de NuGet Microsoft.ML.OnnxRuntime, MIT). Solo Windows:
// en el resto de plataformas el .c compila vacío y nadie importa el módulo.
#include <stddef.h>
#include <stdint.h>
#include "onnxruntime_c_api.h"

/// Tabla de funciones de la API C para ORT_API_VERSION (NULL si no hay onnxruntime.dll o es más antigua que las cabeceras).
const OrtApi *tf_ort_api(void);
/// Versión de API obtenida (ORT_API_VERSION o menor con una DLL más antigua, mínimo 17); 0 sin DLL.
uint32_t tf_ort_api_version(void);
/// Versión de la onnxruntime.dll cargada (p. ej. "1.32.0"); NULL si no se pudo cargar.
const char *tf_ort_version(void);
/// CreateSession con la ruta en UTF-8 (ORTCHAR_T es wchar_t en Windows: la conversión se hace aquí).
OrtStatus *tf_create_session(const OrtApi *api, OrtEnv *env, const char *utf8_path,
                             OrtSessionOptions *options, OrtSession **out);

// --- Sesión (parte 7.8) --------------------------------------------------------------------------------

/// Proveedores (mismo orden que `OnnxProvider` en Swift no importa: se pasan por este código).
enum { TF_ORT_CPU = 0, TF_ORT_DIRECTML = 1, TF_ORT_CUDA = 2, TF_ORT_QNN = 3 };

typedef struct {
    int intra_threads;   ///< 0: el de ORT (núcleos físicos).
    int mem_arena;       ///< 0: sin reserva de memoria de CPU (separación con dynamo: si no, pasa de 10 GB).
    int mem_pattern;     ///< 0: sin patrón de memoria (DirectML lo exige a 0).
    int provider;        ///< TF_ORT_*.
    int device_id;       ///< Índice del adaptador DXGI (DirectML) o de la GPU CUDA.
} tf_ort_options;

typedef struct tf_ort_session tf_ort_session;

/// Crea la sesión. 0 bien; si no, mensaje en `err` (truncado a `err_len`).
int tf_ort_session_create(const char *utf8_path, const tf_ort_options *options, tf_ort_session **out,
                          char *err, size_t err_len);
void tf_ort_session_release(tf_ort_session *s);
size_t tf_ort_session_input_count(const tf_ort_session *s);
size_t tf_ort_session_output_count(const tf_ort_session *s);
const char *tf_ort_session_input_name(const tf_ort_session *s, size_t i);
const char *tf_ort_session_output_name(const tf_ort_session *s, size_t i);
/// Forma declarada de la entrada `i` (-1 en los ejes dinámicos); devuelve el rango (0 si falla).
size_t tf_ort_session_input_shape(const tf_ort_session *s, size_t i, int64_t *dims, size_t cap);

/// Ejecuta con tensores float32 sobre la memoria del llamante (sin copiar las entradas).
/// Salida i: si `out_buffers[i]` no es NULL, ORT escribe ahí con la forma `out_shapes[i]` (sin copia);
/// si es NULL, ORT la reserva y la deja en `out_values[i]` (liberar con tf_ort_value_release).
int tf_ort_session_run(tf_ort_session *s,
                       size_t n_in, const char *const *in_names, float *const *in_data,
                       const int64_t *const *in_shapes, const size_t *in_ranks,
                       size_t n_out, const char *const *out_names, float *const *out_buffers,
                       const int64_t *const *out_shapes, const size_t *out_ranks,
                       OrtValue **out_values, char *err, size_t err_len);
/// Corta las ejecuciones en curso y las siguientes de la sesión (RunOptionsSetTerminate): devuelven error.
void tf_ort_session_terminate(tf_ort_session *s);
size_t tf_ort_value_shape(const OrtValue *v, int64_t *dims, size_t cap);
float *tf_ort_value_data(OrtValue *v);
void tf_ort_value_release(OrtValue *v);

// --- GPU por DXGI (parte 7.8) --------------------------------------------------------------------------

typedef struct {
    char name[128];             ///< Descripción en UTF-8.
    uint32_t vendor_id;         ///< 0x10DE NVIDIA, 0x1002 AMD, 0x8086 Intel, 0x5143 Qualcomm, 0x1414 Microsoft (WARP).
    uint32_t device_id;
    uint64_t dedicated_video_memory;
    uint64_t shared_system_memory;
    int is_software;            ///< DXGI_ADAPTER_FLAG_SOFTWARE (WARP, «Microsoft Basic Render Driver»).
    int adapter_index;          ///< Índice en IDXGIFactory1::EnumAdapters1 (el device_id de DirectML).
} tf_gpu_info;

/// Rellena hasta `cap` adaptadores; devuelve cuántos hay (-1 si DXGI no está).
int tf_dxgi_adapters(tf_gpu_info *out, int cap);
