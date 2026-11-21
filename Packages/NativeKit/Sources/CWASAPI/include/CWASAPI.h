#pragma once
// Shim C/COM de WASAPI (plan, «Fase 7c», paso 7, parte 7.7; P8 «E/S en vivo»: WASAPI propio con marcas por búfer).
// Solo existe en Windows; en el resto de plataformas el objetivo compila vacío.
//
// Qué da (lo que pide el contrato de `WASAPIAudioIO` y `DuplexClockSync` en AudioKit):
// - Enumeración de endpoints de render y captura: id, nombre, formato de mezcla, periodos de `GetDevicePeriod` y de
//   `IAudioClient3::GetSharedModeEnginePeriod`.
// - Flujo dúplex por eventos en un único hilo de audio con MMCSS «Pro Audio»: compartido (`InitializeSharedAudioStream`
//   con el periodo mínimo; respaldo `IAudioClient::Initialize`) o exclusivo (`Initialize` exclusivo con el periodo
//   mínimo y alineado de búfer).
// - Por búfer de salida: fotogramas escritos antes del búfer + `IAudioClock::GetPosition` (posición y su QPC).
//   Por paquete de captura: `u64DevicePosition`, `u64QPCPosition` y los flags de `GetBuffer`.
// - Las muestras pasan como float32 entrelazado en búferes reservados al abrir (la conversión de formato, si el
//   exclusivo no admite float, la hace el shim). El hilo de audio no reserva memoria ni toma cerrojos.
// - Desconexión, cambio de dispositivo por defecto y errores del flujo se notifican por `wasapi_event_cb`; el hilo
//   de audio sale solo si el dispositivo se invalida o deja de dar eventos, y `wasapi_stop` nunca espera sin tope.
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
/// Versión del shim (para el test de humo).
int wasapi_shim_version(void);

#define WASAPI_ID_CAP 256
#define WASAPI_NAME_CAP 256

/// Flujo del endpoint.
enum { WASAPI_FLOW_RENDER = 0, WASAPI_FLOW_CAPTURE = 1 };
/// Modo de compartición.
enum { WASAPI_MODE_SHARED = 0, WASAPI_MODE_EXCLUSIVE = 1 };
/// Cómo se inicializó cada lado.
enum {
    WASAPI_PATH_NONE = 0,
    WASAPI_PATH_CLIENT3_SHARED = 1,   ///< IAudioClient3::InitializeSharedAudioStream (periodo mínimo del motor)
    WASAPI_PATH_CLIENT_SHARED = 2,    ///< IAudioClient::Initialize compartido (periodo por defecto del motor)
    WASAPI_PATH_AUTOCONVERT = 3,      ///< IAudioClient::Initialize compartido con AUTOCONVERTPCM (otra frecuencia)
    WASAPI_PATH_EXCLUSIVE = 4,        ///< IAudioClient::Initialize exclusivo
};
/// Flags de captura (los de `AUDCLNT_BUFFERFLAGS_*`, mismos valores).
enum {
    WASAPI_CAPTURE_DISCONTINUITY = 0x1,
    WASAPI_CAPTURE_SILENT = 0x2,
    WASAPI_CAPTURE_TIMESTAMP_ERROR = 0x4,
};
/// Eventos notificados (desde un hilo de COM o desde el hilo de audio al salir; el manejador debe volver enseguida y
/// NO llamar a `wasapi_stop`/`wasapi_close` desde dentro).
enum {
    WASAPI_EVENT_DEFAULT_CHANGED = 1,   ///< cambió el dispositivo por defecto de `flow` (consola); `device_id` el nuevo
    WASAPI_EVENT_DEVICE_REMOVED = 2,    ///< un endpoint del flujo desapareció o dejó de estar activo
    WASAPI_EVENT_DEVICE_INVALIDATED = 3,///< AUDCLNT_E_DEVICE_INVALIDATED en el hilo de audio: el flujo se detuvo
    WASAPI_EVENT_STREAM_ERROR = 4,      ///< otro HRESULT de error en el hilo de audio (`hresult`): el flujo se detuvo
    WASAPI_EVENT_STALLED = 5,           ///< sin eventos de audio durante `WASAPI_STALL_MS`: el flujo se detuvo
    WASAPI_EVENT_FORMAT_CHANGED = 6,    ///< cambió la propiedad de formato de un endpoint del flujo
};
/// Sin eventos durante este tiempo, el hilo de audio da el flujo por colgado y sale (decisión propia: 20 periodos de
/// 10 ms con margen de sobra).
#define WASAPI_STALL_MS 2000

/// Formato de un lado.
typedef struct wasapi_format {
    uint32_t sample_rate;
    uint16_t channels;
    uint16_t bits;          ///< bits del contenedor
    uint16_t valid_bits;
    uint16_t is_float;      ///< 1 = IEEE float, 0 = PCM entero
} wasapi_format;

/// Endpoint enumerado.
typedef struct wasapi_device_info {
    char id[WASAPI_ID_CAP];        ///< id del endpoint (UTF-8), estable entre arranques
    char name[WASAPI_NAME_CAP];    ///< nombre amigable (UTF-8)
    int32_t flow;                  ///< WASAPI_FLOW_*
    int32_t is_default;            ///< 1 si es el de consola por defecto de su flujo
    wasapi_format mix;             ///< formato de mezcla del motor
    int64_t default_period_100ns;  ///< IAudioClient::GetDevicePeriod (compartido)
    int64_t minimum_period_100ns;  ///< IAudioClient::GetDevicePeriod (mínimo, exclusivo)
    int32_t has_client3;           ///< 1 si el endpoint da IAudioClient3
    uint32_t engine_default_frames;     ///< GetSharedModeEnginePeriod: periodo por defecto
    uint32_t engine_fundamental_frames; ///< ... paso
    uint32_t engine_min_frames;         ///< ... mínimo
    uint32_t engine_max_frames;         ///< ... máximo
    int32_t exclusive_float_ok;    ///< IsFormatSupported(EXCLUSIVE) con float32 al formato de mezcla
    int32_t hresult;               ///< 0 o el primer error al consultar el endpoint
} wasapi_device_info;

/// Escribe hasta `capacity` endpoints activos de render y captura en `out` y devuelve cuántos hay (puede ser mayor que
/// `capacity`), o un HRESULT negativo.
int32_t wasapi_enumerate(wasapi_device_info *out, int32_t capacity);

/// Marcas de un búfer de salida.
typedef struct wasapi_render_info {
    uint64_t frames_written;    ///< fotogramas escritos antes de este búfer (sampleTime del búfer)
    uint64_t clock_position;    ///< IAudioClock::GetPosition, en unidades de `clock_frequency`
    uint64_t clock_qpc_100ns;   ///< su QPC, en 100 ns (DuplexClockSync.seconds(qpc100ns:)); 0 si falló
    uint64_t clock_frequency;   ///< IAudioClock::GetFrequency
    uint64_t wake_qpc_ticks;    ///< QueryPerformanceCounter al despertar el hilo (ticks de HostClock)
    uint32_t padding_frames;    ///< GetCurrentPadding antes de escribir (compartido; 0 en exclusivo)
    uint32_t reserved;
} wasapi_render_info;

/// Marcas de un paquete de captura.
typedef struct wasapi_capture_info {
    uint64_t device_position;   ///< u64DevicePosition (fotograma de captura del primer fotograma), en fotogramas
                                ///< del ENDPOINT: con AUTOCONVERTPCM va a `capture_device_rate`, no a la del flujo
    uint64_t stream_position;   ///< lo mismo en fotogramas del flujo: = device_position sin conversión; con
                                ///< AUTOCONVERTPCM, contador consecutivo que se resincroniza a device_position·razón
                                ///< al arrancar y en cada discontinuidad. Es la que va a DuplexClockSync.addCapturePacket
    uint64_t qpc_100ns;         ///< u64QPCPosition (100 ns), instante de device_position
    uint64_t wake_qpc_ticks;    ///< QueryPerformanceCounter al despertar el hilo
    uint32_t flags;             ///< WASAPI_CAPTURE_* (SILENT ya puesto a cero en las muestras)
    uint32_t reserved;
} wasapi_capture_info;

/// Llena `frames` fotogramas de `channels` canales float32 entrelazados (el búfer llega a cero). Hilo de audio.
typedef void (*wasapi_render_cb)(void *ctx, float *interleaved, uint32_t frames, uint32_t channels,
                                 const wasapi_render_info *info);
/// Recibe `frames` fotogramas float32 entrelazados capturados. Hilo de audio.
typedef void (*wasapi_capture_cb)(void *ctx, const float *interleaved, uint32_t frames, uint32_t channels,
                                  const wasapi_capture_info *info);
/// Evento (WASAPI_EVENT_*). `device_id` UTF-8 o NULL; `flow` WASAPI_FLOW_* o -1.
typedef void (*wasapi_event_cb)(void *ctx, int32_t kind, int32_t flow, const char *device_id, int32_t hresult);

/// Parámetros de apertura.
typedef struct wasapi_open_params {
    const char *render_id;     ///< NULL o "" = render por defecto
    const char *capture_id;    ///< NULL o "" = captura por defecto
    int32_t mode;              ///< WASAPI_MODE_*
    uint32_t sample_rate;      ///< 0 = el de mezcla del render
    uint32_t period_frames;    ///< 0 = el mínimo que admita el camino elegido
    int32_t use_render;        ///< 0 = sin salida
    int32_t use_capture;       ///< 0 = sin entrada
    wasapi_render_cb render;
    wasapi_capture_cb capture;
    wasapi_event_cb event;
    void *ctx;
} wasapi_open_params;

/// Lo que quedó abierto.
typedef struct wasapi_stream_info {
    int32_t mode;
    int32_t render_path, capture_path;      ///< WASAPI_PATH_*
    wasapi_format render_format, capture_format;   ///< formato del dispositivo (las muestras pasan como float32)
    uint32_t render_buffer_frames, capture_buffer_frames;  ///< GetBufferSize
    uint32_t render_period_frames, capture_period_frames;  ///< periodo pedido/concedido (motor o dispositivo)
    int64_t render_latency_100ns, capture_latency_100ns;   ///< GetStreamLatency
    uint64_t clock_frequency;               ///< IAudioClock::GetFrequency del render (en compartido suele ser bytes/s)
    uint32_t capture_device_rate;           ///< frecuencia de mezcla del endpoint de captura (≠ la del flujo con AUTOCONVERTPCM)
    uint32_t reserved;
    char render_id[WASAPI_ID_CAP], capture_id[WASAPI_ID_CAP];
    char render_name[WASAPI_NAME_CAP], capture_name[WASAPI_NAME_CAP];
} wasapi_stream_info;

/// Estado tras arrancar o parar (contadores del hilo de audio).
typedef struct wasapi_stream_status {
    int32_t running;
    int32_t mmcss_ok;               ///< 1 si AvSetMmThreadCharacteristicsW("Pro Audio") funcionó
    int32_t last_hresult;           ///< 0 o el error que paró el hilo
    int32_t stop_reason;            ///< 0 = parada pedida, o WASAPI_EVENT_* que lo paró
    uint64_t render_buffers;        ///< llamadas a `render` con frames > 0
    uint64_t render_starved;        ///< despertares de render sin hueco (padding == búfer)
    uint64_t capture_packets;       ///< llamadas a `capture`
    uint64_t wakeups;               ///< despertares del hilo
    uint64_t clock_failures;        ///< IAudioClock::GetPosition fallido
} wasapi_stream_status;

typedef struct wasapi_stream wasapi_stream;

/// Abre (sin arrancar). Devuelve 0 o un HRESULT negativo; en `step` (si no es NULL) deja la operación que falló.
int32_t wasapi_open(const wasapi_open_params *params, wasapi_stream **out, wasapi_stream_info *info,
                    const char **step);
/// Arranca: rellena la salida con silencio, crea el hilo de audio y arranca los clientes. 0 o HRESULT.
int32_t wasapi_start(wasapi_stream *stream);
/// Para el hilo (espera como mucho `WASAPI_STALL_MS` + 500 ms), detiene y reinicia los clientes (posiciones a 0).
/// Se puede volver a arrancar después. Idempotente.
void wasapi_stop(wasapi_stream *stream);
/// Contadores actuales (léelos tras `wasapi_stop` para valores coherentes).
void wasapi_get_status(const wasapi_stream *stream, wasapi_stream_status *status);
/// Para si hace falta y libera todo. Admite NULL.
void wasapi_close(wasapi_stream *stream);
#endif

#ifdef __cplusplus
}
#endif
