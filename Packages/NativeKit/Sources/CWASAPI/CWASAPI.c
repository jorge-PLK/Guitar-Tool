#include "CWASAPI.h"
typedef int CWASAPI_empty_translation_unit;

// Shim de WASAPI (plan, «Fase 7c», paso 7, parte 7.7). Contrato en include/CWASAPI.h; lo consume el probe
// Probes/P8-windows/wasapi y, en la parte 7.10, `WASAPIAudioIO` (AudioKit).
#if defined(_WIN32)
#if !defined(_WIN32_WINNT) || _WIN32_WINNT < 0x0A00
#undef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif
#if !defined(NTDDI_VERSION) || NTDDI_VERSION < 0x0A000000
#undef NTDDI_VERSION
#define NTDDI_VERSION 0x0A000000
#endif
#if !defined(WINVER) || WINVER < 0x0A00
#undef WINVER
#define WINVER 0x0A00
#endif
#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmreg.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <devicetopology.h>
#include <devpropdef.h>
#include <cfgmgr32.h>
#include <avrt.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <math.h>
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "avrt.lib")
#pragma comment(lib, "uuid.lib")
#pragma comment(lib, "cfgmgr32.lib")   // driver del adaptador en el listado (parte 7.10b)

int wasapi_shim_version(void) { return 1; }   // lo comprueba NativeSmokeTests

#ifndef AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM
#define AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM 0x80000000
#endif
#ifndef AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY
#define AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY 0x08000000
#endif

// GUIDs locales (no dependen de qué exporte uuid.lib en cada SDK).
static const GUID TF_CLSID_MMDeviceEnumerator = {0xBCDE0395, 0xE52F, 0x467C, {0x8E, 0x3D, 0xC4, 0x57, 0x92, 0x91, 0x69, 0x2E}};
static const GUID TF_IID_IMMDeviceEnumerator = {0xA95664D2, 0x9614, 0x4F35, {0xA7, 0x46, 0xDE, 0x8D, 0xB6, 0x36, 0x17, 0xE6}};
static const GUID TF_IID_IMMNotificationClient = {0x7991EEC9, 0x7E89, 0x4D85, {0x83, 0x90, 0x6C, 0x70, 0x3C, 0xEC, 0x60, 0xC0}};
static const GUID TF_IID_IUnknown = {0x00000000, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}};
static const GUID TF_IID_IAudioClient = {0x1CB9AD4C, 0xDBFA, 0x4C32, {0xB1, 0x78, 0xC2, 0xF5, 0x68, 0xA7, 0x03, 0xB2}};
static const GUID TF_IID_IAudioClient3 = {0x7ED4EE07, 0x8E67, 0x4CD4, {0x8C, 0x1A, 0x2B, 0x7A, 0x59, 0x87, 0xAD, 0x42}};
static const GUID TF_IID_IAudioRenderClient = {0xF294ACFC, 0x3146, 0x4483, {0xA7, 0xBF, 0xAD, 0xDC, 0xA7, 0xC2, 0x60, 0xE2}};
static const GUID TF_IID_IAudioCaptureClient = {0xC8ADBD64, 0xE71E, 0x48A0, {0xA4, 0xDE, 0x18, 0x5C, 0x39, 0x5C, 0xD3, 0x17}};
static const GUID TF_IID_IAudioClock = {0xCD63314F, 0x3FBA, 0x4A1B, {0x81, 0x2C, 0xEF, 0x96, 0x35, 0x87, 0x28, 0xE7}};
static const GUID TF_SUBTYPE_PCM = {0x00000001, 0x0000, 0x0010, {0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71}};
static const GUID TF_SUBTYPE_FLOAT = {0x00000003, 0x0000, 0x0010, {0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71}};
static const PROPERTYKEY TF_PKEY_FriendlyName = {{0xA45C254E, 0xDF1C, 0x4EFD, {0x80, 0x20, 0x67, 0xD1, 0x46, 0xA8, 0x50, 0xE0}}, 14};
static const PROPERTYKEY TF_PKEY_EngineFormat = {{0xF19F064D, 0x082C, 0x4E27, {0xBC, 0x73, 0x68, 0x82, 0xA1, 0xBB, 0x8E, 0x4C}}, 0};

static int ensure_com(void) {
    HRESULT hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    return hr == S_OK || hr == S_FALSE;   // RPC_E_CHANGED_MODE: hilo STA ajeno; los objetos de audio valen igual
}

static void to_utf8(const WCHAR *w, char *out, int cap) {
    out[0] = 0;
    if (!w) return;
    if (WideCharToMultiByte(CP_UTF8, 0, w, -1, out, cap, NULL, NULL) <= 0) out[0] = 0;
    out[cap - 1] = 0;
}

#define RELEASE(p) do { if (p) { IUnknown_Release((IUnknown *)(p)); (p) = NULL; } } while (0)

static int64_t qpc_now(void) { LARGE_INTEGER c; QueryPerformanceCounter(&c); return c.QuadPart; }

// --- Formatos -------------------------------------------------------------------------------------------

enum { SF_FLOAT32 = 0, SF_I16 = 1, SF_I24 = 2, SF_I32 = 3, SF_OTHER = 4 };

static int is_float_format(const WAVEFORMATEX *w) {
    if (w->wFormatTag == WAVE_FORMAT_IEEE_FLOAT) return 1;
    if (w->wFormatTag == WAVE_FORMAT_EXTENSIBLE && w->cbSize >= 22)
        return IsEqualGUID(&((const WAVEFORMATEXTENSIBLE *)w)->SubFormat, &TF_SUBTYPE_FLOAT);
    return 0;
}

static void describe(const WAVEFORMATEX *w, wasapi_format *f) {
    f->sample_rate = w->nSamplesPerSec;
    f->channels = w->nChannels;
    f->bits = w->wBitsPerSample;
    f->valid_bits = (w->wFormatTag == WAVE_FORMAT_EXTENSIBLE && w->cbSize >= 22)
        ? ((const WAVEFORMATEXTENSIBLE *)w)->Samples.wValidBitsPerSample : w->wBitsPerSample;
    f->is_float = (uint16_t)is_float_format(w);
}

static int sample_kind(const WAVEFORMATEX *w) {
    if (is_float_format(w)) return w->wBitsPerSample == 32 ? SF_FLOAT32 : SF_OTHER;
    switch (w->wBitsPerSample) { case 16: return SF_I16; case 24: return SF_I24; case 32: return SF_I32; default: return SF_OTHER; }
}

static void copy_format(const WAVEFORMATEX *src, WAVEFORMATEXTENSIBLE *dst) {
    size_t n = sizeof(WAVEFORMATEX) + src->cbSize;
    if (n > sizeof(*dst)) n = sizeof(*dst);
    memset(dst, 0, sizeof(*dst));
    memcpy(dst, src, n);
}

static void make_format(WAVEFORMATEXTENSIBLE *f, uint32_t rate, uint16_t ch, DWORD mask, int is_float, uint16_t bits,
                        uint16_t valid) {
    memset(f, 0, sizeof(*f));
    f->Format.wFormatTag = WAVE_FORMAT_EXTENSIBLE;
    f->Format.nChannels = ch;
    f->Format.nSamplesPerSec = rate;
    f->Format.wBitsPerSample = bits;
    f->Format.nBlockAlign = (WORD)(ch * bits / 8);
    f->Format.nAvgBytesPerSec = rate * f->Format.nBlockAlign;
    f->Format.cbSize = 22;
    f->Samples.wValidBitsPerSample = valid;
    f->dwChannelMask = mask ? mask : (ch == 1 ? SPEAKER_FRONT_CENTER : ch == 2 ? (SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT) : 0);
    f->SubFormat = is_float ? TF_SUBTYPE_FLOAT : TF_SUBTYPE_PCM;
}

static DWORD mask_of(const WAVEFORMATEX *w) {
    return (w->wFormatTag == WAVE_FORMAT_EXTENSIBLE && w->cbSize >= 22) ? ((const WAVEFORMATEXTENSIBLE *)w)->dwChannelMask : 0;
}

static inline float clampf(float x) { return x > 1.f ? 1.f : (x < -1.f ? -1.f : x); }

static void float_to_device(const float *src, BYTE *dst, size_t samples, int kind) {
    size_t i;
    switch (kind) {
    case SF_I16: for (i = 0; i < samples; i++) ((int16_t *)dst)[i] = (int16_t)lrintf(clampf(src[i]) * 32767.f); break;
    case SF_I32: for (i = 0; i < samples; i++) ((int32_t *)dst)[i] = (int32_t)llrint((double)clampf(src[i]) * 2147483647.0); break;
    case SF_I24:
        for (i = 0; i < samples; i++) {
            int32_t v = (int32_t)lrintf(clampf(src[i]) * 8388607.f);
            dst[3 * i] = (BYTE)(v & 0xff); dst[3 * i + 1] = (BYTE)((v >> 8) & 0xff); dst[3 * i + 2] = (BYTE)((v >> 16) & 0xff);
        }
        break;
    default: break;
    }
}

static void device_to_float(const BYTE *src, float *dst, size_t samples, int kind) {
    size_t i;
    switch (kind) {
    case SF_FLOAT32: memcpy(dst, src, samples * sizeof(float)); break;
    case SF_I16: for (i = 0; i < samples; i++) dst[i] = (float)((const int16_t *)src)[i] / 32768.f; break;
    case SF_I32: for (i = 0; i < samples; i++) dst[i] = (float)((double)((const int32_t *)src)[i] / 2147483648.0); break;
    case SF_I24:
        for (i = 0; i < samples; i++) {
            int32_t v = (int32_t)((uint32_t)src[3 * i] << 8 | (uint32_t)src[3 * i + 1] << 16 | (uint32_t)src[3 * i + 2] << 24) >> 8;
            dst[i] = (float)v / 8388608.f;
        }
        break;
    default: memset(dst, 0, samples * sizeof(float)); break;
    }
}

// --- Notificaciones (IMMNotificationClient en C) --------------------------------------------------------

typedef struct tf_notifier {
    IMMNotificationClient iface;   // primer miembro: el puntero COM es el de la estructura
    wasapi_event_cb cb;
    void *ctx;
    WCHAR rid[WASAPI_ID_CAP], cid[WASAPI_ID_CAP];
} tf_notifier;

static void notify(tf_notifier *n, int32_t kind, int32_t flow, LPCWSTR id) {
    char buf[WASAPI_ID_CAP];
    if (!n->cb) return;
    to_utf8(id, buf, WASAPI_ID_CAP);
    n->cb(n->ctx, kind, flow, id ? buf : NULL, 0);
}

static int32_t flow_of(tf_notifier *n, LPCWSTR id) {
    if (!id) return -1;
    if (n->rid[0] && lstrcmpiW(id, n->rid) == 0) return WASAPI_FLOW_RENDER;
    if (n->cid[0] && lstrcmpiW(id, n->cid) == 0) return WASAPI_FLOW_CAPTURE;
    return -1;
}

static HRESULT STDMETHODCALLTYPE nc_qi(IMMNotificationClient *This, REFIID riid, void **ppv) {
    if (IsEqualGUID(riid, &TF_IID_IUnknown) || IsEqualGUID(riid, &TF_IID_IMMNotificationClient)) { *ppv = This; return S_OK; }
    *ppv = NULL;
    return E_NOINTERFACE;
}
// Vive dentro del flujo y se desregistra antes de liberarlo: la cuenta de referencias no gobierna su vida.
static ULONG STDMETHODCALLTYPE nc_addref(IMMNotificationClient *This) { (void)This; return 1; }
static ULONG STDMETHODCALLTYPE nc_release(IMMNotificationClient *This) { (void)This; return 1; }
static HRESULT STDMETHODCALLTYPE nc_state(IMMNotificationClient *This, LPCWSTR id, DWORD state) {
    tf_notifier *n = (tf_notifier *)This;
    int32_t f = flow_of(n, id);
    if (f >= 0 && state != DEVICE_STATE_ACTIVE) notify(n, WASAPI_EVENT_DEVICE_REMOVED, f, id);
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE nc_added(IMMNotificationClient *This, LPCWSTR id) { (void)This; (void)id; return S_OK; }
static HRESULT STDMETHODCALLTYPE nc_removed(IMMNotificationClient *This, LPCWSTR id) {
    tf_notifier *n = (tf_notifier *)This;
    int32_t f = flow_of(n, id);
    if (f >= 0) notify(n, WASAPI_EVENT_DEVICE_REMOVED, f, id);
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE nc_default(IMMNotificationClient *This, EDataFlow flow, ERole role, LPCWSTR id) {
    if (role == eConsole && (flow == eRender || flow == eCapture))
        notify((tf_notifier *)This, WASAPI_EVENT_DEFAULT_CHANGED, flow == eRender ? WASAPI_FLOW_RENDER : WASAPI_FLOW_CAPTURE, id);
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE nc_prop(IMMNotificationClient *This, LPCWSTR id, const PROPERTYKEY key) {
    tf_notifier *n = (tf_notifier *)This;
    int32_t f = flow_of(n, id);
    if (f >= 0 && IsEqualGUID(&key.fmtid, &TF_PKEY_EngineFormat.fmtid) && key.pid == TF_PKEY_EngineFormat.pid)
        notify(n, WASAPI_EVENT_FORMAT_CHANGED, f, id);
    return S_OK;
}
static IMMNotificationClientVtbl tf_notifier_vtbl = {nc_qi, nc_addref, nc_release, nc_state, nc_added, nc_removed, nc_default, nc_prop};

// --- Enumeración --------------------------------------------------------------------------------------

static void read_name(IMMDevice *dev, char *out, int cap) {
    IPropertyStore *ps = NULL;
    PROPVARIANT pv;
    out[0] = 0;
    if (FAILED(IMMDevice_OpenPropertyStore(dev, STGM_READ, &ps))) return;
    PropVariantInit(&pv);
    if (SUCCEEDED(IPropertyStore_GetValue(ps, &TF_PKEY_FriendlyName, &pv)) && pv.vt == VT_LPWSTR) to_utf8(pv.pwszVal, out, cap);
    PropVariantClear(&pv);
    RELEASE(ps);
}

static void query_device(IMMDevice *dev, wasapi_device_info *d) {
    IAudioClient *c = NULL;
    IAudioClient3 *c3 = NULL;
    WAVEFORMATEX *mix = NULL;
    HRESULT hr = IMMDevice_Activate(dev, &TF_IID_IAudioClient, CLSCTX_ALL, NULL, (void **)&c);
    if (FAILED(hr)) { d->hresult = hr; return; }
    hr = IAudioClient_GetMixFormat(c, &mix);
    if (FAILED(hr)) { d->hresult = hr; goto done; }
    describe(mix, &d->mix);
    {
        REFERENCE_TIME def = 0, mn = 0;
        if (SUCCEEDED(IAudioClient_GetDevicePeriod(c, &def, &mn))) { d->default_period_100ns = def; d->minimum_period_100ns = mn; }
    }
    if (SUCCEEDED(IAudioClient_QueryInterface(c, &TF_IID_IAudioClient3, (void **)&c3))) {
        UINT32 a = 0, b = 0, m = 0, x = 0;
        d->has_client3 = 1;
        if (SUCCEEDED(IAudioClient3_GetSharedModeEnginePeriod(c3, mix, &a, &b, &m, &x))) {
            d->engine_default_frames = a; d->engine_fundamental_frames = b; d->engine_min_frames = m; d->engine_max_frames = x;
        }
    }
    {
        WAVEFORMATEXTENSIBLE f;
        make_format(&f, mix->nSamplesPerSec, mix->nChannels, mask_of(mix), 1, 32, 32);
        d->exclusive_float_ok = IAudioClient_IsFormatSupported(c, AUDCLNT_SHAREMODE_EXCLUSIVE, &f.Format, NULL) == S_OK;
    }
done:
    if (mix) CoTaskMemFree(mix);
    RELEASE(c3);
    RELEASE(c);
}

// Driver del adaptador (parte 7.10b): saber si un aparato USB va con su driver propio o con el genérico de Windows
// (servicio «usbaudio2»/«usbaudio», proveedor «Microsoft»).
static const GUID TF_IID_IDeviceTopology = {0x2A07407E, 0x6497, 0x4A18, {0x97, 0x87, 0x32, 0xF7, 0x9B, 0xD0, 0xD9, 0x8F}};
static const DEVPROPKEY TF_DEVPKEY_InstanceId = {{0x78C34FC8, 0x104A, 0x4ACA, {0x9E, 0xA4, 0x52, 0x4D, 0x52, 0x99, 0x6E, 0x57}}, 256};
static const DEVPROPKEY TF_DEVPKEY_DeviceDesc = {{0xA45C254E, 0xDF1C, 0x4EFD, {0x80, 0x20, 0x67, 0xD1, 0x46, 0xA8, 0x50, 0xE0}}, 2};
static const DEVPROPKEY TF_DEVPKEY_Service = {{0xA45C254E, 0xDF1C, 0x4EFD, {0x80, 0x20, 0x67, 0xD1, 0x46, 0xA8, 0x50, 0xE0}}, 6};
static const DEVPROPKEY TF_DEVPKEY_DevFriendlyName = {{0xA45C254E, 0xDF1C, 0x4EFD, {0x80, 0x20, 0x67, 0xD1, 0x46, 0xA8, 0x50, 0xE0}}, 14};
static const DEVPROPKEY TF_DEVPKEY_DriverVersion = {{0xA8B865DD, 0x2E3D, 0x4094, {0xAD, 0x97, 0xE5, 0x93, 0xA7, 0x0C, 0x75, 0xD6}}, 3};
static const DEVPROPKEY TF_DEVPKEY_DriverDesc = {{0xA8B865DD, 0x2E3D, 0x4094, {0xAD, 0x97, 0xE5, 0x93, 0xA7, 0x0C, 0x75, 0xD6}}, 4};
static const DEVPROPKEY TF_DEVPKEY_DriverInfPath = {{0xA8B865DD, 0x2E3D, 0x4094, {0xAD, 0x97, 0xE5, 0x93, 0xA7, 0x0C, 0x75, 0xD6}}, 5};
static const DEVPROPKEY TF_DEVPKEY_DriverProvider = {{0xA8B865DD, 0x2E3D, 0x4094, {0xAD, 0x97, 0xE5, 0x93, 0xA7, 0x0C, 0x75, 0xD6}}, 9};

/// Error de cfgmgr32 como HRESULT negativo (para `driver_hresult`).
static HRESULT cr_hr(CONFIGRET cr) { return (HRESULT)(0x80000000u | (uint32_t)cr); }

/// Propiedad de texto de un nodo PnP; vacía si no existe, no es texto o no cabe.
static int devnode_string(DEVINST dn, const DEVPROPKEY *key, char *out, int cap) {
    WCHAR buf[512];
    ULONG size = sizeof(buf);
    DEVPROPTYPE type = 0;
    out[0] = 0;
    if (CM_Get_DevNode_PropertyW(dn, key, &type, (PBYTE)buf, &size, 0) != CR_SUCCESS || type != DEVPROP_TYPE_STRING) return 0;
    buf[511] = 0;
    to_utf8(buf, out, cap);
    return out[0] != 0;
}

/// Endpoint → su conector 0 → id del dispositivo (filtro KS del adaptador) al que está conectado → nodo PnP → driver.
static void query_driver(IMMDevice *dev, wasapi_device_info *d) {
    IDeviceTopology *topo = NULL;
    IConnector *conn = NULL;
    LPWSTR adapter = NULL;
    const WCHAR *path;
    WCHAR inst[WASAPI_ID_CAP];
    ULONG size = sizeof(inst);
    DEVPROPTYPE type = 0;
    DEVINST dn = 0;
    CONFIGRET cr;
    HRESULT hr;
    if (FAILED(hr = IMMDevice_Activate(dev, &TF_IID_IDeviceTopology, CLSCTX_ALL, NULL, (void **)&topo))) goto done;
    if (FAILED(hr = IDeviceTopology_GetConnector(topo, 0, &conn))) goto done;
    if (FAILED(hr = IConnector_GetDeviceIdConnectedTo(conn, &adapter))) goto done;
    // El id del adaptador lleva delante un prefijo de MMDevice («{2}.») antes de la ruta de la interfaz «\\?\...».
    path = wcsstr(adapter, L"\\\\?\\");
    if (!path) path = adapter;
    cr = CM_Get_Device_Interface_PropertyW(path, &TF_DEVPKEY_InstanceId, &type, (PBYTE)inst, &size, 0);
    if (cr != CR_SUCCESS || type != DEVPROP_TYPE_STRING) { hr = cr_hr(cr != CR_SUCCESS ? cr : CR_FAILURE); goto done; }
    inst[WASAPI_ID_CAP - 1] = 0;
    to_utf8(inst, d->adapter_instance, WASAPI_ID_CAP);
    if ((cr = CM_Locate_DevNodeW(&dn, inst, CM_LOCATE_DEVNODE_NORMAL)) != CR_SUCCESS) { hr = cr_hr(cr); goto done; }
    if (!devnode_string(dn, &TF_DEVPKEY_DevFriendlyName, d->adapter_name, WASAPI_NAME_CAP))
        devnode_string(dn, &TF_DEVPKEY_DeviceDesc, d->adapter_name, WASAPI_NAME_CAP);
    devnode_string(dn, &TF_DEVPKEY_Service, d->driver_service, WASAPI_DRIVER_CAP);
    devnode_string(dn, &TF_DEVPKEY_DriverProvider, d->driver_provider, WASAPI_DRIVER_CAP);
    devnode_string(dn, &TF_DEVPKEY_DriverVersion, d->driver_version, WASAPI_DRIVER_CAP);
    devnode_string(dn, &TF_DEVPKEY_DriverDesc, d->driver_desc, WASAPI_NAME_CAP);
    devnode_string(dn, &TF_DEVPKEY_DriverInfPath, d->driver_inf, WASAPI_DRIVER_CAP);
    hr = S_OK;
done:
    d->driver_hresult = hr;
    if (adapter) CoTaskMemFree(adapter);
    RELEASE(conn);
    RELEASE(topo);
}

int32_t wasapi_enumerate(wasapi_device_info *out, int32_t capacity) {
    IMMDeviceEnumerator *e = NULL;
    int32_t total = 0;
    int fi;
    HRESULT hr;
    ensure_com();
    hr = CoCreateInstance(&TF_CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL, &TF_IID_IMMDeviceEnumerator, (void **)&e);
    if (FAILED(hr)) return hr;
    for (fi = 0; fi < 2; fi++) {
        EDataFlow flow = fi == 0 ? eRender : eCapture;
        IMMDeviceCollection *coll = NULL;
        IMMDevice *def = NULL;
        LPWSTR defId = NULL;
        UINT count = 0, i;
        if (SUCCEEDED(IMMDeviceEnumerator_GetDefaultAudioEndpoint(e, flow, eConsole, &def))) IMMDevice_GetId(def, &defId);
        RELEASE(def);
        if (SUCCEEDED(IMMDeviceEnumerator_EnumAudioEndpoints(e, flow, DEVICE_STATE_ACTIVE, &coll))) {
            IMMDeviceCollection_GetCount(coll, &count);
            for (i = 0; i < count; i++, total++) {
                IMMDevice *dev = NULL;
                LPWSTR id = NULL;
                wasapi_device_info *d;
                if (total >= capacity || !out) continue;
                d = &out[total];
                memset(d, 0, sizeof(*d));
                d->flow = fi == 0 ? WASAPI_FLOW_RENDER : WASAPI_FLOW_CAPTURE;
                if (FAILED(hr = IMMDeviceCollection_Item(coll, i, &dev))) { d->hresult = hr; continue; }
                if (SUCCEEDED(IMMDevice_GetId(dev, &id))) {
                    to_utf8(id, d->id, WASAPI_ID_CAP);
                    d->is_default = defId && lstrcmpiW(id, defId) == 0;
                    CoTaskMemFree(id);
                }
                read_name(dev, d->name, WASAPI_NAME_CAP);
                query_device(dev, d);
                query_driver(dev, d);
                RELEASE(dev);
            }
            RELEASE(coll);
        }
        if (defId) CoTaskMemFree(defId);
    }
    RELEASE(e);
    return total;
}

// --- Flujo --------------------------------------------------------------------------------------------

struct wasapi_stream {
    wasapi_open_params p;
    wasapi_stream_info info;
    IMMDeviceEnumerator *enumr;
    IMMDevice *rdev, *cdev;
    IAudioClient *rclient, *cclient;
    IAudioRenderClient *render;
    IAudioCaptureClient *capture;
    IAudioClock *clock;
    HANDLE revent, cevent, stop_event, thread;
    WAVEFORMATEXTENSIBLE rfmt, cfmt;
    int rkind, ckind;
    float *rscratch, *cscratch;      // reservados al abrir; el hilo de audio no reserva
    uint32_t cscratch_frames;
    double cratio;                   // fotogramas del flujo por fotograma del endpoint de captura (1 sin conversión)
    uint64_t cnext;                  // stream_position esperada del siguiente paquete
    int cstream_valid;
    uint64_t frames_written;
    wasapi_stream_status st;
    tf_notifier notifier;
    int notifier_registered;
    int zombie;                      // el hilo no salió a tiempo: no se libera nada
};

static HRESULT get_device(IMMDeviceEnumerator *e, EDataFlow flow, const char *id, IMMDevice **dev) {
    if (id && *id) {
        WCHAR w[WASAPI_ID_CAP];
        if (MultiByteToWideChar(CP_UTF8, 0, id, -1, w, WASAPI_ID_CAP) <= 0) return E_INVALIDARG;
        return IMMDeviceEnumerator_GetDevice(e, w, dev);
    }
    return IMMDeviceEnumerator_GetDefaultAudioEndpoint(e, flow, eConsole, dev);
}

int32_t wasapi_render_name(const char *id, char *out, int32_t cap) {
    IMMDeviceEnumerator *e = NULL;
    IMMDevice *dev = NULL;
    HRESULT hr;
    if (!out || cap <= 0) return E_INVALIDARG;
    out[0] = 0;
    ensure_com();
    hr = CoCreateInstance(&TF_CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL, &TF_IID_IMMDeviceEnumerator, (void **)&e);
    if (FAILED(hr)) return hr;
    if (SUCCEEDED(hr = get_device(e, eRender, id, &dev))) read_name(dev, out, cap);
    RELEASE(dev);
    RELEASE(e);
    return FAILED(hr) ? hr : 0;
}

static uint32_t hns_to_frames(REFERENCE_TIME t, uint32_t rate) { return (uint32_t)((double)t * rate / 1e7 + 0.5); }
static REFERENCE_TIME frames_to_hns(uint32_t f, uint32_t rate) { return (REFERENCE_TIME)(1e7 * f / rate + 0.5); }

// Compartido: IAudioClient3 con el periodo mínimo (si la frecuencia pedida es la de mezcla), si no IAudioClient con el
// periodo por defecto, y si la frecuencia no coincide, AUTOCONVERTPCM.
static HRESULT init_shared(IMMDevice *dev, uint32_t rate, uint32_t want, IAudioClient **out, WAVEFORMATEXTENSIBLE *fmt,
                           int32_t *path, uint32_t *period, const char **step) {
    IAudioClient3 *c3 = NULL;
    IAudioClient *c = NULL;
    WAVEFORMATEX *mix = NULL;
    HRESULT hr;
    if (SUCCEEDED(IMMDevice_Activate(dev, &TF_IID_IAudioClient3, CLSCTX_ALL, NULL, (void **)&c3))) {
        if (SUCCEEDED(IAudioClient3_GetMixFormat(c3, &mix)) && mix->nSamplesPerSec == rate) {
            UINT32 def = 0, fund = 0, mn = 0, mx = 0;
            if (SUCCEEDED(IAudioClient3_GetSharedModeEnginePeriod(c3, mix, &def, &fund, &mn, &mx)) && fund > 0) {
                uint32_t p = mn;
                if (want) {
                    p = want < mn ? mn : (want > mx ? mx : want);
                    p = mn + (p - mn + fund - 1) / fund * fund;
                    if (p > mx) p = mx;
                }
                hr = IAudioClient3_InitializeSharedAudioStream(c3, AUDCLNT_STREAMFLAGS_EVENTCALLBACK, p, mix, NULL);
                if (SUCCEEDED(hr)) {
                    copy_format(mix, fmt);
                    CoTaskMemFree(mix);
                    *out = (IAudioClient *)c3;   // IAudioClient3 hereda de IAudioClient (mismo prefijo de vtable)
                    *path = WASAPI_PATH_CLIENT3_SHARED;
                    *period = p;
                    return S_OK;
                }
            }
        }
        if (mix) { CoTaskMemFree(mix); mix = NULL; }
        RELEASE(c3);
    }
    *step = "Activate(IAudioClient)";
    if (FAILED(hr = IMMDevice_Activate(dev, &TF_IID_IAudioClient, CLSCTX_ALL, NULL, (void **)&c))) return hr;
    *step = "GetMixFormat";
    if (FAILED(hr = IAudioClient_GetMixFormat(c, &mix))) { RELEASE(c); return hr; }
    {
        REFERENCE_TIME def = 0, mn = 0;
        IAudioClient_GetDevicePeriod(c, &def, &mn);
        if (mix->nSamplesPerSec == rate) {
            copy_format(mix, fmt);
            *step = "IAudioClient::Initialize(shared)";
            hr = IAudioClient_Initialize(c, AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_EVENTCALLBACK, 0, 0, mix, NULL);
            *path = WASAPI_PATH_CLIENT_SHARED;
        } else {
            make_format(fmt, rate, mix->nChannels, mask_of(mix), 1, 32, 32);
            *step = "IAudioClient::Initialize(shared, autoconvert)";
            hr = IAudioClient_Initialize(c, AUDCLNT_SHAREMODE_SHARED,
                                         AUDCLNT_STREAMFLAGS_EVENTCALLBACK | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM |
                                         AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY, 0, 0, &fmt->Format, NULL);
            *path = WASAPI_PATH_AUTOCONVERT;
        }
        *period = hns_to_frames(def, rate);
    }
    CoTaskMemFree(mix);
    if (FAILED(hr)) { RELEASE(c); *path = WASAPI_PATH_NONE; return hr; }
    *out = c;
    return S_OK;
}

// Exclusivo: primer formato que admita el dispositivo (float32, int32, int24 en 32, int24, int16; canales de mezcla y
// luego 2), periodo mínimo del dispositivo (o el pedido), con el reintento de alineado de búfer.
static HRESULT init_exclusive(IMMDevice *dev, uint32_t rate, uint32_t want, IAudioClient **out, WAVEFORMATEXTENSIBLE *fmt,
                              uint32_t *period, const char **step) {
    static const uint16_t cand[][3] = {{1, 32, 32}, {0, 32, 32}, {0, 32, 24}, {0, 24, 24}, {0, 16, 16}};
    IAudioClient *c = NULL;
    WAVEFORMATEX *mix = NULL;
    REFERENCE_TIME def = 0, mn = 0, per;
    HRESULT hr;
    int found = 0, k, ci;
    *step = "Activate(IAudioClient)";
    if (FAILED(hr = IMMDevice_Activate(dev, &TF_IID_IAudioClient, CLSCTX_ALL, NULL, (void **)&c))) return hr;
    *step = "GetMixFormat";
    if (FAILED(hr = IAudioClient_GetMixFormat(c, &mix))) { RELEASE(c); return hr; }
    for (ci = 0; ci < 2 && !found; ci++) {
        uint16_t ch = ci == 0 ? mix->nChannels : 2;
        DWORD mask = ci == 0 ? mask_of(mix) : 0;
        if (ci == 1 && ch == mix->nChannels) break;
        for (k = 0; k < 5 && !found; k++) {
            make_format(fmt, rate, ch, mask, cand[k][0], cand[k][1], cand[k][2]);
            if (IAudioClient_IsFormatSupported(c, AUDCLNT_SHAREMODE_EXCLUSIVE, &fmt->Format, NULL) == S_OK) found = 1;
        }
    }
    CoTaskMemFree(mix);
    *step = "IsFormatSupported(exclusive)";
    if (!found) { RELEASE(c); return AUDCLNT_E_UNSUPPORTED_FORMAT; }
    IAudioClient_GetDevicePeriod(c, &def, &mn);
    per = want ? frames_to_hns(want, rate) : mn;
    if (per < mn) per = mn;
    *step = "IAudioClient::Initialize(exclusive)";
    hr = IAudioClient_Initialize(c, AUDCLNT_SHAREMODE_EXCLUSIVE, AUDCLNT_STREAMFLAGS_EVENTCALLBACK, per, per, &fmt->Format, NULL);
    if (hr == AUDCLNT_E_BUFFER_SIZE_NOT_ALIGNED) {
        UINT32 n = 0;
        IAudioClient_GetBufferSize(c, &n);
        RELEASE(c);
        per = frames_to_hns(n, rate);
        *step = "Activate(IAudioClient) tras alinear";
        if (FAILED(hr = IMMDevice_Activate(dev, &TF_IID_IAudioClient, CLSCTX_ALL, NULL, (void **)&c))) return hr;
        *step = "IAudioClient::Initialize(exclusive, alineado)";
        hr = IAudioClient_Initialize(c, AUDCLNT_SHAREMODE_EXCLUSIVE, AUDCLNT_STREAMFLAGS_EVENTCALLBACK, per, per, &fmt->Format, NULL);
    }
    if (FAILED(hr)) { RELEASE(c); return hr; }
    {
        UINT32 n = 0;
        IAudioClient_GetBufferSize(c, &n);
        *period = n;
    }
    *out = c;
    return S_OK;
}

static HRESULT open_side(wasapi_stream *s, int capture, uint32_t rate, const char **step) {
    IMMDevice *dev = capture ? s->cdev : s->rdev;
    IAudioClient **client = capture ? &s->cclient : &s->rclient;
    WAVEFORMATEXTENSIBLE *fmt = capture ? &s->cfmt : &s->rfmt;
    int32_t *path = capture ? &s->info.capture_path : &s->info.render_path;
    uint32_t *period = capture ? &s->info.capture_period_frames : &s->info.render_period_frames;
    HANDLE ev = capture ? s->cevent : s->revent;
    UINT32 buf = 0;
    REFERENCE_TIME lat = 0;
    HRESULT hr;
    if (s->p.mode == WASAPI_MODE_EXCLUSIVE) {
        hr = init_exclusive(dev, rate, s->p.period_frames, client, fmt, period, step);
        if (SUCCEEDED(hr)) *path = WASAPI_PATH_EXCLUSIVE;
    } else {
        hr = init_shared(dev, rate, s->p.period_frames, client, fmt, path, period, step);
    }
    if (FAILED(hr)) return hr;
    *step = "SetEventHandle";
    if (FAILED(hr = IAudioClient_SetEventHandle(*client, ev))) return hr;
    *step = "GetBufferSize";
    if (FAILED(hr = IAudioClient_GetBufferSize(*client, &buf))) return hr;
    IAudioClient_GetStreamLatency(*client, &lat);
    if (capture) {
        describe(&fmt->Format, &s->info.capture_format);
        s->info.capture_buffer_frames = buf;
        s->info.capture_latency_100ns = lat;
        s->ckind = sample_kind(&fmt->Format);
        s->info.capture_device_rate = fmt->Format.nSamplesPerSec;
        s->cratio = 1.0;
        if (*path == WASAPI_PATH_AUTOCONVERT) {   // u64DevicePosition va en fotogramas del endpoint (medido en la VM)
            WAVEFORMATEX *mix = NULL;
            if (SUCCEEDED(IAudioClient_GetMixFormat(*client, &mix))) {
                s->info.capture_device_rate = mix->nSamplesPerSec;
                s->cratio = (double)fmt->Format.nSamplesPerSec / mix->nSamplesPerSec;
                CoTaskMemFree(mix);
            }
        }
        s->cscratch_frames = buf;
        s->cscratch = (float *)calloc((size_t)buf * fmt->Format.nChannels, sizeof(float));
        *step = "calloc(captura)";
        if (!s->cscratch) return E_OUTOFMEMORY;
        *step = "GetService(IAudioCaptureClient)";
        return IAudioClient_GetService(*client, &TF_IID_IAudioCaptureClient, (void **)&s->capture);
    }
    describe(&fmt->Format, &s->info.render_format);
    s->info.render_buffer_frames = buf;
    s->info.render_latency_100ns = lat;
    s->rkind = sample_kind(&fmt->Format);
    if (s->rkind != SF_FLOAT32) {
        s->rscratch = (float *)calloc((size_t)buf * fmt->Format.nChannels, sizeof(float));
        *step = "calloc(salida)";
        if (!s->rscratch) return E_OUTOFMEMORY;
    }
    *step = "GetService(IAudioRenderClient)";
    if (FAILED(hr = IAudioClient_GetService(*client, &TF_IID_IAudioRenderClient, (void **)&s->render))) return hr;
    *step = "GetService(IAudioClock)";
    if (FAILED(hr = IAudioClient_GetService(*client, &TF_IID_IAudioClock, (void **)&s->clock))) return hr;
    {
        UINT64 f = 0;
        IAudioClock_GetFrequency(s->clock, &f);
        s->info.clock_frequency = f;
    }
    return S_OK;
}

static void endpoint_ids(IMMDevice *dev, char *id8, char *name8, WCHAR *idw) {
    LPWSTR id = NULL;
    if (SUCCEEDED(IMMDevice_GetId(dev, &id))) {
        to_utf8(id, id8, WASAPI_ID_CAP);
        lstrcpynW(idw, id, WASAPI_ID_CAP);
        CoTaskMemFree(id);
    }
    read_name(dev, name8, WASAPI_NAME_CAP);
}

int32_t wasapi_open(const wasapi_open_params *params, wasapi_stream **out, wasapi_stream_info *info, const char **step) {
    const char *dummy = NULL;
    wasapi_stream *s;
    HRESULT hr;
    uint32_t rate;
    if (!step) step = &dummy;
    *out = NULL;
    *step = "parametros";
    if (!params || (!params->use_render && !params->use_capture)) return E_INVALIDARG;
    if ((params->use_render && !params->render) || (params->use_capture && !params->capture)) return E_INVALIDARG;
    ensure_com();
    s = (wasapi_stream *)calloc(1, sizeof(*s));
    *step = "calloc";
    if (!s) return E_OUTOFMEMORY;
    s->p = *params;
    s->p.render_id = s->p.capture_id = NULL;   // no se guardan punteros del llamador
    s->info.mode = params->mode;
    s->notifier.iface.lpVtbl = &tf_notifier_vtbl;
    s->notifier.cb = params->event;
    s->notifier.ctx = params->ctx;
    s->stop_event = CreateEventW(NULL, TRUE, FALSE, NULL);
    s->revent = params->use_render ? CreateEventW(NULL, FALSE, FALSE, NULL) : NULL;
    s->cevent = params->use_capture ? CreateEventW(NULL, FALSE, FALSE, NULL) : NULL;
    *step = "CreateEvent";
    if (!s->stop_event || (params->use_render && !s->revent) || (params->use_capture && !s->cevent)) { hr = E_FAIL; goto fail; }
    *step = "CoCreateInstance(MMDeviceEnumerator)";
    hr = CoCreateInstance(&TF_CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL, &TF_IID_IMMDeviceEnumerator, (void **)&s->enumr);
    if (FAILED(hr)) goto fail;
    if (params->use_render) {
        *step = "GetDevice(render)";
        if (FAILED(hr = get_device(s->enumr, eRender, params->render_id, &s->rdev))) goto fail;
        endpoint_ids(s->rdev, s->info.render_id, s->info.render_name, s->notifier.rid);
    }
    if (params->use_capture) {
        *step = "GetDevice(captura)";
        if (FAILED(hr = get_device(s->enumr, eCapture, params->capture_id, &s->cdev))) goto fail;
        endpoint_ids(s->cdev, s->info.capture_id, s->info.capture_name, s->notifier.cid);
    }
    rate = params->sample_rate;
    if (!rate) {
        IAudioClient *c = NULL;
        WAVEFORMATEX *mix = NULL;
        *step = "GetMixFormat(frecuencia)";
        if (FAILED(hr = IMMDevice_Activate(params->use_render ? s->rdev : s->cdev, &TF_IID_IAudioClient, CLSCTX_ALL, NULL, (void **)&c))) goto fail;
        hr = IAudioClient_GetMixFormat(c, &mix);
        if (SUCCEEDED(hr)) { rate = mix->nSamplesPerSec; CoTaskMemFree(mix); }
        RELEASE(c);
        if (FAILED(hr)) goto fail;
    }
    if (params->use_render && FAILED(hr = open_side(s, 0, rate, step))) goto fail;
    if (params->use_capture && FAILED(hr = open_side(s, 1, rate, step))) goto fail;
    if (params->event && SUCCEEDED(IMMDeviceEnumerator_RegisterEndpointNotificationCallback(s->enumr, &s->notifier.iface)))
        s->notifier_registered = 1;
    *step = NULL;
    if (info) *info = s->info;
    *out = s;
    return S_OK;
fail:
    if (info) *info = s->info;
    wasapi_close(s);
    return hr;
}

static HRESULT service_render(wasapi_stream *s, int64_t wake) {
    wasapi_render_info ri;
    UINT32 pad = 0, avail, ch = s->rfmt.Format.nChannels;
    BYTE *data = NULL;
    float *dst;
    HRESULT hr;
    if (s->info.render_path != WASAPI_PATH_EXCLUSIVE) {
        if (FAILED(hr = IAudioClient_GetCurrentPadding(s->rclient, &pad))) return hr;
    }
    avail = s->info.render_buffer_frames - pad;
    if (avail == 0) { s->st.render_starved++; return S_OK; }
    ri.frames_written = s->frames_written;
    ri.clock_frequency = s->info.clock_frequency;
    ri.wake_qpc_ticks = (uint64_t)wake;
    ri.padding_frames = pad;
    ri.reserved = 0;
    if (FAILED(IAudioClock_GetPosition(s->clock, &ri.clock_position, &ri.clock_qpc_100ns))) {
        s->st.clock_failures++;
        ri.clock_position = 0;
        ri.clock_qpc_100ns = 0;
    }
    if (FAILED(hr = IAudioRenderClient_GetBuffer(s->render, avail, &data))) return hr;
    dst = s->rkind == SF_FLOAT32 ? (float *)data : s->rscratch;
    memset(dst, 0, (size_t)avail * ch * sizeof(float));
    s->p.render(s->p.ctx, dst, avail, ch, &ri);
    if (s->rkind != SF_FLOAT32) float_to_device(dst, data, (size_t)avail * ch, s->rkind);
    if (FAILED(hr = IAudioRenderClient_ReleaseBuffer(s->render, avail, 0))) return hr;
    s->frames_written += avail;
    s->st.render_buffers++;
    return S_OK;
}

static HRESULT service_capture(wasapi_stream *s, int64_t wake) {
    UINT32 ch = s->cfmt.Format.nChannels, bpf = s->cfmt.Format.nBlockAlign, rate = s->cfmt.Format.nSamplesPerSec;
    for (;;) {
        BYTE *data = NULL;
        UINT32 frames = 0, done = 0;
        DWORD flags = 0;
        UINT64 pos = 0, qpc = 0, spos;
        HRESULT hr = IAudioCaptureClient_GetBuffer(s->capture, &data, &frames, &flags, &pos, &qpc);
        if (hr == AUDCLNT_S_BUFFER_EMPTY) return S_OK;
        if (FAILED(hr)) return hr;
        if (s->cratio == 1.0) spos = pos;
        else if (!s->cstream_valid || (flags & AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY)) spos = (uint64_t)llround((double)pos * s->cratio);
        else spos = s->cnext;
        s->cstream_valid = 1;
        s->cnext = spos + frames;
        while (done < frames) {   // trozos del tamaño del búfer reservado (un paquete no debería superarlo)
            wasapi_capture_info ci;
            UINT32 n = frames - done;
            if (n > s->cscratch_frames) n = s->cscratch_frames;
            if (flags & AUDCLNT_BUFFERFLAGS_SILENT) memset(s->cscratch, 0, (size_t)n * ch * sizeof(float));
            else device_to_float(data + (size_t)done * bpf, s->cscratch, (size_t)n * ch, s->ckind);
            ci.stream_position = spos + done;
            ci.device_position = pos + (uint64_t)llround((double)done / s->cratio);
            ci.qpc_100ns = qpc ? qpc + (uint64_t)((double)done * 1e7 / rate + 0.5) : 0;
            ci.wake_qpc_ticks = (uint64_t)wake;
            ci.flags = done == 0 ? (uint32_t)flags : (uint32_t)(flags & ~AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY);
            ci.reserved = 0;
            s->p.capture(s->p.ctx, s->cscratch, n, ch, &ci);
            s->st.capture_packets++;
            done += n;
        }
        if (FAILED(hr = IAudioCaptureClient_ReleaseBuffer(s->capture, frames))) return hr;
    }
}

static DWORD WINAPI audio_thread(LPVOID arg) {
    wasapi_stream *s = (wasapi_stream *)arg;
    HANDLE waits[3], av;
    DWORD n = 0, task = 0;
    int ri = -1, ci = -1;
    HRESULT hr = S_OK;
    int reason = 0;
    int com = ensure_com();
    av = AvSetMmThreadCharacteristicsW(L"Pro Audio", &task);
    s->st.mmcss_ok = av != NULL;
    waits[n++] = s->stop_event;
    if (s->revent) { ri = (int)n; waits[n++] = s->revent; }
    if (s->cevent) { ci = (int)n; waits[n++] = s->cevent; }
    for (;;) {
        DWORD r = WaitForMultipleObjects(n, waits, FALSE, WASAPI_STALL_MS);
        int64_t wake;
        int idx;
        if (r == WAIT_OBJECT_0) break;
        if (r == WAIT_TIMEOUT) { reason = WASAPI_EVENT_STALLED; break; }
        if (r == WAIT_FAILED || r >= WAIT_OBJECT_0 + n) { hr = HRESULT_FROM_WIN32(GetLastError()); reason = WASAPI_EVENT_STREAM_ERROR; break; }
        wake = qpc_now();
        s->st.wakeups++;
        idx = (int)(r - WAIT_OBJECT_0);
        // El evento que despertó ya está consumido (eventos de reinicio automático); el otro se mira sin esperar.
        if (idx == ri || (ri >= 0 && WaitForSingleObject(s->revent, 0) == WAIT_OBJECT_0))
            if (FAILED(hr = service_render(s, wake))) break;
        if (idx == ci || (ci >= 0 && WaitForSingleObject(s->cevent, 0) == WAIT_OBJECT_0))
            if (FAILED(hr = service_capture(s, wake))) break;
    }
    if (FAILED(hr) && !reason) reason = hr == AUDCLNT_E_DEVICE_INVALIDATED ? WASAPI_EVENT_DEVICE_INVALIDATED : WASAPI_EVENT_STREAM_ERROR;
    s->st.last_hresult = hr;
    s->st.stop_reason = reason;
    if (av) AvRevertMmThreadCharacteristics(av);
    if (reason && s->p.event) {
        int32_t flow = s->rclient ? WASAPI_FLOW_RENDER : WASAPI_FLOW_CAPTURE;
        s->p.event(s->p.ctx, reason, reason == WASAPI_EVENT_STALLED ? -1 : flow, NULL, hr);
    }
    if (com) CoUninitialize();
    return 0;
}

int32_t wasapi_start(wasapi_stream *s) {
    HRESULT hr;
    if (!s || s->zombie) return E_INVALIDARG;
    if (s->thread) return S_OK;
    memset(&s->st, 0, sizeof(s->st));
    s->frames_written = 0;
    s->cstream_valid = 0;
    ResetEvent(s->stop_event);
    if (s->render) {   // búfer entero de silencio antes de arrancar (exigido en exclusivo; evita el primer hueco)
        BYTE *data = NULL;
        UINT32 n = s->info.render_buffer_frames;
        if (FAILED(hr = IAudioRenderClient_GetBuffer(s->render, n, &data))) return hr;
        if (FAILED(hr = IAudioRenderClient_ReleaseBuffer(s->render, n, AUDCLNT_BUFFERFLAGS_SILENT))) return hr;
        s->frames_written = n;
    }
    if (s->cclient && FAILED(hr = IAudioClient_Start(s->cclient))) return hr;
    if (s->rclient && FAILED(hr = IAudioClient_Start(s->rclient))) {
        if (s->cclient) { IAudioClient_Stop(s->cclient); IAudioClient_Reset(s->cclient); }
        return hr;
    }
    s->st.running = 1;
    s->thread = CreateThread(NULL, 0, audio_thread, s, 0, NULL);
    if (!s->thread) {
        hr = HRESULT_FROM_WIN32(GetLastError());
        s->st.running = 0;
        if (s->rclient) { IAudioClient_Stop(s->rclient); IAudioClient_Reset(s->rclient); }
        if (s->cclient) { IAudioClient_Stop(s->cclient); IAudioClient_Reset(s->cclient); }
        return hr;
    }
    return S_OK;
}

void wasapi_stop(wasapi_stream *s) {
    if (!s || !s->thread) return;
    SetEvent(s->stop_event);
    if (WaitForSingleObject(s->thread, WASAPI_STALL_MS + 500) != WAIT_OBJECT_0) {
        s->zombie = 1;   // el hilo sigue dentro de un callback o de una llamada COM: no se toca nada más
        return;
    }
    CloseHandle(s->thread);
    s->thread = NULL;
    if (s->rclient) { IAudioClient_Stop(s->rclient); IAudioClient_Reset(s->rclient); }
    if (s->cclient) { IAudioClient_Stop(s->cclient); IAudioClient_Reset(s->cclient); }
    s->st.running = 0;
}

void wasapi_get_status(const wasapi_stream *s, wasapi_stream_status *status) {
    if (!status) return;
    if (!s) { memset(status, 0, sizeof(*status)); return; }
    *status = s->st;
}

void wasapi_close(wasapi_stream *s) {
    if (!s) return;
    wasapi_stop(s);
    if (s->zombie) return;   // fuga deliberada antes que liberar memoria que el hilo aún usa
    if (s->notifier_registered) IMMDeviceEnumerator_UnregisterEndpointNotificationCallback(s->enumr, &s->notifier.iface);
    RELEASE(s->clock);
    RELEASE(s->render);
    RELEASE(s->capture);
    RELEASE(s->rclient);
    RELEASE(s->cclient);
    RELEASE(s->rdev);
    RELEASE(s->cdev);
    RELEASE(s->enumr);
    if (s->revent) CloseHandle(s->revent);
    if (s->cevent) CloseHandle(s->cevent);
    if (s->stop_event) CloseHandle(s->stop_event);
    free(s->rscratch);
    free(s->cscratch);
    free(s);
}
#endif
