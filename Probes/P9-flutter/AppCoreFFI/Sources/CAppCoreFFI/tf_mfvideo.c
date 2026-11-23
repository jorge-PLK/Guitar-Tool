// P9 7h: reproductor de vídeo nativo de Windows para la prueba 5 (vídeo de tomas). Media Foundation IMFSourceReader
// con decodificación por hardware (MF_SOURCE_READER_D3D_MANAGER) y conversión a BGRA en la GPU
// (MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING), esclavo de un reloj `takeview.position`
// {seconds, rate, playing, epoch}: pos(t) = seconds + (t - at)*rate si playing.
//
// Tres hilos: el decodificador (MTA, dueño del lector: lee, descarta lo que ya pasó sin leerlo a CPU, salta con
// SetCurrentPosition) llena una cola de MFV_BUFFERS búferes BGRA; el presentador (cada 1 ms) aplica el bucle, pide
// saltos y sube por tf_d3d_upload el último fotograma cuyo PTS ya cubre la posición, y avisa al motor; el raster del
// motor llama a tf_mfv_copy, que devuelve el handle y mide el error A/V como VideoProbe.swift (mismas claves).
// La textura sale sin rotar; info.rotationDegrees lleva el giro que aplica Flutter (misma semántica que el Mac).
// Variables: TF_P9_VSW=1 fuerza decodificación por software (sin gestor D3D) para comparar.
#ifdef _WIN32
#include "tf_core.h"

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
// Define aquí (selectany) los GUID declarados con DEFINE_GUID en las cabeceras siguientes (atributos MF, IID de D3D11).
#include <initguid.h>
#include <d3d11_4.h>
#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfreadwrite.h>

#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxguid.lib")

#ifndef CREATE_WAITABLE_TIMER_HIGH_RESOLUTION
#define CREATE_WAITABLE_TIMER_HIGH_RESOLUTION 0x00000002
#endif

#define MFV_CHANNELS 2
#define MFV_BUFFERS 4          // cola del decodificador (BGRA a tamaño de visualización)
#define MFV_TICK_NS 1000000    // periodo del presentador
/// Medio fotograma a 30000/1001 fps (arquitectura.md, «Vídeo de tomas»): T = 1001/30000 s.
static const double kFrameDur = 1001.0 / 30000.0;
/// Diferencia reloj-decodificador que fuerza SetCurrentPosition en vez de seguir decodificando (encargo 7h: ~1 s).
static const double kFarSeconds = 1.0;
/// Redondeo de PTS a 100 ns: un fotograma cuenta como «ya toca» con este margen.
static const double kPtsEps = 0.0002;

typedef struct {
  uint8_t *px;
  double pts;  // segundos de la toma (PTS - startPts)
  int n;       // índice incrustado (-1 ilegible)
  int gen;
} mfv_frame;

typedef struct {
  double t, e, item;
  int has_e, n, epoch;
} mfv_sample;

typedef struct {
  double t;
  const char *kind;
} mfv_event;

typedef struct mfv {
  int ch;
  tf_mfv_notify_fn notify;
  WCHAR *path;
  CRITICAL_SECTION cs;   // reloj, cola, medidas
  CRITICAL_SECTION pub;  // subida + índice publicado (orden de toma: pub -> cs)
  CONDITION_VARIABLE cv;
  HANDLE dec_thread, pres_thread;
  volatile LONG stop;
  int state;  // 0 abriendo, 1 listo, 2 fallo
  char fail[384];
  char info[1024];
  double start_pts, duration;
  int w, h;  // tamaño copiado (= textura)
  int out_h;    // filas de la salida del lector (para el stride negativo)
  LONG stride;  // MF_MT_DEFAULT_STRIDE de la salida (solo camino Lock sin IMF2DBuffer)
  int force_alpha;
  // Reloj.
  double c_sec, c_at, c_rate;
  int c_play, c_epoch, applied_epoch;
  double l_start, l_end;
  int l_on;
  // Cola.
  mfv_frame buf[MFV_BUFFERS];
  int free_list[MFV_BUFFERS], n_free;
  int q[MFV_BUFFERS], q_head, q_n;
  int seek_gen, seek_noted;
  double seek_target;
  // Publicado (bajo pub).
  int pub_n;
  double pub_pts;
  int64_t pub_seq, copied_seq;
  // Medidas (bajo cs).
  double t0;
  mfv_sample *samples;
  int n_samples, cap_samples;
  mfv_event *events;
  int n_events, cap_events;
  int64_t resyncs, drift_resyncs, calls, deliveries, unreadable;
  int64_t late_drops, queued, uploads, upload_fails, seeks, seek_fails, read_fails;
  double read_sum, read_max, rb_sum, rb_max, up_sum, up_max;
  int64_t read_n, rb_n;
  HRESULT last_hr;
} mfv;

static mfv *g_mfv[MFV_CHANNELS];
static SRWLOCK g_mfv_lock = SRWLOCK_INIT;
static LARGE_INTEGER g_qpf;

static double mfv_now(void) {
  LARGE_INTEGER c;
  if (g_qpf.QuadPart == 0) QueryPerformanceFrequency(&g_qpf);
  QueryPerformanceCounter(&c);
  return (double)c.QuadPart / (double)g_qpf.QuadPart;
}

static double mfv_pos(mfv *p, double t) {  // cs tomado
  return p->c_play ? p->c_sec + (t - p->c_at) * p->c_rate : p->c_sec;
}

static void mfv_event_add(mfv *p, double now, const char *kind) {  // cs tomado
  if (p->n_events == p->cap_events) {
    int cap = p->cap_events ? p->cap_events * 2 : 64;
    mfv_event *x = (mfv_event *)realloc(p->events, sizeof(mfv_event) * (size_t)cap);
    if (!x) return;
    p->events = x; p->cap_events = cap;
  }
  p->events[p->n_events].t = now - p->t0;
  p->events[p->n_events].kind = kind;
  p->n_events++;
}

static void mfv_free_buf(mfv *p, int b) {  // cs tomado
  p->free_list[p->n_free++] = b;
}

/// Salto: vacía la cola y pide al decodificador SetCurrentPosition a la posición actual del reloj. cs tomado.
static void mfv_request_seek(mfv *p, double now, const char *kind, int drift) {
  p->seek_gen++;
  p->seek_target = mfv_pos(p, now);
  p->applied_epoch = p->c_epoch;
  while (p->q_n > 0) {
    mfv_free_buf(p, p->q[p->q_head]);
    p->q_head = (p->q_head + 1) % MFV_BUFFERS;
    p->q_n--;
  }
  p->seek_noted = 0;
  p->resyncs++;
  if (drift) p->drift_resyncs++;
  mfv_event_add(p, now, kind);
  WakeAllConditionVariable(&p->cv);
}

/// Índice de fotograma de los vídeos de prueba (igual que VideoProbe.frameIndex): 12 bloques de 64x64 arriba a la
/// izquierda; referencias en los bloques 12 (blanco) y 13 (negro). Canal G de la fila 32, centro de cada bloque.
static int mfv_index(const uint8_t *px, int w, int h) {
  if (w < 896 || h < 64) return -1;
  const size_t row = (size_t)32 * (size_t)w * 4;
#define MFV_G(k) ((int)px[row + (size_t)(64 * (k) + 32) * 4 + 1])
  int wv = MFV_G(12), bv = MFV_G(13);
  if (wv - bv <= 100) return -1;
  int thr = (wv + bv) / 2, n = 0;
  for (int k = 0; k < 12; k++)
    if (MFV_G(k) > thr) n |= 1 << k;
#undef MFV_G
  return n;
}

/// Copia el fotograma de la muestra a dst (BGRA compacto w x h). 0 bien.
static int mfv_readback(mfv *p, IMFSample *s, uint8_t *dst) {
  IMFMediaBuffer *mb = NULL;
  if (FAILED(IMFSample_GetBufferByIndex(s, 0, &mb))) return 1;
  int rc = 1;
  IMF2DBuffer *b2 = NULL;
  BYTE *scan0 = NULL;
  LONG pitch = 0;
  DWORD len = 0;
  int locked2d = 0, locked = 0;
  if (SUCCEEDED(IMFMediaBuffer_QueryInterface(mb, &IID_IMF2DBuffer, (void **)&b2)) &&
      SUCCEEDED(IMF2DBuffer_Lock2D(b2, &scan0, &pitch))) {
    locked2d = 1;
  } else if (SUCCEEDED(IMFMediaBuffer_Lock(mb, &scan0, NULL, &len))) {
    locked = 1;
    // Búfer contiguo: filas de la salida del lector (out_w, no el recorte), con el signo de MF_MT_DEFAULT_STRIDE
    // (negativo = de abajo arriba: la fila superior es la última en memoria).
    pitch = p->stride;
    LONG ap = pitch < 0 ? -pitch : pitch;
    if (ap < p->w * 4 || (size_t)len < (size_t)ap * (size_t)(p->h - 1) + (size_t)p->w * 4) {
      IMFMediaBuffer_Unlock(mb);
      locked = 0;
    } else if (pitch < 0) {
      scan0 += (size_t)ap * (size_t)(p->out_h - 1);
    }
  }
  if (locked2d || locked) {
    const size_t rowb = (size_t)p->w * 4;
    for (int y = 0; y < p->h; y++) {
      uint8_t *d = dst + (size_t)y * rowb;
      memcpy(d, scan0 + (ptrdiff_t)y * pitch, rowb);
      if (p->force_alpha) {
        uint32_t *u = (uint32_t *)d;
        for (int x = 0; x < p->w; x++) u[x] |= 0xFF000000u;
      }
    }
    rc = 0;
  }
  if (locked2d) IMF2DBuffer_Unlock2D(b2);
  if (locked) IMFMediaBuffer_Unlock(mb);
  if (b2) IMF2DBuffer_Release(b2);
  IMFMediaBuffer_Release(mb);
  return rc;
}

/// Una muestra decodificada de la generación `gen`: se descarta si ya pasó (sin leerla a CPU), se pide salto si el
/// reloj va > kFarSeconds por delante, y si no se lee a un búfer libre y se encola.
static void mfv_take_sample(mfv *p, IMFSample *s, LONGLONG ts, int gen) {
  double pts = (double)ts / 1e7 - p->start_pts;
  double now = mfv_now();
  EnterCriticalSection(&p->cs);
  int stale = p->seek_gen != gen;
  double pos = mfv_pos(p, now);
  int late = !stale && pts + kFrameDur <= pos;
  // Tras un salto, MF entrega desde el fotograma clave anterior: lo previo al objetivo se descarta sin pedir otro
  // salto (si no, con GOP > kFarSeconds se saltaría en bucle). Solo hay deriva si esta generación ya alcanzó el reloj.
  if (late && p->seek_noted && pts + kFarSeconds < pos) {
    mfv_request_seek(p, now, "drift", 1);
    stale = 1;
  }
  int b = -1;
  if (late && !stale) p->late_drops++;
  if (!stale && !late && p->n_free > 0) b = p->free_list[--p->n_free];
  LeaveCriticalSection(&p->cs);
  if (b < 0) return;
  double r0 = mfv_now();
  int rc = mfv_readback(p, s, p->buf[b].px);
  double rb = (mfv_now() - r0) * 1000;
  int n = rc == 0 ? mfv_index(p->buf[b].px, p->w, p->h) : -1;
  EnterCriticalSection(&p->cs);
  p->rb_n++; p->rb_sum += rb;
  if (rb > p->rb_max) p->rb_max = rb;
  if (rc != 0 || p->seek_gen != gen) {
    mfv_free_buf(p, b);
  } else {
    p->buf[b].pts = pts; p->buf[b].n = n; p->buf[b].gen = gen;
    p->q[(p->q_head + p->q_n) % MFV_BUFFERS] = b;
    p->q_n++;
    p->queued++;
    if (!p->seek_noted) { p->seek_noted = 1; mfv_event_add(p, mfv_now(), "seekDone"); }
  }
  LeaveCriticalSection(&p->cs);
}

static void mfv_fail(mfv *p, const char *what, HRESULT hr) {
  EnterCriticalSection(&p->cs);
  snprintf(p->fail, sizeof p->fail, "%s hr=0x%08lX", what, (unsigned long)hr);
  p->state = 2;
  LeaveCriticalSection(&p->cs);
}

/// Nombre del decodificador que eligió el lector (IMFSourceReaderEx), o "?".
static void mfv_decoder_name(IMFSourceReader *r, char *out, size_t cap, int *hw_mft) {
  snprintf(out, cap, "?");
  *hw_mft = 0;
  IMFSourceReaderEx *rx = NULL;
  if (FAILED(IMFSourceReader_QueryInterface(r, &IID_IMFSourceReaderEx, (void **)&rx))) return;
  for (DWORD i = 0; i < 8; i++) {
    GUID cat;
    IMFTransform *t = NULL;
    if (FAILED(IMFSourceReaderEx_GetTransformForStream(rx, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, i, &cat, &t)))
      break;
    if (IsEqualGUID(&cat, &MFT_CATEGORY_VIDEO_DECODER)) {
      IMFAttributes *a = NULL;
      if (SUCCEEDED(IMFTransform_GetAttributes(t, &a)) && a) {
        WCHAR *name = NULL;
        UINT32 nlen = 0;
        if (SUCCEEDED(IMFAttributes_GetAllocatedString(a, &MFT_FRIENDLY_NAME_Attribute, &name, &nlen))) {
          WideCharToMultiByte(CP_UTF8, 0, name, -1, out, (int)cap, NULL, NULL);
          CoTaskMemFree(name);
        } else {
          GUID clsid;
          if (SUCCEEDED(IMFAttributes_GetGUID(a, &MFT_TRANSFORM_CLSID_Attribute, &clsid)))
            snprintf(out, cap, "clsid {%08lX-%04X-%04X}", (unsigned long)clsid.Data1, clsid.Data2, clsid.Data3);
          else
            snprintf(out, cap, "decoder sin nombre");
        }
        UINT32 len = 0;
        if (SUCCEEDED(IMFAttributes_GetStringLength(a, &MFT_ENUM_HARDWARE_URL_Attribute, &len))) *hw_mft = 1;
        IMFAttributes_Release(a);
      }
    }
    IMFTransform_Release(t);
  }
  IMFSourceReaderEx_Release(rx);
}

typedef struct {
  IMFSourceReader *reader;
  IMFDXGIDeviceManager *mgr;
  ID3D11Device *dev;
  int out_w, out_h, argb;
  LONG stride;
  HRESULT d3d_hr;  // fallo del camino D3D (S_OK si se usó)
  int used_d3d;
} mfv_open_res;

static void mfv_open_release(mfv_open_res *o) {
  if (o->reader) IMFSourceReader_Release(o->reader);
  if (o->mgr) IMFDXGIDeviceManager_Release(o->mgr);
  if (o->dev) ID3D11Device_Release(o->dev);
  o->reader = NULL; o->mgr = NULL; o->dev = NULL;
}

/// Crea el lector (con o sin gestor D3D) y fija la salida ARGB32 (o RGB32). Deja en *what el paso que falló.
static HRESULT mfv_try_open(mfv *p, int use_d3d, mfv_open_res *o, const char **what) {
  HRESULT hr = S_OK;
  IMFAttributes *a = NULL;
  IMFMediaType *ot = NULL, *cur = NULL;
  if (use_d3d) {
    *what = "D3D11CreateDevice(VIDEO_SUPPORT)";
    hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL,
                           D3D11_CREATE_DEVICE_VIDEO_SUPPORT | D3D11_CREATE_DEVICE_BGRA_SUPPORT, NULL, 0,
                           D3D11_SDK_VERSION, &o->dev, NULL, NULL);
    if (FAILED(hr)) goto done;
    ID3D11Multithread *mt = NULL;
    if (SUCCEEDED(ID3D11Device_QueryInterface(o->dev, &IID_ID3D11Multithread, (void **)&mt))) {
      ID3D11Multithread_SetMultithreadProtected(mt, TRUE);
      ID3D11Multithread_Release(mt);
    }
    UINT token = 0;
    *what = "MFCreateDXGIDeviceManager";
    hr = MFCreateDXGIDeviceManager(&token, &o->mgr);
    if (FAILED(hr)) goto done;
    hr = IMFDXGIDeviceManager_ResetDevice(o->mgr, (IUnknown *)o->dev, token);
    if (FAILED(hr)) goto done;
  }
  *what = "MFCreateAttributes";
  hr = MFCreateAttributes(&a, 3);
  if (FAILED(hr)) goto done;
  IMFAttributes_SetUINT32(a, &MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE);
  IMFAttributes_SetUINT32(a, &MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING, TRUE);
  if (use_d3d) IMFAttributes_SetUnknown(a, &MF_SOURCE_READER_D3D_MANAGER, (IUnknown *)o->mgr);
  *what = "MFCreateSourceReaderFromURL";
  hr = MFCreateSourceReaderFromURL(p->path, a, &o->reader);
  if (FAILED(hr)) goto done;
  IMFSourceReader_SetStreamSelection(o->reader, (DWORD)MF_SOURCE_READER_ALL_STREAMS, FALSE);
  *what = "SetStreamSelection(video)";
  hr = IMFSourceReader_SetStreamSelection(o->reader, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, TRUE);
  if (FAILED(hr)) goto done;
  *what = "MFCreateMediaType";
  hr = MFCreateMediaType(&ot);
  if (FAILED(hr)) goto done;
  IMFMediaType_SetGUID(ot, &MF_MT_MAJOR_TYPE, &MFMediaType_Video);
  IMFMediaType_SetGUID(ot, &MF_MT_SUBTYPE, &MFVideoFormat_ARGB32);
  *what = "SetCurrentMediaType(ARGB32/RGB32)";
  hr = IMFSourceReader_SetCurrentMediaType(o->reader, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, NULL, ot);
  o->argb = SUCCEEDED(hr);
  if (FAILED(hr)) {
    IMFMediaType_SetGUID(ot, &MF_MT_SUBTYPE, &MFVideoFormat_RGB32);
    hr = IMFSourceReader_SetCurrentMediaType(o->reader, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, NULL, ot);
    if (FAILED(hr)) goto done;
  }
  *what = "GetCurrentMediaType";
  hr = IMFSourceReader_GetCurrentMediaType(o->reader, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, &cur);
  if (FAILED(hr)) goto done;
  UINT64 fs = 0;
  IMFMediaType_GetUINT64(cur, &MF_MT_FRAME_SIZE, &fs);
  o->out_w = (int)(fs >> 32); o->out_h = (int)(fs & 0xFFFFFFFFu);
  UINT32 st32 = 0;
  if (SUCCEEDED(IMFMediaType_GetUINT32(cur, &MF_MT_DEFAULT_STRIDE, &st32))) {
    o->stride = (LONG)(INT32)st32;
  } else {
    GUID osub = GUID_NULL;
    IMFMediaType_GetGUID(cur, &MF_MT_SUBTYPE, &osub);
    if (FAILED(MFGetStrideForBitmapInfoHeader(osub.Data1, (DWORD)o->out_w, &o->stride))) o->stride = o->out_w * 4;
  }
  o->used_d3d = use_d3d;
done:
  if (a) IMFAttributes_Release(a);
  if (ot) IMFMediaType_Release(ot);
  if (cur) IMFMediaType_Release(cur);
  if (FAILED(hr)) mfv_open_release(o);
  return hr;
}

static DWORD WINAPI mfv_present(void *arg);

static DWORD WINAPI mfv_decode(void *arg) {
  mfv *p = (mfv *)arg;
  HRESULT hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
  int co = SUCCEEDED(hr);
  hr = MFStartup(MF_VERSION, MFSTARTUP_FULL);
  if (FAILED(hr)) { mfv_fail(p, "MFStartup", hr); goto out_co; }
  double t_open = mfv_now();
  mfv_open_res o;
  memset(&o, 0, sizeof o);
  const char *what = "";
  const char *sw = getenv("TF_P9_VSW");
  int try_d3d = !(sw && sw[0] == '1');
  o.d3d_hr = S_OK;
  char d3d_fail[160] = "";
  if (try_d3d) {
    hr = mfv_try_open(p, 1, &o, &what);
    if (FAILED(hr)) {
      snprintf(d3d_fail, sizeof d3d_fail, "%s hr=0x%08lX", what, (unsigned long)hr);
      o.d3d_hr = hr;
    }
  }
  if (!o.reader) {
    hr = mfv_try_open(p, 0, &o, &what);
    if (FAILED(hr)) {
      char m[256];
      snprintf(m, sizeof m, "%s (d3d: %s)", what, d3d_fail[0] ? d3d_fail : "no intentado");
      mfv_fail(p, m, hr);
      goto out_mf;
    }
  }
  IMFSourceReader *r = o.reader;

  // Tipo nativo: códec, tamaño, fps, rotación, apertura.
  IMFMediaType *nt = NULL;
  GUID sub = GUID_NULL;
  UINT64 fs = 0, fr = 0;
  UINT32 rot = 0;
  int nw = 0, nh = 0, dw = 0, dh = 0;
  if (SUCCEEDED(IMFSourceReader_GetNativeMediaType(r, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, &nt))) {
    IMFMediaType_GetGUID(nt, &MF_MT_SUBTYPE, &sub);
    IMFMediaType_GetUINT64(nt, &MF_MT_FRAME_SIZE, &fs);
    IMFMediaType_GetUINT64(nt, &MF_MT_FRAME_RATE, &fr);
    IMFMediaType_GetUINT32(nt, &MF_MT_VIDEO_ROTATION, &rot);
    MFVideoArea area;
    UINT32 asz = 0;
    if (SUCCEEDED(IMFMediaType_GetBlob(nt, &MF_MT_MINIMUM_DISPLAY_APERTURE, (UINT8 *)&area, sizeof area, &asz)) &&
        asz == sizeof area) {
      dw = (int)area.Area.cx; dh = (int)area.Area.cy;
    }
    IMFMediaType_Release(nt);
  }
  nw = (int)(fs >> 32); nh = (int)(fs & 0xFFFFFFFFu);
  if (dw <= 0 || dh <= 0) { dw = nw; dh = nh; }
  // El lector no gira: si la salida viniera ya girada (dimensiones cruzadas), no se pide giro a Flutter.
  int mf_rotated = (rot == 90 || rot == 270) && o.out_w == nh && o.out_h == nw && nw != nh;
  int cw = mf_rotated ? dh : dw, chh = mf_rotated ? dw : dh;
  if (cw > o.out_w) cw = o.out_w;
  if (chh > o.out_h) chh = o.out_h;
  double fps = (fr & 0xFFFFFFFFu) ? (double)(fr >> 32) / (double)(fr & 0xFFFFFFFFu) : 0;
  PROPVARIANT pv;
  PropVariantInit(&pv);
  double dur = 0;
  if (SUCCEEDED(IMFSourceReader_GetPresentationAttribute(r, (DWORD)MF_SOURCE_READER_MEDIASOURCE, &MF_PD_DURATION, &pv)))
    dur = (double)pv.uhVal.QuadPart / 1e7;
  PropVariantClear(&pv);

  // Primera muestra: fija startPts (como el Mac: el reloj de la toma empieza en el primer fotograma mostrado).
  DWORD si = 0, fl = 0;
  LONGLONG ts = 0;
  IMFSample *s0 = NULL;
  hr = IMFSourceReader_ReadSample(r, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, &si, &fl, &ts, &s0);
  if (FAILED(hr) || !s0) {
    mfv_fail(p, FAILED(hr) ? "ReadSample(primera)" : "ReadSample(primera) sin muestra", FAILED(hr) ? hr : (HRESULT)fl);
    if (s0) IMFSample_Release(s0);
    mfv_open_release(&o);
    goto out_mf;
  }
  int d3d_out = 0;
  {
    IMFMediaBuffer *mb = NULL;
    if (SUCCEEDED(IMFSample_GetBufferByIndex(s0, 0, &mb))) {
      IMFDXGIBuffer *db = NULL;
      if (SUCCEEDED(IMFMediaBuffer_QueryInterface(mb, &IID_IMFDXGIBuffer, (void **)&db))) { d3d_out = 1; IMFDXGIBuffer_Release(db); }
      IMFMediaBuffer_Release(mb);
    }
  }
  char dec[128];
  int hw_mft = 0;
  mfv_decoder_name(r, dec, sizeof dec, &hw_mft);
  for (char *c = dec; *c; c++) if (*c == '"' || *c == '\\') *c = '\'';

  int ok = 1;
  for (int i = 0; i < MFV_BUFFERS && ok; i++) {
    p->buf[i].px = (uint8_t *)malloc((size_t)cw * (size_t)chh * 4);
    if (!p->buf[i].px) ok = 0;
  }
  if (!ok || cw <= 0 || chh <= 0) {
    mfv_fail(p, "tamaño o memoria", E_OUTOFMEMORY);
    IMFSample_Release(s0);
    mfv_open_release(&o);
    goto out_mf;
  }
  // Giro que aplica Flutter en el sentido de VideoProbe.swift (RotatedBox, horario). MF_MT_VIDEO_ROTATION es
  // antihorario: el giro de visualización horario equivalente es (360 - rot) % 360.
  int flutter_rot = mf_rotated ? 0 : (int)((360 - (rot % 360)) % 360);
  int swap = flutter_rot == 90 || flutter_rot == 270;
  const char *codec = IsEqualGUID(&sub, &MFVideoFormat_HEVC) ? "hevc" : IsEqualGUID(&sub, &MFVideoFormat_H264) ? "h264" : "otro";

  EnterCriticalSection(&p->cs);
  if (p->stop) {
    LeaveCriticalSection(&p->cs);
    IMFSample_Release(s0);
    mfv_open_release(&o);
    goto out_mf;
  }
  p->w = cw; p->h = chh;
  p->out_h = o.out_h; p->stride = o.stride;
  p->force_alpha = 1;  // RGB32 trae X indefinido; ARGB32 del procesador de vídeo también se fuerza (coste medido en rb)
  p->start_pts = (double)ts / 1e7;
  p->duration = dur - p->start_pts;
  for (int i = 0; i < MFV_BUFFERS; i++) p->free_list[i] = i;
  p->n_free = MFV_BUFFERS;
  snprintf(p->info, sizeof p->info,
           "{\"width\":%d,\"height\":%d,\"displayWidth\":%d,\"displayHeight\":%d,\"rotationDegrees\":%d,\"fps\":%.4f,"
           "\"duration\":%.4f,\"startPts\":%.4f,\"hardwareDecode\":%s,\"engine\":\"mf-sourcereader\",\"codec\":\"%s\","
           "\"mfRotation\":%u,\"mfRotatedOutput\":%s,\"nativeSize\":[%d,%d],\"readerOutput\":[%d,%d],\"outFormat\":\"%s\","
           "\"d3dManager\":%s,\"d3dFail\":\"%s\",\"d3dOutputSamples\":%s,\"decoder\":\"%s\",\"decoderHardwareUrl\":%s,"
           "\"openMsNative\":%.1f}",
           cw, chh, swap ? chh : cw, swap ? cw : chh, flutter_rot, fps, p->duration, p->start_pts,
           (o.used_d3d && d3d_out) ? "true" : "false", codec, (unsigned)rot, mf_rotated ? "true" : "false", nw, nh,
           o.out_w, o.out_h, o.argb ? "ARGB32" : "RGB32", o.used_d3d ? "true" : "false", d3d_fail,
           d3d_out ? "true" : "false", dec, hw_mft ? "true" : "false", (mfv_now() - t_open) * 1000);
  LeaveCriticalSection(&p->cs);
  mfv_take_sample(p, s0, ts, 0);
  IMFSample_Release(s0);

  EnterCriticalSection(&p->cs);
  p->state = 1;
  mfv_event_add(p, mfv_now(), "open");
  p->resyncs++;
  LeaveCriticalSection(&p->cs);
  p->pres_thread = CreateThread(NULL, 0, mfv_present, p, 0, NULL);

  int gen = 0, eos = 0;
  for (;;) {
    EnterCriticalSection(&p->cs);
    while (!p->stop && p->seek_gen == gen && (eos || p->n_free == 0))
      SleepConditionVariableCS(&p->cv, &p->cs, 100);
    if (p->stop) { LeaveCriticalSection(&p->cs); break; }
    if (p->seek_gen != gen) {
      gen = p->seek_gen;
      double tgt = p->seek_target < 0 ? 0 : p->seek_target;
      LeaveCriticalSection(&p->cs);
      PROPVARIANT v;
      PropVariantInit(&v);
      v.vt = VT_I8;
      v.hVal.QuadPart = (LONGLONG)((tgt + p->start_pts) * 1e7);
      hr = IMFSourceReader_SetCurrentPosition(r, &GUID_NULL, &v);
      EnterCriticalSection(&p->cs);
      p->seeks++;
      if (FAILED(hr)) { p->seek_fails++; p->last_hr = hr; }
      LeaveCriticalSection(&p->cs);
      eos = 0;
      continue;
    }
    LeaveCriticalSection(&p->cs);
    IMFSample *s = NULL;
    double d0 = mfv_now();
    hr = IMFSourceReader_ReadSample(r, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, &si, &fl, &ts, &s);
    double dm = (mfv_now() - d0) * 1000;
    EnterCriticalSection(&p->cs);
    p->read_n++; p->read_sum += dm;
    if (dm > p->read_max) p->read_max = dm;
    if (FAILED(hr)) { p->read_fails++; p->last_hr = hr; }
    LeaveCriticalSection(&p->cs);
    if (FAILED(hr) || (fl & MF_SOURCE_READERF_ENDOFSTREAM)) {
      eos = 1;
      if (s) IMFSample_Release(s);
      continue;
    }
    if (!s) continue;
    mfv_take_sample(p, s, ts, gen);
    IMFSample_Release(s);
  }
  if (p->pres_thread) {
    WaitForSingleObject(p->pres_thread, INFINITE);
    CloseHandle(p->pres_thread);
    p->pres_thread = NULL;
  }
  mfv_open_release(&o);
out_mf:
  MFShutdown();
out_co:
  if (co) CoUninitialize();
  return 0;
}

static DWORD WINAPI mfv_present(void *arg) {
  mfv *p = (mfv *)arg;
  HANDLE timer = CreateWaitableTimerExW(NULL, NULL, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS);
  if (!timer) timer = CreateWaitableTimerExW(NULL, NULL, 0, TIMER_ALL_ACCESS);
  SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_ABOVE_NORMAL);
  while (!p->stop) {
    double now = mfv_now();
    int pick = -1;
    EnterCriticalSection(&p->cs);
    // Bucle: el reloj vuelve a start al llegar a end (salto con epoch), como VideoProbe.tick.
    if (p->l_on && p->c_play && mfv_pos(p, now) >= p->l_end) {
      p->c_sec = p->l_start; p->c_at = now; p->c_epoch++;
    }
    if (p->c_epoch != p->applied_epoch) mfv_request_seek(p, now, "clock", 0);
    double pos = mfv_pos(p, now);
    while (p->q_n > 0) {
      int b = p->q[p->q_head];
      mfv_frame *f = &p->buf[b];
      if (f->gen != p->seek_gen) {
        p->q_head = (p->q_head + 1) % MFV_BUFFERS; p->q_n--;
        mfv_free_buf(p, b);
        continue;
      }
      if (f->pts > pos + kPtsEps) {
        if (f->pts > pos + kFarSeconds) mfv_request_seek(p, now, "drift", 1);  // reloj > 1 s por detrás de la cola
        break;
      }
      p->q_head = (p->q_head + 1) % MFV_BUFFERS; p->q_n--;
      if (pick >= 0) mfv_free_buf(p, pick);
      pick = b;
    }
    if (pick >= 0) WakeAllConditionVariable(&p->cv);
    LeaveCriticalSection(&p->cs);
    if (pick >= 0) {
      mfv_frame *f = &p->buf[pick];
      double u0 = mfv_now();
      EnterCriticalSection(&p->pub);
      int rc = tf_d3d_upload(p->ch, f->px, p->w, p->h);
      if (rc == 0) { p->pub_n = f->n; p->pub_pts = f->pts; p->pub_seq++; }
      LeaveCriticalSection(&p->pub);
      double um = (mfv_now() - u0) * 1000;
      EnterCriticalSection(&p->cs);
      if (rc == 0) p->uploads++; else p->upload_fails++;
      p->up_sum += um;
      if (um > p->up_max) p->up_max = um;
      mfv_free_buf(p, pick);
      WakeAllConditionVariable(&p->cv);
      LeaveCriticalSection(&p->cs);
      if (rc == 0 && p->notify) p->notify(p->ch);
    }
    if (timer) {
      LARGE_INTEGER due;
      due.QuadPart = -(LONGLONG)(MFV_TICK_NS / 100);
      if (SetWaitableTimer(timer, &due, 0, NULL, NULL, FALSE)) WaitForSingleObject(timer, 20);
      else Sleep(1);
    } else {
      Sleep(1);
    }
  }
  if (timer) CloseHandle(timer);
  return 0;
}

// MARK: API

static mfv *mfv_get_locked(int32_t ch) {  // g_mfv_lock compartido tomado
  return (ch >= 0 && ch < MFV_CHANNELS) ? g_mfv[ch] : NULL;
}

static void mfv_destroy(mfv *p) {
  if (!p) return;
  EnterCriticalSection(&p->cs);
  InterlockedExchange(&p->stop, 1);
  WakeAllConditionVariable(&p->cv);
  LeaveCriticalSection(&p->cs);
  if (p->dec_thread) {
    WaitForSingleObject(p->dec_thread, INFINITE);
    CloseHandle(p->dec_thread);
  }
  for (int i = 0; i < MFV_BUFFERS; i++) free(p->buf[i].px);
  free(p->samples);
  free(p->events);
  free(p->path);
  DeleteCriticalSection(&p->cs);
  DeleteCriticalSection(&p->pub);
  free(p);
}

int32_t tf_mfv_open(int32_t channel, const char *utf8Path, tf_mfv_notify_fn notify) {
  if (channel < 0 || channel >= MFV_CHANNELS || !utf8Path) return 1;
  int wn = MultiByteToWideChar(CP_UTF8, 0, utf8Path, -1, NULL, 0);
  if (wn <= 0) return 1;
  mfv *p = (mfv *)calloc(1, sizeof(mfv));
  if (!p) return 1;
  p->path = (WCHAR *)malloc(sizeof(WCHAR) * (size_t)wn);
  if (!p->path) { free(p); return 1; }
  MultiByteToWideChar(CP_UTF8, 0, utf8Path, -1, p->path, wn);
  p->ch = channel;
  p->notify = notify;
  p->c_rate = 1.0;
  p->t0 = mfv_now();
  p->pub_n = -1;
  InitializeCriticalSection(&p->cs);
  InitializeCriticalSection(&p->pub);
  InitializeConditionVariable(&p->cv);
  AcquireSRWLockExclusive(&g_mfv_lock);
  mfv *old = g_mfv[channel];
  g_mfv[channel] = p;
  ReleaseSRWLockExclusive(&g_mfv_lock);
  mfv_destroy(old);
  // Apertura asíncrona: el hilo decodificador abre y avisa con state.
  p->dec_thread = CreateThread(NULL, 0, mfv_decode, p, 0, NULL);
  if (!p->dec_thread) mfv_fail(p, "CreateThread", HRESULT_FROM_WIN32(GetLastError()));
  return 0;
}

int32_t tf_mfv_state(int32_t channel) {
  AcquireSRWLockShared(&g_mfv_lock);
  mfv *p = mfv_get_locked(channel);
  int32_t st = -1;
  if (p) { EnterCriticalSection(&p->cs); st = p->state; LeaveCriticalSection(&p->cs); }
  ReleaseSRWLockShared(&g_mfv_lock);
  return st;
}

void tf_mfv_close(int32_t channel) {
  if (channel < 0 || channel >= MFV_CHANNELS) return;
  AcquireSRWLockExclusive(&g_mfv_lock);
  mfv *p = g_mfv[channel];
  g_mfv[channel] = NULL;
  ReleaseSRWLockExclusive(&g_mfv_lock);
  mfv_destroy(p);
}

void tf_mfv_clock(int32_t channel, double seconds, double rate, int32_t playing, int32_t epochJump) {
  AcquireSRWLockShared(&g_mfv_lock);
  mfv *p = mfv_get_locked(channel);
  if (p) {
    EnterCriticalSection(&p->cs);
    p->c_sec = seconds; p->c_at = mfv_now(); p->c_rate = rate; p->c_play = playing != 0;
    if (epochJump) p->c_epoch++;  // el presentador lo aplica en su próximo tick (≤ 1 ms)
    LeaveCriticalSection(&p->cs);
  }
  ReleaseSRWLockShared(&g_mfv_lock);
}

void tf_mfv_loop(int32_t channel, double start, double end, int32_t enabled) {
  AcquireSRWLockShared(&g_mfv_lock);
  mfv *p = mfv_get_locked(channel);
  if (p) {
    EnterCriticalSection(&p->cs);
    p->l_start = start; p->l_end = end; p->l_on = enabled != 0;
    LeaveCriticalSection(&p->cs);
  }
  ReleaseSRWLockShared(&g_mfv_lock);
}

char *tf_mfv_info(int32_t channel) {
  AcquireSRWLockShared(&g_mfv_lock);
  mfv *p = mfv_get_locked(channel);
  char *out = NULL;
  if (p) {
    EnterCriticalSection(&p->cs);
    if (p->state == 1) {
      out = _strdup(p->info);
    } else if (p->state == 2) {
      char tmp[512];
      for (char *c = p->fail; *c; c++) if (*c == '"' || *c == '\\') *c = '\'';
      snprintf(tmp, sizeof tmp, "{\"error\":\"%s\"}", p->fail);
      out = _strdup(tmp);
    }
    LeaveCriticalSection(&p->cs);
  }
  ReleaseSRWLockShared(&g_mfv_lock);
  return out;
}

typedef struct {
  char *s;
  size_t n, cap;
} mfv_sb;

static void sb_printf(mfv_sb *b, const char *fmt, ...) {
  va_list ap;
  for (;;) {
    size_t room = b->cap - b->n;
    va_start(ap, fmt);
    int k = b->s ? vsnprintf(b->s + b->n, room, fmt, ap) : -1;
    va_end(ap);
    if (k >= 0 && (size_t)k < room) { b->n += (size_t)k; return; }
    size_t cap = b->cap ? b->cap * 2 : 4096;
    while (k >= 0 && cap - b->n <= (size_t)k) cap *= 2;
    char *x = (char *)realloc(b->s, cap);
    if (!x) return;
    b->s = x; b->cap = cap;
  }
}

char *tf_mfv_stats(int32_t channel, int32_t reset) {
  AcquireSRWLockShared(&g_mfv_lock);
  mfv *p = mfv_get_locked(channel);
  if (!p) { ReleaseSRWLockShared(&g_mfv_lock); return NULL; }
  mfv_sb b = {0};
  EnterCriticalSection(&p->cs);
  sb_printf(&b, "{\"resyncs\":%lld,\"driftResyncs\":%lld,\"calls\":%lld,\"deliveries\":%lld,\"unreadable\":%lld,\"samples\":[",
            (long long)p->resyncs, (long long)p->drift_resyncs, (long long)p->calls, (long long)p->deliveries,
            (long long)p->unreadable);
  for (int i = 0; i < p->n_samples; i++) {
    mfv_sample *x = &p->samples[i];
    if (x->has_e)
      sb_printf(&b, "%s[%.2f,%.2f,%d,%.4f,%d]", i ? "," : "", x->t * 1000, x->e * 1000, x->n, x->item, x->epoch);
    else
      sb_printf(&b, "%s[%.2f,null,%d,%.4f,%d]", i ? "," : "", x->t * 1000, x->n, x->item, x->epoch);
  }
  sb_printf(&b, "],\"events\":[");
  for (int i = 0; i < p->n_events; i++)
    sb_printf(&b, "%s[%.2f,\"%s\"]", i ? "," : "", p->events[i].t * 1000, p->events[i].kind);
  sb_printf(&b, "],\"win\":{\"lateDrops\":%lld,\"queued\":%lld,\"uploads\":%lld,\"uploadFails\":%lld,\"seeks\":%lld,"
                "\"seekFails\":%lld,\"readFails\":%lld,\"lastHr\":\"0x%08lX\",\"readMsAvg\":%.3f,\"readMsMax\":%.3f,"
                "\"readbackMsAvg\":%.3f,\"readbackMsMax\":%.3f,\"uploadMsAvg\":%.3f,\"uploadMsMax\":%.3f}}",
            (long long)p->late_drops, (long long)p->queued, (long long)p->uploads, (long long)p->upload_fails,
            (long long)p->seeks, (long long)p->seek_fails, (long long)p->read_fails, (unsigned long)p->last_hr,
            p->read_n ? p->read_sum / (double)p->read_n : 0, p->read_max, p->rb_n ? p->rb_sum / (double)p->rb_n : 0,
            p->rb_max, p->uploads ? p->up_sum / (double)p->uploads : 0, p->up_max);
  if (reset) {
    p->n_samples = 0; p->n_events = 0;
    p->resyncs = p->drift_resyncs = p->calls = p->deliveries = p->unreadable = 0;
    p->late_drops = p->queued = p->uploads = p->upload_fails = p->seeks = p->seek_fails = p->read_fails = 0;
    p->read_sum = p->read_max = p->rb_sum = p->rb_max = p->up_sum = p->up_max = 0;
    p->read_n = p->rb_n = 0;
    p->t0 = mfv_now();
  }
  LeaveCriticalSection(&p->cs);
  ReleaseSRWLockShared(&g_mfv_lock);
  return b.s;
}

void *tf_mfv_copy(int32_t channel, int32_t *active) {
  AcquireSRWLockShared(&g_mfv_lock);
  mfv *p = mfv_get_locked(channel);
  if (active) *active = p ? 1 : 0;
  if (!p) { ReleaseSRWLockShared(&g_mfv_lock); return NULL; }
  // Handle e índice bajo `pub`: el presentador sube y fija el índice dentro del mismo cerrojo.
  EnterCriticalSection(&p->pub);
  void *h = p->pub_seq > 0 ? tf_d3d_handle(channel) : NULL;
  int n = p->pub_n;
  double item = p->pub_pts;
  int64_t seq = p->pub_seq;
  int fresh = h && seq != p->copied_seq;
  p->copied_seq = seq;
  LeaveCriticalSection(&p->pub);
  double now = mfv_now();
  EnterCriticalSection(&p->cs);
  p->calls++;
  if (fresh) {
    p->deliveries++;
    if (n < 0) p->unreadable++;
    if (p->n_samples == p->cap_samples) {
      int cap = p->cap_samples ? p->cap_samples * 2 : 1024;
      mfv_sample *x = (mfv_sample *)realloc(p->samples, sizeof(mfv_sample) * (size_t)cap);
      if (x) { p->samples = x; p->cap_samples = cap; }
    }
    if (p->n_samples < p->cap_samples) {
      mfv_sample *x = &p->samples[p->n_samples++];
      x->t = now - p->t0;
      x->has_e = n >= 0;
      x->e = n >= 0 ? mfv_pos(p, now) - (double)n * kFrameDur : 0;
      x->n = n;
      x->item = item;
      x->epoch = p->c_epoch;
    }
  }
  LeaveCriticalSection(&p->cs);
  ReleaseSRWLockShared(&g_mfv_lock);
  return h;
}
#endif
