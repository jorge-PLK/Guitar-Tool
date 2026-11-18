// Referencias calculadas en el Mac con vDSP (ref_data.c, generado). Fase 7c paso 4, prueba b.
#ifndef TF_REF_DATA_H
#define TF_REF_DATA_H

// FFT real de 4096 con vDSP_DFT_zrop (float): entrada y salida empaquetada de vDSP
// (re[0] = 2·X[0], im[0] = 2·X[N/2], re[k] + i·im[k] = 2·X[k]).
const float *tf_ref_x_ptr(void);
const float *tf_ref_re_ptr(void);
const float *tf_ref_im_ptr(void);

// SignalMath.analyticCorrelation (vDSP_DFT_zop double, n = 65536): pico de la envolvente,
// posición con interpolación parabólica, su valor y la envolvente cada 40 muestras.
int tf_corr_peak_index(void);
double tf_corr_peak_position(void);
double tf_corr_peak_value(void);
const double *tf_corr_env_ptr(void);

#endif
