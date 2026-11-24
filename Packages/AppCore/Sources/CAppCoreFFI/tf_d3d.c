// Textura D3D11 compartida por canal para el camino de textura externa en Windows (P9.7f; no se compila en Mac).
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
#define TF_D3D_RING_MAX 4  // TF_P9_RING=2..4 elige el tamaño del anillo (por defecto 3)
// Tras un cambio de tamaño, las texturas viejas se conservan este número de subidas (~1 s a 30 fps) por si el motor
// aún no ha abierto su handle: abrir un handle clásico ya liberado falla.
#define TF_D3D_RETIRE_UPLOADS 45

// P9.7k: anillo de TF_D3D_RING_MAX texturas por canal (TF_P9_RING=0: una sola, como antes de 7k).
//
// Hilos: ESCRIBE un único hilo productor por canal (tf_d3d_upload, hilo del generador); LEE el hilo de raster del
// motor (tf_d3d_handle, vía tf_frame_copy). `published` (último completo y con Flush) y `delivered` (última entregada
// al motor) son índices LONG que solo se tocan con Interlocked*. Solo el productor modifica `published`; solo
// tf_d3d_handle modifica `delivered` (= published en ese instante). El productor escribe en un índice distinto de
// ambos: como `published` no cambia bajo sus pies y `delivered` solo puede tomar el valor de `published`, el índice
// elegido sigue libre durante toda la escritura. Con 3 texturas siempre hay una libre. El lock global solo protege
// el dispositivo/contexto D3D (el contexto inmediato no es thread-safe y los dos canales lo comparten) y la
// recreación del anillo.
typedef struct {
  ID3D11Texture2D *tex[TF_D3D_RING_MAX];
  HANDLE shared[TF_D3D_RING_MAX];
  ID3D11Texture2D *retired[TF_D3D_RING_MAX];
  int32_t retire_left;
  int32_t n;                 // texturas del anillo (1 o 3); 0 = sin crear
  volatile LONG published;   // -1 = ninguna
  volatile LONG delivered;   // -1 = ninguna
  volatile LONG64 flushes;
  int32_t w, h;
  // P9 7n: espera a la GPU (TF_P9_WAIT=1) y variante de copia (TF_P9_COPY=1).
  ID3D11Query *query;
  ID3D11Texture2D *priv;     // textura privada (no compartida) desde la que se copia con CopyResource
  volatile LONG64 wait_n, wait_sum_us, wait_max_us, wait_timeouts;
} tf_d3d_slot;

static INIT_ONCE tf_d3d_once = INIT_ONCE_STATIC_INIT;
static CRITICAL_SECTION tf_d3d_lock;
static ID3D11Device *tf_d3d_dev;
static ID3D11DeviceContext *tf_d3d_ctx;
static tf_d3d_slot tf_d3d_slots[TF_D3D_CHANNELS];
static int tf_d3d_ring_n = 3;
static int tf_d3d_wait = 0;  // TF_P9_WAIT=1: publicar solo cuando un D3D11_QUERY_EVENT confirma que la GPU terminó la subida
static int tf_d3d_copy = 0;  // TF_P9_COPY=1: subir a una textura privada y CopyResource a la compartida
#define TF_D3D_WAIT_LIMIT_US 50000
static LARGE_INTEGER tf_d3d_qpf;

static BOOL CALLBACK tf_d3d_init_lock(PINIT_ONCE once, PVOID param, PVOID *ctx) {
  (void)once; (void)param; (void)ctx;
  InitializeCriticalSection(&tf_d3d_lock);
  const char *e = getenv("TF_P9_RING");
  if (e != NULL && e[0] == '0') tf_d3d_ring_n = 1;
  else if (e != NULL && e[0] >= '2' && e[0] <= '4') tf_d3d_ring_n = e[0] - '0';
  const char *w = getenv("TF_P9_WAIT");
  if (w != NULL && w[0] == '1') tf_d3d_wait = 1;
  const char *c = getenv("TF_P9_COPY");
  if (c != NULL && c[0] == '1') tf_d3d_copy = 1;
  QueryPerformanceFrequency(&tf_d3d_qpf);
  for (int i = 0; i < TF_D3D_CHANNELS; ++i) { tf_d3d_slots[i].published = -1; tf_d3d_slots[i].delivered = -1; }
  return TRUE;
}

static void tf_d3d_release_retired(tf_d3d_slot *s) {
  for (int i = 0; i < TF_D3D_RING_MAX; ++i) {
    if (s->retired[i]) { ID3D11Texture2D_Release(s->retired[i]); s->retired[i] = NULL; }
  }
  s->retire_left = 0;
}

// Con el lock tomado. Las texturas actuales pasan a «retiradas» (no se liberan de golpe).
static void tf_d3d_slot_free(tf_d3d_slot *s) {
  tf_d3d_release_retired(s);
  for (int i = 0; i < TF_D3D_RING_MAX; ++i) {
    s->retired[i] = s->tex[i];
    s->tex[i] = NULL; s->shared[i] = NULL;
  }
  s->retire_left = TF_D3D_RETIRE_UPLOADS;
  if (s->priv) { ID3D11Texture2D_Release(s->priv); s->priv = NULL; }
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
  const int count = tf_d3d_ring_n;
  for (int i = 0; i < count; ++i) {
    if (FAILED(ID3D11Device_CreateTexture2D(tf_d3d_dev, &d, NULL, &s->tex[i]))) { s->tex[i] = NULL; s->n = count; tf_d3d_slot_free(s); return 2; }
    IDXGIResource *res = NULL;
    if (FAILED(ID3D11Texture2D_QueryInterface(s->tex[i], &IID_IDXGIResource, (void **)&res))) { s->n = count; tf_d3d_slot_free(s); return 3; }
    HANDLE hnd = NULL;
    HRESULT hr = IDXGIResource_GetSharedHandle(res, &hnd);
    IDXGIResource_Release(res);
    if (FAILED(hr) || hnd == NULL) { s->n = count; tf_d3d_slot_free(s); return 4; }
    s->shared[i] = hnd;
  }
  if (tf_d3d_copy) {
    D3D11_TEXTURE2D_DESC pd = d;
    pd.MiscFlags = 0; pd.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    if (FAILED(ID3D11Device_CreateTexture2D(tf_d3d_dev, &pd, NULL, &s->priv))) { s->priv = NULL; s->n = count; tf_d3d_slot_free(s); return 5; }
  }
  s->n = count; s->w = w; s->h = h;
  return 0;
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
    // Textura libre: ni la publicada ni la última entregada al motor. Con n == 1 (TF_P9_RING=0) es siempre la 0.
    LONG pub = InterlockedCompareExchange(&s->published, 0, 0);
    LONG del = InterlockedCompareExchange(&s->delivered, 0, 0);
    int idx = 0;
    if (s->n > 1) { while (idx == pub || idx == del) ++idx; }
    if (tf_d3d_copy && s->priv) {
      ID3D11DeviceContext_UpdateSubresource(tf_d3d_ctx, (ID3D11Resource *)s->priv, 0, NULL, bgra, (UINT)width * 4, 0);
      ID3D11DeviceContext_CopyResource(tf_d3d_ctx, (ID3D11Resource *)s->tex[idx], (ID3D11Resource *)s->priv);
    } else {
      ID3D11DeviceContext_UpdateSubresource(tf_d3d_ctx, (ID3D11Resource *)s->tex[idx], 0, NULL, bgra,
                                            (UINT)width * 4, 0);
    }
    if (tf_d3d_wait) {
      if (s->query == NULL) {
        D3D11_QUERY_DESC qd; qd.Query = D3D11_QUERY_EVENT; qd.MiscFlags = 0;
        if (FAILED(ID3D11Device_CreateQuery(tf_d3d_dev, &qd, &s->query))) s->query = NULL;
      }
      if (s->query) {
        LARGE_INTEGER t0, t1;
        QueryPerformanceCounter(&t0);
        ID3D11DeviceContext_End(tf_d3d_ctx, (ID3D11Asynchronous *)s->query);
        ID3D11DeviceContext_Flush(tf_d3d_ctx);
        BOOL done = FALSE;
        int timeout = 0;
        for (;;) {
          HRESULT hr = ID3D11DeviceContext_GetData(tf_d3d_ctx, (ID3D11Asynchronous *)s->query, &done, sizeof(BOOL), 0);
          if (hr == S_OK && done) break;
          QueryPerformanceCounter(&t1);
          if ((t1.QuadPart - t0.QuadPart) * 1000000 / tf_d3d_qpf.QuadPart > TF_D3D_WAIT_LIMIT_US) { timeout = 1; break; }
          SwitchToThread();
        }
        QueryPerformanceCounter(&t1);
        LONG64 us = (t1.QuadPart - t0.QuadPart) * 1000000 / tf_d3d_qpf.QuadPart;
        InterlockedIncrement64(&s->wait_n);
        InterlockedAdd64(&s->wait_sum_us, us);
        if (us > s->wait_max_us) InterlockedExchange64(&s->wait_max_us, us);
        if (timeout) InterlockedIncrement64(&s->wait_timeouts);
      }
    } else {
      // El contenido debe estar enviado a la GPU antes de publicar el handle y de avisar al motor.
      ID3D11DeviceContext_Flush(tf_d3d_ctx);
    }
    InterlockedIncrement64(&s->flushes);
    InterlockedExchange(&s->published, idx);  // publicar DESPUÉS del Flush
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
  if (pub >= 0 && pub < TF_D3D_RING_MAX) {
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
  LeaveCriticalSection(&tf_d3d_lock);
}

#else
typedef int tf_d3d_unused_t;
#endif
