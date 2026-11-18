#pragma once
#include <stddef.h>
// Cabeceras de ONNX Runtime fuera del repo (C:\ort\include, iguales para ARM64 y x64).
#include "C:/ort/include/onnxruntime_c_api.h"

/// Tabla de funciones de la API C para ORT_API_VERSION (NULL si la DLL es más antigua que las cabeceras).
const OrtApi *tf_ort_api(void);
/// Versión de la onnxruntime.dll cargada (p. ej. "1.32.0").
const char *tf_ort_version(void);
/// CreateSession con la ruta en UTF-8 (ORTCHAR_T es wchar_t en Windows: la conversión se hace aquí).
OrtStatus *tf_create_session(const OrtApi *api, OrtEnv *env, const char *utf8_path,
                             OrtSessionOptions *options, OrtSession **out);
/// Pico del conjunto de trabajo del proceso, en bytes.
size_t tf_peak_working_set(void);
/// Ruta completa de la onnxruntime.dll cargada (para descartar la de System32), en UTF-8.
const char *tf_loaded_ort_path(void);
