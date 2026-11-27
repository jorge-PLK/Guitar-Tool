#pragma once
// Shim C/COM de Media Foundation (plan, «Fase 7c», paso 7, parte 7.2). Solo existe en Windows; en el resto de
// plataformas el objetivo compila vacío. Lo usa VideoKit (`#if os(Windows)`): escritor MP4 (`IMFSinkWriter`), lector
// (`IMFSourceReader`), listado de codificadores y cámaras (captura asíncrona con marcas QPC del dispositivo).
//
// Convenciones: los `int32_t` de vuelta son HRESULT (0 = bien, negativo = error) salvo que se diga otra cosa; las rutas
// e identificadores van en UTF-16 terminado en 0; los tiempos en unidades de 100 ns. Cada llamada inicia COM (MTA) en
// el hilo que llama si hace falta: Swift salta de hilo entre tareas.
#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#include <stdint.h>

/// Versión del shim (para el test de humo).
int mf_shim_version(void);

enum { TFMF_CODEC_H264 = 0, TFMF_CODEC_HEVC = 1 };
enum { TFMF_PIXEL_BGRA = 0, TFMF_PIXEL_NV12 = 1 };

// --- Codificadores -------------------------------------------------------------------------------------------------
typedef struct TFMFEncoderInfo {
    int32_t codec;      // TFMF_CODEC_*
    int32_t hardware;   // 1 si el MFT es de hardware
    char name[256];     // nombre del MFT en UTF-8
} TFMFEncoderInfo;

/// Codificadores de vídeo registrados para `codec` (MFTEnumEx, síncronos, asíncronos y de hardware, ya filtrados). Escribe
/// hasta `capacity` y devuelve cuántos hay (o un HRESULT negativo).
int32_t tfmf_list_encoders(int32_t codec, TFMFEncoderInfo *out, int32_t capacity);

// --- Escritor --------------------------------------------------------------------------------------------------------
typedef struct TFMFWriterConfig {
    int32_t width, height;          // pares (NV12)
    int32_t fpsNum, fpsDen;
    int32_t codec;                  // TFMF_CODEC_*
    int32_t videoBitrate;           // bits/s
    int32_t audioChannels;          // 0: sin audio; 1 o 2
    int32_t audioSampleRate;        // 44100 o 48000
    int32_t audioBytesPerSecond;    // AAC: 12000, 16000, 20000 o 24000
    int32_t realTime;               // 1: sin espera (throttling desactivado); 0: WriteSample espera al codificador
} TFMFWriterConfig;

/// Crea un MP4 (contenedor MPEG-4 sea cual sea la extensión). `step`: qué paso falló (texto estático).
int32_t tfmf_writer_create(const uint16_t *path, const TFMFWriterConfig *config, void **writer, const char **step);
/// Un fotograma. BGRA: `bytesPerRow` del único plano. NV12: luma y, a continuación (`data + bytesPerRow · alto`), el
/// plano UV con el mismo `bytesPerRow`. El BGRA se pasa a NV12 BT.709 de rango limitado.
int32_t tfmf_writer_video(void *writer, int32_t pixelFormat, const uint8_t *data, int32_t bytesPerRow,
                          int64_t time100ns, int64_t duration100ns);
/// PCM de 16 bits entrelazado (`frames` por canal).
int32_t tfmf_writer_audio(void *writer, const int16_t *interleaved, int32_t frames, int64_t time100ns);
int32_t tfmf_writer_finalize(void *writer);
void tfmf_writer_release(void *writer);

// --- Conversión de color (BT.709, rango limitado 16-235) ----------------------------------------------------------
void tfmf_bgra_to_nv12(const uint8_t *bgra, int32_t bgraStride, int32_t width, int32_t height,
                       uint8_t *y, int32_t yStride, uint8_t *uv, int32_t uvStride);
void tfmf_nv12_to_bgra(const uint8_t *y, int32_t yStride, const uint8_t *uv, int32_t uvStride, int32_t width, int32_t height,
                       uint8_t *bgra, int32_t bgraStride);

// --- Lector ----------------------------------------------------------------------------------------------------------
typedef struct TFMFReaderInfo {
    int32_t hasVideo, width, height;
    int32_t fpsNum, fpsDen;
    uint32_t videoFourCC;           // subtipo del vídeo en el fichero ('H264', 'HEVC', ...)
    int32_t hasAudio, sampleRate, channels;
    uint32_t audioFormatTag;        // Data1 del subtipo de audio (0x1610 AAC)
    int64_t duration100ns;
} TFMFReaderInfo;

typedef struct TFMFVideoFrame {
    int64_t time100ns, duration100ns;
    int32_t width, height;
    const uint8_t *y; int32_t yStride;
    const uint8_t *uv; int32_t uvStride;
} TFMFVideoFrame;

typedef struct TFMFAudioChunk {
    int64_t time100ns;
    const float *samples;           // entrelazado
    int32_t frames, channels;
} TFMFAudioChunk;

/// Abre un fichero para leer su primer vídeo (decodificado a NV12) o su primer audio (float), no los dos a la vez.
int32_t tfmf_reader_open(const uint16_t *path, int32_t wantVideo, int32_t wantAudio, void **reader, TFMFReaderInfo *info);
/// Siguiente fotograma (válido hasta la siguiente llamada). `eos` = 1 al final.
int32_t tfmf_reader_video(void *reader, TFMFVideoFrame *frame, int32_t *eos);
/// Siguiente trozo de audio (válido hasta la siguiente llamada). `eos` = 1 al final.
int32_t tfmf_reader_audio(void *reader, TFMFAudioChunk *chunk, int32_t *eos);
/// Salta a `time100ns` (marca del lector): el siguiente fotograma o trozo sale del punto de acceso anterior (en H.264, el
/// fotograma clave previo), no necesariamente de ese instante exacto.
int32_t tfmf_reader_seek(void *reader, int64_t time100ns);
void tfmf_reader_release(void *reader);

// --- Cámaras ---------------------------------------------------------------------------------------------------------
typedef struct TFMFCameraInfo {
    char id[1024];                  // enlace simbólico del dispositivo (UTF-8)
    char name[256];
} TFMFCameraInfo;

typedef struct TFMFCameraFormat {
    int32_t index;                  // tipo nativo en el lector
    int32_t width, height;
    uint32_t fourCC;
    int32_t fpsNum, fpsDen, fpsMinNum, fpsMinDen, fpsMaxNum, fpsMaxDen;
} TFMFCameraFormat;

typedef struct TFMFCameraFrame {
    int64_t sampleTime100ns;        // marca del lector
    int64_t deviceQPC100ns;         // MFSampleExtension_DeviceTimestamp (QPC en 100 ns), si `hasDeviceTime`
    int32_t hasDeviceTime;
    int64_t systemTime100ns;        // MFGetSystemTime al entrar en la devolución de llamada (QPC en 100 ns)
    int32_t width, height;
    const uint8_t *y; int32_t yStride;
    const uint8_t *uv; int32_t uvStride;
} TFMFCameraFrame;

typedef void (*tfmf_camera_callback)(void *context, const TFMFCameraFrame *frame);
typedef void (*tfmf_change_callback)(void *context);

/// Cámaras de vídeo (MFEnumDeviceSources). Devuelve cuántas hay (0 sin cámara) o un HRESULT negativo.
int32_t tfmf_camera_list(TFMFCameraInfo *out, int32_t capacity);
/// Formatos nativos de una cámara. Devuelve cuántos hay o un HRESULT negativo.
int32_t tfmf_camera_formats(const uint16_t *id, TFMFCameraFormat *out, int32_t capacity);
/// 0 si la privacidad de Windows niega la cámara a las aplicaciones de escritorio; 1 si no.
int32_t tfmf_camera_access(void);
/// Empieza a capturar el formato nativo `formatIndex` a `fpsNum/fpsDen` (0: el del formato), con salida NV12. Las
/// devoluciones de llamada llegan en orden en un hilo de Media Foundation.
int32_t tfmf_capture_start(const uint16_t *id, int32_t formatIndex, int32_t fpsNum, int32_t fpsDen,
                           tfmf_camera_callback callback, void *context, void **capture,
                           int32_t *width, int32_t *height, int32_t *outFpsNum, int32_t *outFpsDen);
/// Para la captura; al volver no hay ninguna devolución de llamada en curso ni pendiente.
void tfmf_capture_stop(void *capture);
/// Aviso al conectar o desconectar una cámara (CM_Register_Notification). `NULL` si no se pudo registrar.
void *tfmf_watch_cameras(tfmf_change_callback callback, void *context);
void tfmf_unwatch_cameras(void *watch);

/// QPC actual en unidades de 100 ns (MFGetSystemTime).
int64_t tfmf_system_time(void);
#endif

#ifdef __cplusplus
}
#endif
