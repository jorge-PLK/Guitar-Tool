// P9.7f-A: textura D3D11 compartida por canal para el camino `gpu` de la textura externa en Windows.
#include "tf_core.h"

#ifdef _WIN32
#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxguid.lib")

#define TF_D3D_CHANNELS 2

typedef struct {
  ID3D11Texture2D *tex;
  HANDLE shared;
  int32_t w, h;
} tf_d3d_slot;

static INIT_ONCE tf_d3d_once = INIT_ONCE_STATIC_INIT;
static CRITICAL_SECTION tf_d3d_lock;
static ID3D11Device *tf_d3d_dev;
static ID3D11DeviceContext *tf_d3d_ctx;
static tf_d3d_slot tf_d3d_slots[TF_D3D_CHANNELS];

static BOOL CALLBACK tf_d3d_init_lock(PINIT_ONCE once, PVOID param, PVOID *ctx) {
  (void)once; (void)param; (void)ctx;
  InitializeCriticalSection(&tf_d3d_lock);
  return TRUE;
}

static void tf_d3d_slot_free(tf_d3d_slot *s) {
  if (s->tex) ID3D11Texture2D_Release(s->tex);
  s->tex = NULL; s->shared = NULL; s->w = s->h = 0;
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
  if (s->tex && s->w == w && s->h == h) return 0;
  tf_d3d_slot_free(s);
  D3D11_TEXTURE2D_DESC d;
  ZeroMemory(&d, sizeof d);
  d.Width = (UINT)w; d.Height = (UINT)h; d.MipLevels = 1; d.ArraySize = 1;
  d.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  d.SampleDesc.Count = 1;
  d.Usage = D3D11_USAGE_DEFAULT;
  d.BindFlags = D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET;
  d.MiscFlags = D3D11_RESOURCE_MISC_SHARED;  // handle clásico (no NT): GetSharedHandle
  if (FAILED(ID3D11Device_CreateTexture2D(tf_d3d_dev, &d, NULL, &s->tex))) { s->tex = NULL; return 2; }
  IDXGIResource *res = NULL;
  if (FAILED(ID3D11Texture2D_QueryInterface(s->tex, &IID_IDXGIResource, (void **)&res))) { tf_d3d_slot_free(s); return 3; }
  HANDLE hnd = NULL;
  HRESULT hr = IDXGIResource_GetSharedHandle(res, &hnd);
  IDXGIResource_Release(res);
  if (FAILED(hr) || hnd == NULL) { tf_d3d_slot_free(s); return 4; }
  s->shared = hnd; s->w = w; s->h = h;
  return 0;
}

int32_t tf_d3d_upload(int32_t channel, const uint8_t *bgra, int32_t width, int32_t height) {
  if (channel < 0 || channel >= TF_D3D_CHANNELS || bgra == NULL || width <= 0 || height <= 0) return 1;
  InitOnceExecuteOnce(&tf_d3d_once, tf_d3d_init_lock, NULL, NULL);
  EnterCriticalSection(&tf_d3d_lock);
  int rc = tf_d3d_ensure_device();
  if (rc == 0) rc = tf_d3d_ensure_texture(&tf_d3d_slots[channel], width, height);
  if (rc == 0) {
    ID3D11DeviceContext_UpdateSubresource(tf_d3d_ctx, (ID3D11Resource *)tf_d3d_slots[channel].tex, 0, NULL, bgra,
                                          (UINT)width * 4, 0);
    ID3D11DeviceContext_Flush(tf_d3d_ctx);  // el contenido debe estar enviado antes de que Flutter abra el handle
  }
  LeaveCriticalSection(&tf_d3d_lock);
  return rc;
}

void *tf_d3d_handle(int32_t channel) {
  if (channel < 0 || channel >= TF_D3D_CHANNELS) return NULL;
  InitOnceExecuteOnce(&tf_d3d_once, tf_d3d_init_lock, NULL, NULL);
  EnterCriticalSection(&tf_d3d_lock);
  void *h = (void *)tf_d3d_slots[channel].shared;
  LeaveCriticalSection(&tf_d3d_lock);
  return h;
}

int32_t tf_d3d_size(int32_t channel, int32_t *width, int32_t *height) {
  if (channel < 0 || channel >= TF_D3D_CHANNELS) return 1;
  InitOnceExecuteOnce(&tf_d3d_once, tf_d3d_init_lock, NULL, NULL);
  EnterCriticalSection(&tf_d3d_lock);
  tf_d3d_slot *s = &tf_d3d_slots[channel];
  int rc = s->tex ? 0 : 1;
  if (rc == 0) { if (width) *width = s->w; if (height) *height = s->h; }
  LeaveCriticalSection(&tf_d3d_lock);
  return rc;
}

void tf_d3d_release(int32_t channel) {
  if (channel < 0 || channel >= TF_D3D_CHANNELS) return;
  InitOnceExecuteOnce(&tf_d3d_once, tf_d3d_init_lock, NULL, NULL);
  EnterCriticalSection(&tf_d3d_lock);
  tf_d3d_slot_free(&tf_d3d_slots[channel]);
  LeaveCriticalSection(&tf_d3d_lock);
}
#else
typedef int tf_d3d_unused_t;
#endif
