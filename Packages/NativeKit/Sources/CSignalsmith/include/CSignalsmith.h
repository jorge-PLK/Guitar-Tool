#pragma once
// Envoltorio C mínimo de Signalsmith Stretch (MIT): cambio de tono y estiramiento, Float32 por canales.
#ifdef __cplusplus
extern "C" {
#endif

typedef struct tf_stretch tf_stretch;

/// Crea el procesador con el preset por defecto. NULL si falla.
tf_stretch *tf_stretch_create(int channels, float sample_rate);
/// Factor de tono (2 = una octava arriba); `tonality_limit` 0 = sin límite.
void tf_stretch_set_transpose_factor(tf_stretch *s, float factor, float tonality_limit);
/// Entra `in_n` muestras por canal y sale `out_n` (la relación fija el estiramiento). `in` y `out`
/// son `channels` punteros a Float32.
void tf_stretch_process(tf_stretch *s, const float *const *in, int in_n, float *const *out, int out_n);
int tf_stretch_input_latency(const tf_stretch *s);
int tf_stretch_output_latency(const tf_stretch *s);
/// Muestras de entrada que pide `tf_stretch_output_seek` a la velocidad `rate` (entrada/salida):
/// `input_latency + rate·output_latency`.
int tf_stretch_output_seek_length(const tf_stretch *s, float rate);
/// Tras `reset`: entra `in_n` muestras desde el punto de arranque y precalcula la salida para que lo próximo que
/// devuelva `process` sea ya ese punto (sin latencia de salida). La velocidad se deduce de `in_n`: usar
/// `tf_stretch_output_seek_length`. Lo siguiente que se le da a `process` es la entrada desde `in_n`.
void tf_stretch_output_seek(tf_stretch *s, const float *const *in, int in_n);
/// Entrada previa («pre-roll») para cambiar de punto sin cortar la salida; no calcula nada.
void tf_stretch_seek(tf_stretch *s, const float *const *in, int in_n, double rate);
/// Lo que queda de salida sin más entrada.
void tf_stretch_flush(tf_stretch *s, float *const *out, int out_n, float rate);
int tf_stretch_block_samples(const tf_stretch *s);
int tf_stretch_interval_samples(const tf_stretch *s);
void tf_stretch_reset(tf_stretch *s);
void tf_stretch_destroy(tf_stretch *s);

#ifdef __cplusplus
}
#endif
