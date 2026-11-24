// Textura D3D11 compartida por canal para el camino de textura externa en Windows (no se compila en Mac).
// docs/flutter/arquitectura.md, «Canal de fotogramas»: anillo de 3 y handle publicado solo cuando la GPU confirma la subida.
#include "tf_core.h"

#ifdef _WIN32
#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#include <d3d11.h>
#include <dxgi.h>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxguid.lib")

#define TF_D3D_CHANNELS 2
// Anillo de 3 texturas por canal (arquitectura.md, «Canal de fotogramas»; medido en P9 7f).
#define TF_D3D_RING 3
// Tras un cambio de tamaño, las texturas viejas se conservan este número de subidas (~1 s a 30 fps) por si el motor
// aún no ha abierto su handle: abrir un handle clásico ya liberado falla.
#define TF_D3D_RETIRE_UPLOADS 45
// Tope de la espera a la GPU (D3D11_QUERY_EVENT). Medido en P9: 2-4 ms; si se pasa, se publica igual.
#define TF_D3D_WAIT_LIMIT_US 50000

// Hilos: ESCRIBE un único hilo productor por canal (tf_d3d_upload, hilo del generador); LEE el hilo de raster del
// motor (tf_d3d_handle, vía tf_frame_copy). `published` (último completo y confirmado por la GPU) y `delivered`
// (última entregada al motor) son índices LONG que solo se tocan con Interlocked*. Solo el productor modifica
// `published`; solo tf_d3d_handle modifica `delivered` (= published en ese instante). El productor escribe en un
// índice distinto de ambos: como `published` no cambia bajo sus pies y `delivered` solo puede tomar el valor de
// `published`, el índice elegido sigue libre durante toda la escritura. Con 3 texturas siempre hay una libre. El lock
// global solo protege el dispositivo/contexto D3D (el contexto inmediato no es thread-safe y los dos canales lo
// comparten) y la recreación del anillo.
typedef struct {
  ID3D11Texture2D *tex[TF_D3D_RING];
  HANDLE shared[TF_D3D_RING];
  ID3D11Texture2D *retired[TF_D3D_RING];
  int32_t retire_left;
  int32_t n;                 // texturas del anillo (TF_D3D_RING); 0 = sin crear
  volatile LONG published;   // -1 = ninguna
  volatile LONG delivered;   // -1 = ninguna
  int32_t w, h;
  ID3D11Query *query;        // D3D11_QUERY_EVENT: la GPU terminó la subida
} tf_d3d_slot;

static INIT_ONCE tf_d3d_once = INIT_ONCE_STATIC_INIT;
static CRITICAL_SECTION tf_d3d_lock;
static ID3D11Device *tf_d3d_dev;
static ID3D11DeviceContext *tf_d3d_ctx;
static tf_d3d_slot tf_d3d_slots[TF_D3D_CHANNELS];
static LARGE_INTEGER tf_d3d_qpf;

static BOOL CALLBACK tf_d3d_init_lock(PINIT_ONCE once, PVOID param, PVOID *ctx) {
  (void)once; (void)param; (void)ctx;
  InitializeCriticalSection(&tf_d3d_lock);
  QueryPerformanceFrequency(&tf_d3d_qpf);
  for (int i = 0; i < TF_D3D_CHANNELS; ++i) { tf_d3d_slots[i].published = -1; tf_d3d_slots[i].delivered = -1; }
  return TRUE;
}

static void tf_d3d_release_retired(tf_d3d_slot *s) {
  for (int i = 0; i < TF_D3D_RING; ++i) {
    if (s->retired[i]) { ID3D11Texture2D_Release(s->retired[i]); s->retired[i] = NULL; }
  }
  s->retire_left = 0;
}

// Con el lock tomado. Las texturas actuales pasan a «retiradas» (no se liberan de golpe).
static void tf_d3d_slot_free(tf_d3d_slot *s) {
  tf_d3d_release_retired(s);
  for (int i = 0; i < TF_D3D_RING; ++i) {
    s->retired[i] = s->tex[i];
    s->tex[i] = NULL; s->shared[i] = NULL;
  }
  s->retire_left = TF_D3D_RETIRE_UPLOADS;
  s->n = 0; s->w = s->h = 0;
  InterlockedExchange(&s->published, -1);
  InterlockedExchange(&s->delivered, -1);
}

// Con el lock tomado.
static int tf_d3d_ensure_device(void) {
  if (tf_d3d_dev) return 0;
  HRESULT hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, D3D11_CREATE_DEVICE_BGRA_SUPPORT, NULL, 0,
                                 D3D11_SDK_VERSION, &tf_d3d_dev, NULL, &tf_d3d_ctx);
  return FAILED(hr) ? 1 : 0;
}

// Con el lock tomado.
static int tf_d3d_ensure_texture(tf_d3d_slot *s, int32_t w, int32_t h) {
  if (s->n > 0 && s->w == w && s->h == h) return 0;
  if (s->n > 0) tf_d3d_slot_free(s);  // cambio de tamaño: anillo nuevo, el viejo queda retirado
  D3D11_TEXTURE2D_DESC d;
  ZeroMemory(&d, sizeof d);
  d.Width = (UINT)w; d.Height = (UINT)h; d.MipLevels = 1; d.ArraySize = 1;
  d.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  d.SampleDesc.Count = 1;
  d.Usage = D3D11_USAGE_DEFAULT;
  d.BindFlags = D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET;
  d.MiscFlags = D3D11_RESOURCE_MISC_SHARED;  // handle clásico (no NT): GetSharedHandle
  for (int i = 0; i < TF_D3D_RING; ++i) {
    if (FAILED(ID3D11Device_CreateTexture2D(tf_d3d_dev, &d, NULL, &s->tex[i]))) { s->tex[i] = NULL; s->n = TF_D3D_RING; tf_d3d_slot_free(s); return 2; }
    IDXGIResource *res = NULL;
    if (FAILED(ID3D11Texture2D_QueryInterface(s->tex[i], &IID_IDXGIResource, (void **)&res))) { s->n = TF_D3D_RING; tf_d3d_slot_free(s); return 3; }
    HANDLE hnd = NULL;
    HRESULT hr = IDXGIResource_GetSharedHandle(res, &hnd);
    IDXGIResource_Release(res);
    if (FAILED(hr) || hnd == NULL) { s->n = TF_D3D_RING; tf_d3d_slot_free(s); return 4; }
    s->shared[i] = hnd;
  }
  s->n = TF_D3D_RING; s->w = w; s->h = h;
  return 0;
}

// Con el lock tomado: envía lo pendiente a la GPU y espera a que un D3D11_QUERY_EVENT confirme que terminó la subida.
// Sin la espera, 2-10 % de fotogramas partidos (P9 7f). Si no se puede crear la consulta o se pasa el tope, el Flush
// ya enviado es lo único que hay.
static void tf_d3d_wait_gpu(tf_d3d_slot *s) {
  if (s->query == NULL) {
    D3D11_QUERY_DESC qd; qd.Query = D3D11_QUERY_EVENT; qd.MiscFlags = 0;
    if (FAILED(ID3D11Device_CreateQuery(tf_d3d_dev, &qd, &s->query))) s->query = NULL;
  }
  if (s->query == NULL) { ID3D11DeviceContext_Flush(tf_d3d_ctx); return; }
  LARGE_INTEGER t0, t1;
  QueryPerformanceCounter(&t0);
  ID3D11DeviceContext_End(tf_d3d_ctx, (ID3D11Asynchronous *)s->query);
  ID3D11DeviceContext_Flush(tf_d3d_ctx);
  BOOL done = FALSE;
  for (;;) {
    HRESULT hr = ID3D11DeviceContext_GetData(tf_d3d_ctx, (ID3D11Asynchronous *)s->query, &done, sizeof(BOOL), 0);
    if (hr == S_OK && done) break;
    QueryPerformanceCounter(&t1);
    if ((t1.QuadPart - t0.QuadPart) * 1000000 / tf_d3d_qpf.QuadPart > TF_D3D_WAIT_LIMIT_US) break;
    SwitchToThread();
  }
}

int32_t tf_d3d_upload(int32_t channel, const uint8_t *bgra, int32_t width, int32_t height) {
  if (channel < 0 || channel >= TF_D3D_CHANNELS || bgra == NULL || width <= 0 || height <= 0) return 1;
  InitOnceExecuteOnce(&tf_d3d_once, tf_d3d_init_lock, NULL, NULL);
  EnterCriticalSection(&tf_d3d_lock);
  int rc = tf_d3d_ensure_device();
  if (rc == 0) rc = tf_d3d_ensure_texture(&tf_d3d_slots[channel], width, height);
  if (rc == 0) {
    tf_d3d_slot *s = &tf_d3d_slots[channel];
    if (s->retire_left > 0 && --s->retire_left == 0) tf_d3d_release_retired(s);
    // Textura libre: ni la publicada ni la última entregada al motor.
    LONG pub = InterlockedCompareExchange(&s->published, 0, 0);
    LONG del = InterlockedCompareExchange(&s->delivered, 0, 0);
    int idx = 0;
    while (idx == pub || idx == del) ++idx;
    ID3D11DeviceContext_UpdateSubresource(tf_d3d_ctx, (ID3D11Resource *)s->tex[idx], 0, NULL, bgra,
                                          (UINT)width * 4, 0);
    tf_d3d_wait_gpu(s);
    InterlockedExchange(&s->published, idx);  // publicar DESPUÉS de que la GPU confirme
  }
  LeaveCriticalSection(&tf_d3d_lock);
  return rc;
}

// Hilo de raster del motor. Entrega la publicada y la marca «en manos del motor» (delivered) hasta la petición
// siguiente: FlutterDesktopGpuSurfaceDescriptor::release_callback solo avisa de que el handle YA SE ABRIÓ, no de
// que el motor haya terminado de muestrear la textura, así que no sirve para liberarla.
void *tf_d3d_handle(int32_t channel) {
  if (channel < 0 || channel >= TF_D3D_CHANNELS) return NULL;
  InitOnceExecuteOnce(&tf_d3d_once, tf_d3d_init_lock, NULL, NULL);
  EnterCriticalSection(&tf_d3d_lock);
  tf_d3d_slot *s = &tf_d3d_slots[channel];
  LONG pub = InterlockedCompareExchange(&s->published, 0, 0);
  void *h = NULL;
  if (pub >= 0 && pub < TF_D3D_RING) {
    InterlockedExchange(&s->delivered, pub);
    h = (void *)s->shared[pub];
  }
  LeaveCriticalSection(&tf_d3d_lock);
  return h;
}

void tf_d3d_release(int32_t channel) {
  if (channel < 0 || channel >= TF_D3D_CHANNELS) return;
  InitOnceExecuteOnce(&tf_d3d_once, tf_d3d_init_lock, NULL, NULL);
  EnterCriticalSection(&tf_d3d_lock);
  tf_d3d_slot_free(&tf_d3d_slots[channel]);
  tf_d3d_release_retired(&tf_d3d_slots[channel]);  // liberación explícita: sin periodo de gracia
  if (tf_d3d_slots[channel].query) { ID3D11Query_Release(tf_d3d_slots[channel].query); tf_d3d_slots[channel].query = NULL; }
  LeaveCriticalSection(&tf_d3d_lock);
}

#else
typedef int tf_d3d_unused_t;
#endif
