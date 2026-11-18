// Fachada C mínima sobre Media Foundation (IMFSinkWriter) para la prueba d del paso 4 (Fase 7c).
#ifndef TFMF_H
#define TFMF_H

#include <stdint.h>

/// Escribe `seconds` s de vídeo sintético (640x360, 30 fps, NV12 → H.264 si `hevc` = 0, HEVC si 1) y,
/// si `withAudio`, audio PCM 48 kHz estéreo → AAC 128 kb/s a un MP4 en `pathUTF8`.
/// Marca de sincronía: el fotograma 30 (t = 1,000 s) es blanco y el audio lleva un clic en t = 1,000 s.
/// Devuelve 0 o el HRESULT que falló; `step` recibe el nombre del paso que falló.
int32_t tfmf_write(const char *pathUTF8, int seconds, int hevc, int withAudio, const char **step);

#endif
