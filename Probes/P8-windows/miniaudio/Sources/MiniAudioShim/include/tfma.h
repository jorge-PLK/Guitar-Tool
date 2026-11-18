// Fachada mínima sobre miniaudio para la prueba c del paso 4 (Fase 7c). Swift no ve miniaudio.h.
#ifndef TFMA_H
#define TFMA_H

#include <stdint.h>

/// Lo llama el hilo de audio de miniaudio en cada periodo (marca de QPC tomada en C al entrar).
typedef void (*tfma_period_cb)(void *user, uint32_t frames, int64_t qpc);

/// Inicializa un contexto WASAPI, imprime dispositivos (salida y entrada) y lo cierra.
/// Devuelve el número de dispositivos (>= 0) o el código de error de miniaudio (< 0).
int tfma_wasapi_report(void);

/// Abre un dispositivo de salida en el backend nulo (reloj propio de miniaudio, sin hardware) y llama a `cb`
/// en cada periodo durante `milliseconds`. Devuelve 0 o el código de error.
int tfma_null_playback(uint32_t sampleRate, uint32_t periodFrames, uint32_t milliseconds, tfma_period_cb cb, void *user);

/// Intenta abrir el dúplex por defecto en WASAPI (compartido, 48 kHz, periodo `periodFrames`) y lo deja correr
/// `milliseconds`. Imprime el resultado. Devuelve 0 o el código de error (en la VM sin audio es normal que falle).
int tfma_wasapi_duplex(uint32_t periodFrames, uint32_t milliseconds, tfma_period_cb cb, void *user);

/// Escribe un WAV de prueba (seno de 1 kHz, f32 estéreo) en `pathUTF8` con la API _w (rutas no ASCII).
int tfma_write_wav(const char *pathUTF8, uint32_t sampleRate, uint32_t frames);

/// Decodifica entero (dr_wav, dr_mp3 o dr_flac según el fichero) a f32 con sus canales y frecuencia nativos.
/// Rellena frames, frecuencia, canales, RMS y pico del canal 0, y el primer índice con |x| > 0,01.
int tfma_decode(const char *pathUTF8, uint64_t *frames, uint32_t *sampleRate, uint32_t *channels,
                double *rms, double *peak, int64_t *firstAbove);

int64_t tfma_qpc(void);
int64_t tfma_qpc_frequency(void);

#endif
