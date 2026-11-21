#pragma once
// Shim C/COM de Windows (CDirect2D): compositor del montaje con Direct2D + DirectWrite sobre un mapa de bits BGRA
// (plan, «Fase 7c», paso 7, parte 7.9). Solo existe en Windows; en el resto de plataformas el objetivo compila vacío.
//
// Dispositivo: D3D11 de hardware si lo hay y, si no, WARP (render por software); Direct2D sobre su DXGI con un
// ID2D1DeviceContext (los efectos de desenfoque lo necesitan). Todo en píxeles de salida, origen arriba a la izquierda,
// BGRA premultiplicado sin gestión de color (las mezclas van sobre los valores codificados, como en Core Image con
// espacio de trabajo nulo). Un contexto no es seguro entre hilos: quien llama lo serializa.
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
/// Versión del shim (para el test de humo).
int d2d_shim_version(void);

typedef struct TFD2DInfo {
    int32_t hardware;           // 1: adaptador de hardware; 0: WARP o «Microsoft Basic Render Driver»
    uint16_t adapter[128];      // descripción del adaptador DXGI (UTF-16, terminada en 0)
} TFD2DInfo;

/// Contexto de `width` × `height`. `allowHardware` 0 fuerza WARP.
int32_t tfd2d_create(int32_t width, int32_t height, int32_t allowHardware, void **context, TFD2DInfo *info);
void tfd2d_release(void *context);

/// Fotograma BGRA de una parte en `slot` (0…63). Se copia; el alfa se ignora (opaco).
int32_t tfd2d_set_source(void *context, int32_t slot, const uint8_t *bgra, int32_t bytesPerRow, int32_t width, int32_t height);

/// Placa de texto (nombre de parte o rótulo): hasta dos líneas blancas sobre un rectángulo redondeado negro
/// translúcido. Cada línea ocupa una caja de ancho ceil(avance) y alto ceil(ascendente + descendente) con la línea
/// base a `descendente` del borde inferior (como la imagen de Core Text del Mac); la 1 arriba, la 2 debajo a `gap`.
/// Tamaño = (máx. ancho + 2·padX) × (2·padY + alto1 [+ gap + alto2]). `radius` < 0: la mitad del alto.
typedef struct TFD2DPlate {
    const uint16_t *line1;      // UTF-16 terminada en 0, o NULL / vacía
    float size1;
    int32_t bold1;
    const uint16_t *line2;
    float size2;
    int32_t bold2;
    float padX, padY, gap, radius, alpha;
} TFD2DPlate;

/// Fuente de las placas (familia instalada en el sistema). Por defecto «Segoe UI».
int32_t tfd2d_set_font(void *context, const uint16_t *family);
/// Dibuja la placa en `slot` (0…1023, aparte de las fuentes) fuera de un fotograma y devuelve el tamaño del rectángulo
/// (px, con decimales; el mapa de bits es el entero de arriba y el rectángulo empieza en su esquina superior izquierda).
int32_t tfd2d_make_plate(void *context, int32_t slot, const TFD2DPlate *plate, float *width, float *height);

/// Un recuadro del montaje (mismas capas que `MontageRenderer` del Mac).
typedef struct TFD2DBox {
    float x, y, w, h;           // rectángulo mostrado (px)
    int32_t slot;               // fuente; -1: sin imagen (negro)
    int32_t fit;                // 1: fotograma entero ajustado sobre relleno difuminado
    float cropX, cropY, cropW, cropH;   // recorte en fracciones de la fuente (si !fit), origen arriba
    float blur;                 // desenfoque de entrada (sigma, px); <= 0,1: ninguno
    float fillScale;            // relleno: escala de trabajo (`MontageStyle.fillDownsample`)
    float fillBlur;             // relleno: sigma en px de salida (se aplica a la escala de trabajo)
    float fillDim;              // relleno: multiplica RGB
    float brightness;           // fundido a negro de la toma (imagen, relleno y nombre)
    float opacity;
    int32_t decorated;          // esquinas redondeadas y sombra
    float radius, shadowOffset, shadowBlur, shadowAlpha;
    int32_t labelSlot;          // placa del nombre; -1: sin nombre
    float labelX, labelY;       // esquina superior izquierda de la placa (px)
} TFD2DBox;

/// Empieza un fotograma con el fondo (0…1).
int32_t tfd2d_begin(void *context, float r, float g, float b);
int32_t tfd2d_box(void *context, const TFD2DBox *box);
/// Placa (rótulo) en (x, y) con opacidad.
int32_t tfd2d_overlay(void *context, int32_t plateSlot, float x, float y, float opacity);
/// Fundido global (RGB · fade), cierra el fotograma y copia el resultado BGRA en `out`.
int32_t tfd2d_end(void *context, float fade, uint8_t *out, int32_t bytesPerRow);
#endif

#ifdef __cplusplus
}
#endif
