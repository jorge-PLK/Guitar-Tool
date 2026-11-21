#pragma once
// Envoltorio C mínimo de r8brain-free-src (MIT): conversión de frecuencia por bloques, doble precisión.
#ifdef __cplusplus
extern "C" {
#endif

typedef struct tf_r8b tf_r8b;

/// Crea un conversor `src_rate` -> `dst_rate` para bloques de hasta `max_in_len` muestras. NULL si falla.
tf_r8b *tf_r8b_create(double src_rate, double dst_rate, int max_in_len);
/// Procesa `n` (<= max_in_len) muestras; deja en `*out` un puntero interno (válido hasta la siguiente
/// llamada) y devuelve cuántas muestras hay en él.
int tf_r8b_process(tf_r8b *r, double *in, int n, const double **out);
/// Latencia entera, en muestras de salida, que hay que descartar al principio.
int tf_r8b_latency(const tf_r8b *r);
/// Vuelve al estado inicial.
void tf_r8b_clear(tf_r8b *r);
void tf_r8b_destroy(tf_r8b *r);

#ifdef __cplusplus
}
#endif
