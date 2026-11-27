#include "CMediaFoundation.h"
typedef int CMediaFoundation_empty_translation_unit;

// Shim de Media Foundation (plan, «Fase 7c», paso 7, parte 7.2). Escritor y prueba de partida: el de P8
// (Probes/P8-windows/mediafoundation, `tfmf.c`).
#if defined(_WIN32)
#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <mftransform.h>
#include <cfgmgr32.h>
#include <stdlib.h>
#include <string.h>
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "mf.lib")
#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "propsys.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "cfgmgr32.lib")

int mf_shim_version(void) { return 1; }   // lo comprueba NativeSmokeTests

// MFSampleExtension_DeviceTimestamp (mfapi.h, Windows 8+): marca del dispositivo en QPC de 100 ns. Copia local para no
// depender de que la versión del SDK la exporte en mfuuid.lib.
static const GUID TF_DeviceTimestamp = {0x8f3e35e7, 0x2dcd, 0x4887, {0x86, 0x22, 0x2a, 0x58, 0xba, 0xa6, 0x52, 0xb0}};
// KSCATEGORY_VIDEO_CAMERA (ksmedia.h): interfaz de las cámaras que enumera MFEnumDeviceSources en Windows 10+.
static const GUID TF_KSCATEGORY_VIDEO_CAMERA = {0xe5323777, 0xf976, 0x4f5b, {0x9b, 0x55, 0xb9, 0x46, 0x99, 0xc4, 0x6e, 0x44}};

#define CHECK(expr, name) do { hr = (expr); if (FAILED(hr)) { *step = name; goto done; } } while (0)

static void ensure_com(void) { (void)CoInitializeEx(NULL, COINIT_MULTITHREADED); }

static void to_utf8(const WCHAR *w, char *out, int cap) {
    out[0] = 0;
    if (!w) return;
    if (WideCharToMultiByte(CP_UTF8, 0, w, -1, out, cap, NULL, NULL) <= 0) out[0] = 0;
    out[cap - 1] = 0;
}

static HRESULT set_pair(IMFAttributes *t, const GUID *key, UINT32 a, UINT32 b) {
    return IMFAttributes_SetUINT64(t, key, ((UINT64)a << 32) | b);
}

static HRESULT get_pair(IMFAttributes *t, const GUID *key, UINT32 *a, UINT32 *b) {
    UINT64 v = 0;
    HRESULT hr = IMFAttributes_GetUINT64(t, key, &v);
    *a = (UINT32)(v >> 32);
    *b = (UINT32)(v & 0xffffffffu);
    return hr;
}

// BT.709 de rango limitado, en coma fija de 16 bits (coeficientes · 219/255 para Y y · 224/255 para Cb y Cr).
static inline uint8_t clamp8(int v) { return (uint8_t)(v < 0 ? 0 : v > 255 ? 255 : v); }

static void bgra_to_nv12_scalar(const uint8_t *bgra, int32_t bgraStride, int32_t width, int32_t height,
                                uint8_t *y, int32_t yStride, uint8_t *uv, int32_t uvStride) {
    for (int32_t r = 0; r < height; r++) {
        const uint8_t *s = bgra + (size_t)r * bgraStride;
        uint8_t *d = y + (size_t)r * yStride;
        for (int32_t x = 0; x < width; x++, s += 4) {
            d[x] = clamp8(16 + ((11966 * s[2] + 40254 * s[1] + 4064 * s[0] + 32768) >> 16));
        }
    }
    // Tamaños impares: la última fila o columna de croma repite el píxel del borde.
    for (int32_t r = 0; r < (height + 1) / 2; r++) {
        const uint8_t *s0 = bgra + (size_t)(2 * r) * bgraStride, *s1 = (2 * r + 1 < height) ? s0 + bgraStride : s0;
        uint8_t *d = uv + (size_t)r * uvStride;
        for (int32_t x = 0; x < (width + 1) / 2; x++) {
            int o = (2 * x + 1 < width) ? 4 : 0;
            const uint8_t *a = s0 + 8 * x, *b = s1 + 8 * x;
            int B = a[0] + a[o] + b[0] + b[o], G = a[1] + a[o + 1] + b[1] + b[o + 1], R = a[2] + a[o + 2] + b[2] + b[o + 2];
            // Suma de 4 píxeles: se divide entre 4 dentro del desplazamiento (>> 18).
            d[2 * x] = clamp8(128 + ((-6598 * R - 22187 * G + 28784 * B + (1 << 17)) >> 18));
            d[2 * x + 1] = clamp8(128 + ((28784 * R - 26148 * G - 2637 * B + (1 << 17)) >> 18));
        }
    }
}

static void nv12_to_bgra_scalar(const uint8_t *y, int32_t yStride, const uint8_t *uv, int32_t uvStride, int32_t width, int32_t height,
                                uint8_t *bgra, int32_t bgraStride) {
    for (int32_t r = 0; r < height; r++) {
        const uint8_t *ys = y + (size_t)r * yStride, *cs = uv + (size_t)(r / 2) * uvStride;
        uint8_t *d = bgra + (size_t)r * bgraStride;
        for (int32_t x = 0; x < width; x++, d += 4) {
            int Y = 76309 * (ys[x] - 16), U = cs[(x & ~1)] - 128, V = cs[(x & ~1) + 1] - 128;
            d[0] = clamp8((Y + 138438 * U + 32768) >> 16);
            d[1] = clamp8((Y - 13975 * U - 34925 * V + 32768) >> 16);
            d[2] = clamp8((Y + 117489 * V + 32768) >> 16);
            d[3] = 255;
        }
    }
}

// --- Conversión de color con AVX2 ------------------------------------------------------------------------------------
// Mismas cuentas enteras de 32 bits que el escalar (mullo, desplazamiento aritmético, min/max), por eso los bytes salen
// idénticos. Las colas (ancho no múltiplo de 8, anchos y alturas impares) las resuelve el propio escalar.
#if defined(__x86_64__) || defined(_M_X64)
#include <immintrin.h>
#define TF_AVX2 __attribute__((target("avx2")))
#define TF_HAVE_AVX2_CODE 1

static int tf_cpu_has_avx2(void) {
    int info[4] = {0, 0, 0, 0};
    __asm__ volatile("cpuid" : "=a"(info[0]), "=b"(info[1]), "=c"(info[2]), "=d"(info[3]) : "a"(0), "c"(0));
    if (info[0] < 7) return 0;
    __asm__ volatile("cpuid" : "=a"(info[0]), "=b"(info[1]), "=c"(info[2]), "=d"(info[3]) : "a"(1), "c"(0));
    int osxsave = (info[2] >> 27) & 1, avx = (info[2] >> 28) & 1;
    if (!osxsave || !avx) return 0;
    unsigned lo, hi;
    __asm__ volatile("xgetbv" : "=a"(lo), "=d"(hi) : "c"(0));
    if ((lo & 6) != 6) return 0;   // el sistema guarda los registros XMM e YMM
    __asm__ volatile("cpuid" : "=a"(info[0]), "=b"(info[1]), "=c"(info[2]), "=d"(info[3]) : "a"(7), "c"(0));
    return (info[1] >> 5) & 1;
}

TF_AVX2 static void nv12_to_bgra_avx2(const uint8_t *y, int32_t yStride, const uint8_t *uv, int32_t uvStride, int32_t width, int32_t height,
                                      uint8_t *bgra, int32_t bgraStride) {
    const __m256i k16 = _mm256_set1_epi32(16), k128 = _mm256_set1_epi32(128), kY = _mm256_set1_epi32(76309),
                  kBU = _mm256_set1_epi32(138438), kGU = _mm256_set1_epi32(-13975), kGV = _mm256_set1_epi32(-34925),
                  kRV = _mm256_set1_epi32(117489), kRound = _mm256_set1_epi32(32768), zero = _mm256_setzero_si256(),
                  k255 = _mm256_set1_epi32(255), alpha = _mm256_set1_epi32((int)0xff000000u);
    const __m256i evenIdx = _mm256_setr_epi32(0, 0, 2, 2, 4, 4, 6, 6), oddIdx = _mm256_setr_epi32(1, 1, 3, 3, 5, 5, 7, 7);
    for (int32_t r = 0; r < height; r++) {
        const uint8_t *ys = y + (size_t)r * yStride, *cs = uv + (size_t)(r / 2) * uvStride;
        uint8_t *d = bgra + (size_t)r * bgraStride;
        int32_t x = 0;
        for (; x + 8 <= width; x += 8) {
            __m256i Y = _mm256_mullo_epi32(_mm256_sub_epi32(_mm256_cvtepu8_epi32(_mm_loadl_epi64((const __m128i *)(ys + x))), k16), kY);
            __m256i c = _mm256_sub_epi32(_mm256_cvtepu8_epi32(_mm_loadl_epi64((const __m128i *)(cs + x))), k128);
            __m256i U = _mm256_permutevar8x32_epi32(c, evenIdx), V = _mm256_permutevar8x32_epi32(c, oddIdx);
            __m256i b = _mm256_srai_epi32(_mm256_add_epi32(_mm256_add_epi32(Y, _mm256_mullo_epi32(U, kBU)), kRound), 16);
            __m256i g = _mm256_srai_epi32(_mm256_add_epi32(_mm256_add_epi32(_mm256_add_epi32(Y, _mm256_mullo_epi32(U, kGU)),
                                                                            _mm256_mullo_epi32(V, kGV)), kRound), 16);
            __m256i rr = _mm256_srai_epi32(_mm256_add_epi32(_mm256_add_epi32(Y, _mm256_mullo_epi32(V, kRV)), kRound), 16);
            b = _mm256_min_epi32(_mm256_max_epi32(b, zero), k255);
            g = _mm256_min_epi32(_mm256_max_epi32(g, zero), k255);
            rr = _mm256_min_epi32(_mm256_max_epi32(rr, zero), k255);
            __m256i px = _mm256_or_si256(_mm256_or_si256(b, _mm256_slli_epi32(g, 8)), _mm256_or_si256(_mm256_slli_epi32(rr, 16), alpha));
            _mm256_storeu_si256((__m256i *)(d + 4 * x), px);
        }
        for (; x < width; x++) {
            int Y = 76309 * (ys[x] - 16), U = cs[(x & ~1)] - 128, V = cs[(x & ~1) + 1] - 128;
            uint8_t *p = d + 4 * x;
            p[0] = clamp8((Y + 138438 * U + 32768) >> 16);
            p[1] = clamp8((Y - 13975 * U - 34925 * V + 32768) >> 16);
            p[2] = clamp8((Y + 117489 * V + 32768) >> 16);
            p[3] = 255;
        }
    }
}

TF_AVX2 static void bgra_to_nv12_avx2(const uint8_t *bgra, int32_t bgraStride, int32_t width, int32_t height,
                                      uint8_t *y, int32_t yStride, uint8_t *uv, int32_t uvStride) {
    const __m256i kR = _mm256_set1_epi32(11966), kG = _mm256_set1_epi32(40254), kB = _mm256_set1_epi32(4064),
                  kRound = _mm256_set1_epi32(32768), k16 = _mm256_set1_epi32(16), zero = _mm256_setzero_si256(),
                  k255 = _mm256_set1_epi32(255), mask = _mm256_set1_epi32(255), pick = _mm256_setr_epi32(0, 4, 0, 4, 0, 4, 0, 4);
    for (int32_t r = 0; r < height; r++) {
        const uint8_t *s = bgra + (size_t)r * bgraStride;
        uint8_t *d = y + (size_t)r * yStride;
        int32_t x = 0;
        for (; x + 8 <= width; x += 8) {
            __m256i p = _mm256_loadu_si256((const __m256i *)(s + 4 * x));
            __m256i B = _mm256_and_si256(p, mask), G = _mm256_and_si256(_mm256_srli_epi32(p, 8), mask),
                    R = _mm256_and_si256(_mm256_srli_epi32(p, 16), mask);
            __m256i v = _mm256_add_epi32(_mm256_add_epi32(_mm256_mullo_epi32(R, kR), _mm256_mullo_epi32(G, kG)),
                                         _mm256_add_epi32(_mm256_mullo_epi32(B, kB), kRound));
            v = _mm256_add_epi32(k16, _mm256_srai_epi32(v, 16));
            v = _mm256_min_epi32(_mm256_max_epi32(v, zero), k255);
            __m256i w = _mm256_packus_epi16(_mm256_packus_epi32(v, v), _mm256_setzero_si256());
            w = _mm256_permutevar8x32_epi32(w, pick);
            _mm_storel_epi64((__m128i *)(d + x), _mm256_castsi256_si128(w));
        }
        for (; x < width; x++) {
            const uint8_t *q = s + 4 * x;
            d[x] = clamp8(16 + ((11966 * q[2] + 40254 * q[1] + 4064 * q[0] + 32768) >> 16));
        }
    }
    const __m128i cUR = _mm_set1_epi32(-6598), cUG = _mm_set1_epi32(-22187), cUB = _mm_set1_epi32(28784),
                  cVR = _mm_set1_epi32(28784), cVG = _mm_set1_epi32(-26148), cVB = _mm_set1_epi32(-2637),
                  rnd = _mm_set1_epi32(1 << 17), k128 = _mm_set1_epi32(128), z = _mm_setzero_si128(), m255 = _mm_set1_epi32(255);
    for (int32_t r = 0; r < (height + 1) / 2; r++) {
        const uint8_t *s0 = bgra + (size_t)(2 * r) * bgraStride, *s1 = (2 * r + 1 < height) ? s0 + bgraStride : s0;
        uint8_t *d = uv + (size_t)r * uvStride;
        int32_t x = 0;   // columna de croma
        for (; 2 * x + 8 <= width; x += 4) {
            __m256i a = _mm256_loadu_si256((const __m256i *)(s0 + 8 * x)), b = _mm256_loadu_si256((const __m256i *)(s1 + 8 * x));
            __m256i Bs = _mm256_add_epi32(_mm256_and_si256(a, mask), _mm256_and_si256(b, mask));
            __m256i Gs = _mm256_add_epi32(_mm256_and_si256(_mm256_srli_epi32(a, 8), mask), _mm256_and_si256(_mm256_srli_epi32(b, 8), mask));
            __m256i Rs = _mm256_add_epi32(_mm256_and_si256(_mm256_srli_epi32(a, 16), mask), _mm256_and_si256(_mm256_srli_epi32(b, 16), mask));
            // Suma horizontal de pares: [s01 s23 s45 s67] en los 128 bits bajos.
            __m128i B = _mm256_castsi256_si128(_mm256_permute4x64_epi64(_mm256_hadd_epi32(Bs, Bs), 0x08));
            __m128i G = _mm256_castsi256_si128(_mm256_permute4x64_epi64(_mm256_hadd_epi32(Gs, Gs), 0x08));
            __m128i R = _mm256_castsi256_si128(_mm256_permute4x64_epi64(_mm256_hadd_epi32(Rs, Rs), 0x08));
            __m128i U = _mm_add_epi32(_mm_srai_epi32(_mm_add_epi32(_mm_add_epi32(_mm_mullo_epi32(R, cUR), _mm_mullo_epi32(G, cUG)),
                                                                   _mm_add_epi32(_mm_mullo_epi32(B, cUB), rnd)), 18), k128);
            __m128i V = _mm_add_epi32(_mm_srai_epi32(_mm_add_epi32(_mm_add_epi32(_mm_mullo_epi32(R, cVR), _mm_mullo_epi32(G, cVG)),
                                                                   _mm_add_epi32(_mm_mullo_epi32(B, cVB), rnd)), 18), k128);
            U = _mm_min_epi32(_mm_max_epi32(U, z), m255);
            V = _mm_min_epi32(_mm_max_epi32(V, z), m255);
            __m128i w = _mm_packus_epi16(_mm_packus_epi32(_mm_unpacklo_epi32(U, V), _mm_unpackhi_epi32(U, V)), z);
            _mm_storel_epi64((__m128i *)(d + 2 * x), w);
        }
        for (; x < (width + 1) / 2; x++) {
            int o = (2 * x + 1 < width) ? 4 : 0;
            const uint8_t *a = s0 + 8 * x, *b = s1 + 8 * x;
            int B = a[0] + a[o] + b[0] + b[o], G = a[1] + a[o + 1] + b[1] + b[o + 1], R = a[2] + a[o + 2] + b[2] + b[o + 2];
            d[2 * x] = clamp8(128 + ((-6598 * R - 22187 * G + 28784 * B + (1 << 17)) >> 18));
            d[2 * x + 1] = clamp8(128 + ((28784 * R - 26148 * G - 2637 * B + (1 << 17)) >> 18));
        }
    }
}
#endif

static int tf_simd_state = -1;   // -1 sin detectar, 0 no, 1 sí
static volatile int tf_force_scalar = 0;

int32_t tfmf_color_simd_available(void) {
#ifdef TF_HAVE_AVX2_CODE
    if (tf_simd_state < 0) tf_simd_state = tf_cpu_has_avx2();
    return tf_simd_state;
#else
    return 0;
#endif
}

void tfmf_color_force_scalar(int32_t force) { tf_force_scalar = force != 0; }

void tfmf_bgra_to_nv12(const uint8_t *bgra, int32_t bgraStride, int32_t width, int32_t height,
                       uint8_t *y, int32_t yStride, uint8_t *uv, int32_t uvStride) {
#ifdef TF_HAVE_AVX2_CODE
    if (!tf_force_scalar && tfmf_color_simd_available()) { bgra_to_nv12_avx2(bgra, bgraStride, width, height, y, yStride, uv, uvStride); return; }
#endif
    bgra_to_nv12_scalar(bgra, bgraStride, width, height, y, yStride, uv, uvStride);
}

void tfmf_nv12_to_bgra(const uint8_t *y, int32_t yStride, const uint8_t *uv, int32_t uvStride, int32_t width, int32_t height,
                       uint8_t *bgra, int32_t bgraStride) {
#ifdef TF_HAVE_AVX2_CODE
    if (!tf_force_scalar && tfmf_color_simd_available()) { nv12_to_bgra_avx2(y, yStride, uv, uvStride, width, height, bgra, bgraStride); return; }
#endif
    nv12_to_bgra_scalar(y, yStride, uv, uvStride, width, height, bgra, bgraStride);
}

// --- Codificadores ---------------------------------------------------------------------------------------------------

int32_t tfmf_list_encoders(int32_t codec, TFMFEncoderInfo *out, int32_t capacity) {
    ensure_com();
    HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_FULL);
    if (FAILED(hr)) return hr;
    MFT_REGISTER_TYPE_INFO info = {MFMediaType_Video, codec == TFMF_CODEC_HEVC ? MFVideoFormat_HEVC : MFVideoFormat_H264};
    IMFActivate **acts = NULL;
    UINT32 n = 0;
    hr = MFTEnumEx(MFT_CATEGORY_VIDEO_ENCODER,
                   MFT_ENUM_FLAG_SYNCMFT | MFT_ENUM_FLAG_ASYNCMFT | MFT_ENUM_FLAG_HARDWARE | MFT_ENUM_FLAG_SORTANDFILTER,
                   NULL, &info, &acts, &n);
    if (SUCCEEDED(hr)) {
        for (UINT32 i = 0; i < n; i++) {
            if ((int32_t)i < capacity && out) {
                WCHAR *name = NULL;
                UINT32 len = 0, flags = 0;
                out[i].codec = codec;
                out[i].name[0] = 0;
                if (SUCCEEDED(IMFActivate_GetAllocatedString(acts[i], &MFT_FRIENDLY_NAME_Attribute, &name, &len))) {
                    to_utf8(name, out[i].name, (int)sizeof out[i].name);
                    CoTaskMemFree(name);
                }
                IMFActivate_GetUINT32(acts[i], &MF_TRANSFORM_FLAGS_Attribute, &flags);
                out[i].hardware = (flags & MFT_ENUM_FLAG_HARDWARE) ? 1 : 0;
            }
            IMFActivate_Release(acts[i]);
        }
        CoTaskMemFree(acts);
    }
    MFShutdown();
    return SUCCEEDED(hr) ? (int32_t)n : hr;
}

// --- Escritor --------------------------------------------------------------------------------------------------------

typedef struct TFMFWriter {
    IMFSinkWriter *w;
    DWORD vs, as;
    int32_t hasAudio, width, height, channels, sampleRate;
    BYTE *nv12;
} TFMFWriter;

static void set_color(IMFMediaType *t) {
    IMFMediaType_SetUINT32(t, &MF_MT_VIDEO_PRIMARIES, MFVideoPrimaries_BT709);
    IMFMediaType_SetUINT32(t, &MF_MT_TRANSFER_FUNCTION, MFVideoTransFunc_709);
    IMFMediaType_SetUINT32(t, &MF_MT_YUV_MATRIX, MFVideoTransferMatrix_BT709);
    IMFMediaType_SetUINT32(t, &MF_MT_VIDEO_NOMINAL_RANGE, MFNominalRange_16_235);
}

static HRESULT write_buffer(IMFSinkWriter *w, DWORD stream, const BYTE *data, DWORD size, LONGLONG time, LONGLONG dur) {
    IMFMediaBuffer *buf = NULL;
    IMFSample *s = NULL;
    BYTE *p = NULL;
    HRESULT hr = MFCreateMemoryBuffer(size, &buf);
    if (SUCCEEDED(hr)) hr = IMFMediaBuffer_Lock(buf, &p, NULL, NULL);
    if (SUCCEEDED(hr)) { memcpy(p, data, size); IMFMediaBuffer_Unlock(buf); }
    if (SUCCEEDED(hr)) hr = IMFMediaBuffer_SetCurrentLength(buf, size);
    if (SUCCEEDED(hr)) hr = MFCreateSample(&s);
    if (SUCCEEDED(hr)) hr = IMFSample_AddBuffer(s, buf);
    if (SUCCEEDED(hr)) hr = IMFSample_SetSampleTime(s, time);
    if (SUCCEEDED(hr)) hr = IMFSample_SetSampleDuration(s, dur);
    if (SUCCEEDED(hr)) hr = IMFSinkWriter_WriteSample(w, stream, s);
    if (s) IMFSample_Release(s);
    if (buf) IMFMediaBuffer_Release(buf);
    return hr;
}

int32_t tfmf_writer_create(const uint16_t *path, const TFMFWriterConfig *c, void **writer, const char **step) {
    HRESULT hr = S_OK;
    IMFAttributes *attr = NULL;
    IMFMediaType *vo = NULL, *vi = NULL, *ao = NULL, *ai = NULL;
    TFMFWriter *tw = NULL;
    int started = 0;
    *writer = NULL;
    *step = "ok";
    if (c->width <= 0 || c->height <= 0 || (c->width & 1) || (c->height & 1) || c->fpsNum <= 0 || c->fpsDen <= 0) {
        *step = "tamaño o fps no válidos";
        return E_INVALIDARG;
    }
    ensure_com();
    CHECK(MFStartup(MF_VERSION, MFSTARTUP_FULL), "MFStartup");
    started = 1;
    tw = (TFMFWriter *)calloc(1, sizeof *tw);
    if (tw) tw->nv12 = (BYTE *)malloc((size_t)c->width * (size_t)c->height * 3 / 2);
    if (!tw || !tw->nv12) { hr = E_OUTOFMEMORY; *step = "memoria"; goto done; }
    tw->width = c->width;
    tw->height = c->height;
    CHECK(MFCreateAttributes(&attr, 3), "MFCreateAttributes");
    CHECK(IMFAttributes_SetUINT32(attr, &MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE), "hardware");
    CHECK(IMFAttributes_SetGUID(attr, &MF_TRANSCODE_CONTAINERTYPE, &MFTranscodeContainerType_MPEG4), "contenedor MPEG-4");
    if (c->realTime) CHECK(IMFAttributes_SetUINT32(attr, &MF_SINK_WRITER_DISABLE_THROTTLING, TRUE), "throttling");
    CHECK(MFCreateSinkWriterFromURL((LPCWSTR)path, NULL, attr, &tw->w), "MFCreateSinkWriterFromURL");

    CHECK(MFCreateMediaType(&vo), "MFCreateMediaType vo");
    IMFMediaType_SetGUID(vo, &MF_MT_MAJOR_TYPE, &MFMediaType_Video);
    IMFMediaType_SetGUID(vo, &MF_MT_SUBTYPE, c->codec == TFMF_CODEC_HEVC ? &MFVideoFormat_HEVC : &MFVideoFormat_H264);
    IMFMediaType_SetUINT32(vo, &MF_MT_AVG_BITRATE, (UINT32)c->videoBitrate);
    // H.264 perfil High como AVFoundation en el Mac (antes el codificador elegía Constrained Baseline).
    if (c->codec != TFMF_CODEC_HEVC) IMFMediaType_SetUINT32(vo, &MF_MT_MPEG2_PROFILE, 100 /* eAVEncH264VProfile_High */);
    IMFMediaType_SetUINT32(vo, &MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    set_pair((IMFAttributes *)vo, &MF_MT_FRAME_SIZE, (UINT32)c->width, (UINT32)c->height);
    set_pair((IMFAttributes *)vo, &MF_MT_FRAME_RATE, (UINT32)c->fpsNum, (UINT32)c->fpsDen);
    set_pair((IMFAttributes *)vo, &MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    set_color(vo);
    CHECK(IMFSinkWriter_AddStream(tw->w, vo, &tw->vs), c->codec == TFMF_CODEC_HEVC ? "AddStream HEVC" : "AddStream H.264");
    CHECK(MFCreateMediaType(&vi), "MFCreateMediaType vi");
    IMFMediaType_SetGUID(vi, &MF_MT_MAJOR_TYPE, &MFMediaType_Video);
    IMFMediaType_SetGUID(vi, &MF_MT_SUBTYPE, &MFVideoFormat_NV12);
    IMFMediaType_SetUINT32(vi, &MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    IMFMediaType_SetUINT32(vi, &MF_MT_DEFAULT_STRIDE, (UINT32)c->width);
    set_pair((IMFAttributes *)vi, &MF_MT_FRAME_SIZE, (UINT32)c->width, (UINT32)c->height);
    set_pair((IMFAttributes *)vi, &MF_MT_FRAME_RATE, (UINT32)c->fpsNum, (UINT32)c->fpsDen);
    set_pair((IMFAttributes *)vi, &MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    set_color(vi);
    CHECK(IMFSinkWriter_SetInputMediaType(tw->w, tw->vs, vi, NULL),
          c->codec == TFMF_CODEC_HEVC ? "SetInputMediaType NV12 a HEVC" : "SetInputMediaType NV12 a H.264");

    if (c->audioChannels > 0) {
        tw->hasAudio = 1;
        tw->channels = c->audioChannels;
        tw->sampleRate = c->audioSampleRate;
        CHECK(MFCreateMediaType(&ao), "MFCreateMediaType ao");
        IMFMediaType_SetGUID(ao, &MF_MT_MAJOR_TYPE, &MFMediaType_Audio);
        IMFMediaType_SetGUID(ao, &MF_MT_SUBTYPE, &MFAudioFormat_AAC);
        IMFMediaType_SetUINT32(ao, &MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
        IMFMediaType_SetUINT32(ao, &MF_MT_AUDIO_SAMPLES_PER_SECOND, (UINT32)c->audioSampleRate);
        IMFMediaType_SetUINT32(ao, &MF_MT_AUDIO_NUM_CHANNELS, (UINT32)c->audioChannels);
        IMFMediaType_SetUINT32(ao, &MF_MT_AUDIO_AVG_BYTES_PER_SECOND, (UINT32)c->audioBytesPerSecond);
        CHECK(IMFSinkWriter_AddStream(tw->w, ao, &tw->as), "AddStream AAC");
        CHECK(MFCreateMediaType(&ai), "MFCreateMediaType ai");
        IMFMediaType_SetGUID(ai, &MF_MT_MAJOR_TYPE, &MFMediaType_Audio);
        IMFMediaType_SetGUID(ai, &MF_MT_SUBTYPE, &MFAudioFormat_PCM);
        IMFMediaType_SetUINT32(ai, &MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
        IMFMediaType_SetUINT32(ai, &MF_MT_AUDIO_SAMPLES_PER_SECOND, (UINT32)c->audioSampleRate);
        IMFMediaType_SetUINT32(ai, &MF_MT_AUDIO_NUM_CHANNELS, (UINT32)c->audioChannels);
        IMFMediaType_SetUINT32(ai, &MF_MT_AUDIO_BLOCK_ALIGNMENT, (UINT32)(2 * c->audioChannels));
        IMFMediaType_SetUINT32(ai, &MF_MT_AUDIO_AVG_BYTES_PER_SECOND, (UINT32)(2 * c->audioChannels * c->audioSampleRate));
        CHECK(IMFSinkWriter_SetInputMediaType(tw->w, tw->as, ai, NULL), "SetInputMediaType PCM a AAC");
    }
    CHECK(IMFSinkWriter_BeginWriting(tw->w), "BeginWriting");

done:
    if (ai) IMFMediaType_Release(ai);
    if (ao) IMFMediaType_Release(ao);
    if (vi) IMFMediaType_Release(vi);
    if (vo) IMFMediaType_Release(vo);
    if (attr) IMFAttributes_Release(attr);
    if (FAILED(hr)) {
        if (tw) {
            if (tw->w) IMFSinkWriter_Release(tw->w);
            free(tw->nv12);
            free(tw);
        }
        if (started) MFShutdown();
        return hr;
    }
    *writer = tw;
    return hr;
}

int32_t tfmf_writer_video(void *writer, int32_t pixelFormat, const uint8_t *data, int32_t bytesPerRow,
                          int64_t time100ns, int64_t duration100ns) {
    TFMFWriter *tw = (TFMFWriter *)writer;
    int32_t W = tw->width, H = tw->height;
    BYTE *y = tw->nv12, *uv = tw->nv12 + (size_t)W * H;
    ensure_com();
    if (pixelFormat == TFMF_PIXEL_BGRA) {
        tfmf_bgra_to_nv12(data, bytesPerRow, W, H, y, W, uv, W);
    } else {
        for (int32_t r = 0; r < H; r++) memcpy(y + (size_t)r * W, data + (size_t)r * bytesPerRow, (size_t)W);
        const uint8_t *src = data + (size_t)bytesPerRow * H;
        for (int32_t r = 0; r < H / 2; r++) memcpy(uv + (size_t)r * W, src + (size_t)r * bytesPerRow, (size_t)W);
    }
    return write_buffer(tw->w, tw->vs, tw->nv12, (DWORD)((size_t)W * H * 3 / 2), time100ns, duration100ns);
}

int32_t tfmf_writer_audio(void *writer, const int16_t *interleaved, int32_t frames, int64_t time100ns) {
    TFMFWriter *tw = (TFMFWriter *)writer;
    if (!tw->hasAudio) return E_UNEXPECTED;
    ensure_com();
    LONGLONG dur = (LONGLONG)frames * 10000000LL / tw->sampleRate;
    return write_buffer(tw->w, tw->as, (const BYTE *)interleaved, (DWORD)(frames * tw->channels * 2), time100ns, dur);
}

int32_t tfmf_writer_finalize(void *writer) {
    ensure_com();
    return IMFSinkWriter_Finalize(((TFMFWriter *)writer)->w);
}

void tfmf_writer_release(void *writer) {
    TFMFWriter *tw = (TFMFWriter *)writer;
    if (!tw) return;
    ensure_com();
    if (tw->w) IMFSinkWriter_Release(tw->w);
    free(tw->nv12);
    free(tw);
    MFShutdown();
}

// --- Lector ----------------------------------------------------------------------------------------------------------

typedef struct TFMFReader {
    IMFSourceReader *r;
    DWORD stream;
    IMFSample *sample;
    IMFMediaBuffer *buf;
    IMF2DBuffer *buf2d;
    int locked, locked2d;
    int32_t width, height, alignedHeight, stride, channels;
} TFMFReader;

static void reader_unlock(TFMFReader *rd) {
    if (rd->buf2d) {
        if (rd->locked2d) IMF2DBuffer_Unlock2D(rd->buf2d);
        IMF2DBuffer_Release(rd->buf2d);
    }
    if (rd->buf) {
        if (rd->locked) IMFMediaBuffer_Unlock(rd->buf);
        IMFMediaBuffer_Release(rd->buf);
    }
    if (rd->sample) IMFSample_Release(rd->sample);
    rd->buf2d = NULL;
    rd->buf = NULL;
    rd->sample = NULL;
    rd->locked = rd->locked2d = 0;
}

// Tamaño visible (abertura mínima si la hay), alto del búfer (p. ej. 1088 para 1080) y stride por defecto.
static void video_layout(IMFMediaType *t, int32_t *w, int32_t *h, int32_t *alignedH, int32_t *stride) {
    UINT32 fw = 0, fh = 0, s = 0, sz = 0;
    MFVideoArea area;
    get_pair((IMFAttributes *)t, &MF_MT_FRAME_SIZE, &fw, &fh);
    *w = (int32_t)fw;
    *h = (int32_t)fh;
    *alignedH = (int32_t)fh;
    if (SUCCEEDED(IMFMediaType_GetBlob(t, &MF_MT_MINIMUM_DISPLAY_APERTURE, (UINT8 *)&area, sizeof area, &sz)) && sz == sizeof area
        && area.Area.cx > 0 && area.Area.cy > 0) {
        *w = area.Area.cx;
        *h = area.Area.cy;
    }
    *stride = SUCCEEDED(IMFMediaType_GetUINT32(t, &MF_MT_DEFAULT_STRIDE, &s)) ? (int32_t)s : (int32_t)fw;
}

static void reader_layout(TFMFReader *rd) {
    IMFMediaType *t = NULL;
    if (FAILED(IMFSourceReader_GetCurrentMediaType(rd->r, rd->stream, &t))) return;
    video_layout(t, &rd->width, &rd->height, &rd->alignedHeight, &rd->stride);
    IMFMediaType_Release(t);
}

int32_t tfmf_reader_open(const uint16_t *path, int32_t wantVideo, int32_t wantAudio, void **reader, TFMFReaderInfo *info) {
    HRESULT hr = S_OK;
    const char *where = "";
    const char **step = &where;
    IMFAttributes *attr = NULL;
    IMFMediaType *nt = NULL, *t = NULL;
    TFMFReader *rd = NULL;
    PROPVARIANT pv;
    int started = 0;
    *reader = NULL;
    memset(info, 0, sizeof *info);
    if (!wantVideo == !wantAudio) return E_INVALIDARG;
    ensure_com();
    CHECK(MFStartup(MF_VERSION, MFSTARTUP_FULL), "MFStartup");
    started = 1;
    rd = (TFMFReader *)calloc(1, sizeof *rd);
    if (!rd) { hr = E_OUTOFMEMORY; goto done; }
    CHECK(MFCreateAttributes(&attr, 1), "attr");
    CHECK(IMFAttributes_SetUINT32(attr, &MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE), "video processing");
    CHECK(MFCreateSourceReaderFromURL((LPCWSTR)path, attr, &rd->r), "MFCreateSourceReaderFromURL");
    if (SUCCEEDED(IMFSourceReader_GetNativeMediaType(rd->r, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, &nt))) {
        GUID sub;
        UINT32 n = 0, d = 0;
        info->hasVideo = 1;
        int32_t ah = 0, st = 0;
        video_layout(nt, &info->width, &info->height, &ah, &st);
        get_pair((IMFAttributes *)nt, &MF_MT_FRAME_RATE, &n, &d);
        info->fpsNum = (int32_t)n;
        info->fpsDen = (int32_t)d;
        if (SUCCEEDED(IMFMediaType_GetGUID(nt, &MF_MT_SUBTYPE, &sub))) info->videoFourCC = sub.Data1;
        IMFMediaType_Release(nt);
        nt = NULL;
    }
    if (SUCCEEDED(IMFSourceReader_GetNativeMediaType(rd->r, (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, 0, &nt))) {
        GUID sub;
        UINT32 v = 0;
        info->hasAudio = 1;
        if (SUCCEEDED(IMFMediaType_GetUINT32(nt, &MF_MT_AUDIO_SAMPLES_PER_SECOND, &v))) info->sampleRate = (int32_t)v;
        if (SUCCEEDED(IMFMediaType_GetUINT32(nt, &MF_MT_AUDIO_NUM_CHANNELS, &v))) info->channels = (int32_t)v;
        if (SUCCEEDED(IMFMediaType_GetGUID(nt, &MF_MT_SUBTYPE, &sub))) info->audioFormatTag = sub.Data1;
        IMFMediaType_Release(nt);
        nt = NULL;
    }
    PropVariantInit(&pv);
    if (SUCCEEDED(IMFSourceReader_GetPresentationAttribute(rd->r, (DWORD)MF_SOURCE_READER_MEDIASOURCE, &MF_PD_DURATION, &pv))) {
        info->duration100ns = (int64_t)pv.uhVal.QuadPart;
    }
    PropVariantClear(&pv);
    CHECK(IMFSourceReader_SetStreamSelection(rd->r, (DWORD)MF_SOURCE_READER_ALL_STREAMS, FALSE), "SetStreamSelection");
    CHECK(MFCreateMediaType(&t), "MFCreateMediaType");
    if (wantVideo) {
        if (!info->hasVideo) { hr = MF_E_INVALIDSTREAMNUMBER; goto done; }
        rd->stream = (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM;
        IMFMediaType_SetGUID(t, &MF_MT_MAJOR_TYPE, &MFMediaType_Video);
        IMFMediaType_SetGUID(t, &MF_MT_SUBTYPE, &MFVideoFormat_NV12);
    } else {
        if (!info->hasAudio) { hr = MF_E_INVALIDSTREAMNUMBER; goto done; }
        rd->stream = (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM;
        IMFMediaType_SetGUID(t, &MF_MT_MAJOR_TYPE, &MFMediaType_Audio);
        IMFMediaType_SetGUID(t, &MF_MT_SUBTYPE, &MFAudioFormat_Float);
    }
    CHECK(IMFSourceReader_SetStreamSelection(rd->r, rd->stream, TRUE), "SetStreamSelection flujo");
    CHECK(IMFSourceReader_SetCurrentMediaType(rd->r, rd->stream, NULL, t), "SetCurrentMediaType");
    if (wantVideo) {
        reader_layout(rd);
    } else {
        IMFMediaType *cur = NULL;
        UINT32 v = 0;
        if (SUCCEEDED(IMFSourceReader_GetCurrentMediaType(rd->r, rd->stream, &cur))) {
            if (SUCCEEDED(IMFMediaType_GetUINT32(cur, &MF_MT_AUDIO_NUM_CHANNELS, &v))) rd->channels = (int32_t)v;
            if (SUCCEEDED(IMFMediaType_GetUINT32(cur, &MF_MT_AUDIO_SAMPLES_PER_SECOND, &v))) info->sampleRate = (int32_t)v;
            IMFMediaType_Release(cur);
        }
        if (rd->channels <= 0) rd->channels = info->channels > 0 ? info->channels : 1;
        info->channels = rd->channels;
    }

done:
    (void)where;
    if (t) IMFMediaType_Release(t);
    if (attr) IMFAttributes_Release(attr);
    if (FAILED(hr)) {
        if (rd) {
            if (rd->r) IMFSourceReader_Release(rd->r);
            free(rd);
        }
        if (started) MFShutdown();
        return hr;
    }
    *reader = rd;
    return hr;
}

static HRESULT lock_planes(IMFSample *s, IMFMediaBuffer **buf, IMF2DBuffer **buf2d, int *locked, int *locked2d,
                           int32_t defaultStride, BYTE **base, LONG *pitch) {
    HRESULT hr = IMFSample_ConvertToContiguousBuffer(s, buf);
    if (FAILED(hr)) return hr;
    if (SUCCEEDED(IMFMediaBuffer_QueryInterface(*buf, &IID_IMF2DBuffer, (void **)buf2d))
        && SUCCEEDED(IMF2DBuffer_Lock2D(*buf2d, base, pitch))) {
        *locked2d = 1;
        return S_OK;
    }
    DWORD len = 0;
    hr = IMFMediaBuffer_Lock(*buf, base, NULL, &len);
    if (FAILED(hr)) return hr;
    *locked = 1;
    *pitch = defaultStride;
    return S_OK;
}

int32_t tfmf_reader_video(void *reader, TFMFVideoFrame *frame, int32_t *eos) {
    TFMFReader *rd = (TFMFReader *)reader;
    ensure_com();
    reader_unlock(rd);
    *eos = 0;
    for (;;) {
        DWORD idx = 0, flags = 0;
        LONGLONG ts = 0, dur = 0;
        IMFSample *s = NULL;
        HRESULT hr = IMFSourceReader_ReadSample(rd->r, rd->stream, 0, &idx, &flags, &ts, &s);
        if (FAILED(hr)) return hr;
        if (flags & MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED) reader_layout(rd);
        if (flags & MF_SOURCE_READERF_ENDOFSTREAM) {
            if (s) IMFSample_Release(s);
            *eos = 1;
            return S_OK;
        }
        if (!s) continue;
        rd->sample = s;
        IMFSample_GetSampleDuration(s, &dur);
        BYTE *base = NULL;
        LONG pitch = 0;
        hr = lock_planes(s, &rd->buf, &rd->buf2d, &rd->locked, &rd->locked2d, rd->stride, &base, &pitch);
        if (FAILED(hr)) return hr;
        frame->time100ns = ts;
        frame->duration100ns = dur;
        frame->width = rd->width;
        frame->height = rd->height;
        frame->y = base;
        frame->yStride = pitch;
        frame->uv = base + (size_t)pitch * (size_t)rd->alignedHeight;
        frame->uvStride = pitch;
        return S_OK;
    }
}

int32_t tfmf_reader_audio(void *reader, TFMFAudioChunk *chunk, int32_t *eos) {
    TFMFReader *rd = (TFMFReader *)reader;
    ensure_com();
    reader_unlock(rd);
    *eos = 0;
    for (;;) {
        DWORD idx = 0, flags = 0, len = 0;
        LONGLONG ts = 0;
        IMFSample *s = NULL;
        BYTE *p = NULL;
        HRESULT hr = IMFSourceReader_ReadSample(rd->r, rd->stream, 0, &idx, &flags, &ts, &s);
        if (FAILED(hr)) return hr;
        if (flags & MF_SOURCE_READERF_ENDOFSTREAM) {
            if (s) IMFSample_Release(s);
            *eos = 1;
            return S_OK;
        }
        if (!s) continue;
        rd->sample = s;
        hr = IMFSample_ConvertToContiguousBuffer(s, &rd->buf);
        if (FAILED(hr)) return hr;
        hr = IMFMediaBuffer_Lock(rd->buf, &p, NULL, &len);
        if (FAILED(hr)) return hr;
        rd->locked = 1;
        chunk->time100ns = ts;
        chunk->samples = (const float *)p;
        chunk->channels = rd->channels;
        chunk->frames = (int32_t)(len / (4u * (DWORD)rd->channels));
        return S_OK;
    }
}

int32_t tfmf_reader_seek(void *reader, int64_t time100ns) {
    TFMFReader *rd = (TFMFReader *)reader;
    static const GUID timeFormat = {0, 0, 0, {0, 0, 0, 0, 0, 0, 0, 0}};   // GUID_NULL: unidades de 100 ns
    PROPVARIANT pv;
    ensure_com();
    reader_unlock(rd);
    PropVariantInit(&pv);
    pv.vt = VT_I8;
    pv.hVal.QuadPart = time100ns < 0 ? 0 : time100ns;
    HRESULT hr = IMFSourceReader_SetCurrentPosition(rd->r, &timeFormat, &pv);
    PropVariantClear(&pv);
    return hr;
}

void tfmf_reader_release(void *reader) {
    TFMFReader *rd = (TFMFReader *)reader;
    if (!rd) return;
    ensure_com();
    reader_unlock(rd);
    if (rd->r) IMFSourceReader_Release(rd->r);
    free(rd);
    MFShutdown();
}

// --- Cámaras ---------------------------------------------------------------------------------------------------------

int64_t tfmf_system_time(void) { return (int64_t)MFGetSystemTime(); }

int32_t tfmf_camera_list(TFMFCameraInfo *out, int32_t capacity) {
    IMFAttributes *a = NULL;
    IMFActivate **devs = NULL;
    UINT32 n = 0;
    ensure_com();
    HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_FULL);
    if (FAILED(hr)) return hr;
    hr = MFCreateAttributes(&a, 1);
    if (SUCCEEDED(hr)) hr = IMFAttributes_SetGUID(a, &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE, &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
    if (SUCCEEDED(hr)) hr = MFEnumDeviceSources(a, &devs, &n);
    if (SUCCEEDED(hr)) {
        for (UINT32 i = 0; i < n; i++) {
            if ((int32_t)i < capacity && out) {
                WCHAR *s = NULL;
                UINT32 len = 0;
                out[i].id[0] = out[i].name[0] = 0;
                if (SUCCEEDED(IMFActivate_GetAllocatedString(devs[i], &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK, &s, &len))) {
                    to_utf8(s, out[i].id, (int)sizeof out[i].id);
                    CoTaskMemFree(s);
                }
                if (SUCCEEDED(IMFActivate_GetAllocatedString(devs[i], &MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME, &s, &len))) {
                    to_utf8(s, out[i].name, (int)sizeof out[i].name);
                    CoTaskMemFree(s);
                }
            }
            IMFActivate_Release(devs[i]);
        }
        CoTaskMemFree(devs);
    }
    if (a) IMFAttributes_Release(a);
    MFShutdown();
    return SUCCEEDED(hr) ? (int32_t)n : hr;
}

static HRESULT open_device(const uint16_t *id, IMFMediaSource **source) {
    IMFAttributes *a = NULL;
    HRESULT hr = MFCreateAttributes(&a, 2);
    if (SUCCEEDED(hr)) hr = IMFAttributes_SetGUID(a, &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE, &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
    if (SUCCEEDED(hr)) hr = IMFAttributes_SetString(a, &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK, (LPCWSTR)id);
    if (SUCCEEDED(hr)) hr = MFCreateDeviceSource(a, source);
    if (a) IMFAttributes_Release(a);
    return hr;
}

int32_t tfmf_camera_formats(const uint16_t *id, TFMFCameraFormat *out, int32_t capacity) {
    IMFMediaSource *src = NULL;
    IMFSourceReader *r = NULL;
    int32_t count = 0;
    ensure_com();
    HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_FULL);
    if (FAILED(hr)) return hr;
    hr = open_device(id, &src);
    if (SUCCEEDED(hr)) hr = MFCreateSourceReaderFromMediaSource(src, NULL, &r);
    for (DWORD i = 0; SUCCEEDED(hr); i++) {
        IMFMediaType *t = NULL;
        if (FAILED(IMFSourceReader_GetNativeMediaType(r, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, i, &t))) break;
        if (count < capacity && out) {
            TFMFCameraFormat *f = &out[count];
            UINT32 a = 0, b = 0;
            GUID sub;
            memset(f, 0, sizeof *f);
            f->index = (int32_t)i;
            get_pair((IMFAttributes *)t, &MF_MT_FRAME_SIZE, &a, &b);
            f->width = (int32_t)a;
            f->height = (int32_t)b;
            if (SUCCEEDED(IMFMediaType_GetGUID(t, &MF_MT_SUBTYPE, &sub))) f->fourCC = sub.Data1;
            get_pair((IMFAttributes *)t, &MF_MT_FRAME_RATE, &a, &b);
            f->fpsNum = (int32_t)a;
            f->fpsDen = (int32_t)b;
            f->fpsMinNum = f->fpsMaxNum = f->fpsNum;
            f->fpsMinDen = f->fpsMaxDen = f->fpsDen;
            if (SUCCEEDED(get_pair((IMFAttributes *)t, &MF_MT_FRAME_RATE_RANGE_MIN, &a, &b))) { f->fpsMinNum = (int32_t)a; f->fpsMinDen = (int32_t)b; }
            if (SUCCEEDED(get_pair((IMFAttributes *)t, &MF_MT_FRAME_RATE_RANGE_MAX, &a, &b))) { f->fpsMaxNum = (int32_t)a; f->fpsMaxDen = (int32_t)b; }
        }
        count++;
        IMFMediaType_Release(t);
    }
    if (r) IMFSourceReader_Release(r);
    if (src) {
        IMFMediaSource_Shutdown(src);
        IMFMediaSource_Release(src);
    }
    MFShutdown();
    return SUCCEEDED(hr) ? count : hr;
}

int32_t tfmf_camera_access(void) {
    static const WCHAR *key = L"Software\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore\\webcam";
    HKEY roots[2] = {HKEY_LOCAL_MACHINE, HKEY_CURRENT_USER};
    for (int i = 0; i < 2; i++) {
        WCHAR v[32];
        DWORD size = sizeof v;
        if (RegGetValueW(roots[i], key, L"Value", RRF_RT_REG_SZ, NULL, v, &size) == ERROR_SUCCESS && lstrcmpiW(v, L"Deny") == 0) return 0;
    }
    return 1;
}

typedef struct TFMFCapture {
    IMFSourceReaderCallback iface;   // primero: el puntero a la interfaz es el del objeto
    volatile LONG ref;
    IMFSourceReader *reader;
    IMFMediaSource *source;
    tfmf_camera_callback cb;
    void *ctx;
    CRITICAL_SECTION lock;
    HANDLE idle;                     // señalado cuando no hay lectura pendiente
    int stopping, pending;
    int32_t width, height, alignedHeight, stride;
} TFMFCapture;

static ULONG STDMETHODCALLTYPE cap_addref(IMFSourceReaderCallback *This) {
    return (ULONG)InterlockedIncrement(&((TFMFCapture *)This)->ref);
}

static ULONG STDMETHODCALLTYPE cap_release(IMFSourceReaderCallback *This) {
    TFMFCapture *c = (TFMFCapture *)This;
    LONG n = InterlockedDecrement(&c->ref);
    if (n == 0) {
        DeleteCriticalSection(&c->lock);
        if (c->idle) CloseHandle(c->idle);
        free(c);
    }
    return (ULONG)n;
}

static HRESULT STDMETHODCALLTYPE cap_qi(IMFSourceReaderCallback *This, REFIID riid, void **ppv) {
    if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_IMFSourceReaderCallback)) {
        *ppv = This;
        cap_addref(This);
        return S_OK;
    }
    *ppv = NULL;
    return E_NOINTERFACE;
}

static void capture_layout(TFMFCapture *c) {
    IMFMediaType *t = NULL;
    if (FAILED(IMFSourceReader_GetCurrentMediaType(c->reader, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, &t))) return;
    video_layout(t, &c->width, &c->height, &c->alignedHeight, &c->stride);
    IMFMediaType_Release(t);
}

static void capture_deliver(TFMFCapture *c, IMFSample *s, LONGLONG ts, int64_t now) {
    TFMFCameraFrame f;
    IMFMediaBuffer *buf = NULL;
    IMF2DBuffer *buf2d = NULL;
    int locked = 0, locked2d = 0;
    BYTE *base = NULL;
    LONG pitch = 0;
    UINT64 dev = 0;
    memset(&f, 0, sizeof f);
    f.sampleTime100ns = ts;
    f.systemTime100ns = now;
    if (SUCCEEDED(IMFSample_GetUINT64(s, &TF_DeviceTimestamp, &dev))) {
        f.deviceQPC100ns = (int64_t)dev;
        f.hasDeviceTime = 1;
    }
    if (SUCCEEDED(lock_planes(s, &buf, &buf2d, &locked, &locked2d, c->stride, &base, &pitch))) {
        f.width = c->width;
        f.height = c->height;
        f.y = base;
        f.yStride = pitch;
        f.uv = base + (size_t)pitch * (size_t)c->alignedHeight;
        f.uvStride = pitch;
        c->cb(c->ctx, &f);
    }
    if (buf2d) {
        if (locked2d) IMF2DBuffer_Unlock2D(buf2d);
        IMF2DBuffer_Release(buf2d);
    }
    if (buf) {
        if (locked) IMFMediaBuffer_Unlock(buf);
        IMFMediaBuffer_Release(buf);
    }
}

static HRESULT STDMETHODCALLTYPE cap_on_read(IMFSourceReaderCallback *This, HRESULT status, DWORD index, DWORD flags,
                                             LONGLONG ts, IMFSample *s) {
    TFMFCapture *c = (TFMFCapture *)This;
    int64_t now = (int64_t)MFGetSystemTime();
    HRESULT hr = E_ABORT;
    (void)index;
    EnterCriticalSection(&c->lock);
    if (!c->stopping) {
        if (flags & MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED) capture_layout(c);
        if (SUCCEEDED(status) && s) capture_deliver(c, s, ts, now);
        if (SUCCEEDED(status) && !(flags & (MF_SOURCE_READERF_ENDOFSTREAM | MF_SOURCE_READERF_ERROR))) {
            hr = IMFSourceReader_ReadSample(c->reader, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, NULL, NULL, NULL, NULL);
        }
    }
    if (FAILED(hr)) {
        c->pending = 0;
        SetEvent(c->idle);
    }
    LeaveCriticalSection(&c->lock);
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE cap_on_flush(IMFSourceReaderCallback *This, DWORD index) {
    TFMFCapture *c = (TFMFCapture *)This;
    (void)index;
    EnterCriticalSection(&c->lock);
    c->pending = 0;
    SetEvent(c->idle);
    LeaveCriticalSection(&c->lock);
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE cap_on_event(IMFSourceReaderCallback *This, DWORD index, IMFMediaEvent *e) {
    (void)This; (void)index; (void)e;
    return S_OK;
}

static IMFSourceReaderCallbackVtbl cap_vtbl = {cap_qi, cap_addref, cap_release, cap_on_read, cap_on_flush, cap_on_event};

int32_t tfmf_capture_start(const uint16_t *id, int32_t formatIndex, int32_t fpsNum, int32_t fpsDen,
                           tfmf_camera_callback callback, void *context, void **capture,
                           int32_t *width, int32_t *height, int32_t *outFpsNum, int32_t *outFpsDen) {
    HRESULT hr = S_OK;
    const char *where = "";
    const char **step = &where;
    IMFAttributes *ra = NULL;
    IMFMediaType *nt = NULL, *out = NULL, *cur = NULL;
    TFMFCapture *c = NULL;
    int started = 0;
    *capture = NULL;
    ensure_com();
    CHECK(MFStartup(MF_VERSION, MFSTARTUP_FULL), "MFStartup");
    started = 1;
    c = (TFMFCapture *)calloc(1, sizeof *c);
    if (!c) { hr = E_OUTOFMEMORY; goto done; }
    c->iface.lpVtbl = &cap_vtbl;
    c->ref = 1;
    c->cb = callback;
    c->ctx = context;
    InitializeCriticalSection(&c->lock);
    c->idle = CreateEventW(NULL, TRUE, FALSE, NULL);
    CHECK(open_device(id, &c->source), "MFCreateDeviceSource");
    CHECK(MFCreateAttributes(&ra, 2), "attr");
    CHECK(IMFAttributes_SetUnknown(ra, &MF_SOURCE_READER_ASYNC_CALLBACK, (IUnknown *)&c->iface), "callback");
    CHECK(IMFAttributes_SetUINT32(ra, &MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE), "video processing");
    CHECK(MFCreateSourceReaderFromMediaSource(c->source, ra, &c->reader), "MFCreateSourceReaderFromMediaSource");
    // Formato del dispositivo (con los fps pedidos) y salida NV12 (el lector añade el decodificador o el conversor).
    CHECK(IMFSourceReader_GetNativeMediaType(c->reader, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, (DWORD)formatIndex, &nt), "formato");
    if (fpsNum > 0 && fpsDen > 0) set_pair((IMFAttributes *)nt, &MF_MT_FRAME_RATE, (UINT32)fpsNum, (UINT32)fpsDen);
    CHECK(IMFSourceReader_SetCurrentMediaType(c->reader, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, NULL, nt), "SetCurrentMediaType nativo");
    CHECK(MFCreateMediaType(&out), "MFCreateMediaType");
    CHECK(IMFMediaType_CopyAllItems(nt, (IMFAttributes *)out), "CopyAllItems");
    IMFMediaType_SetGUID(out, &MF_MT_SUBTYPE, &MFVideoFormat_NV12);
    IMFMediaType_DeleteItem(out, &MF_MT_DEFAULT_STRIDE);
    IMFMediaType_DeleteItem(out, &MF_MT_SAMPLE_SIZE);
    CHECK(IMFSourceReader_SetCurrentMediaType(c->reader, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, NULL, out), "SetCurrentMediaType NV12");
    capture_layout(c);
    {
        UINT32 n = 0, d = 0;
        if (SUCCEEDED(IMFSourceReader_GetCurrentMediaType(c->reader, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, &cur))) {
            get_pair((IMFAttributes *)cur, &MF_MT_FRAME_RATE, &n, &d);
        }
        *width = c->width;
        *height = c->height;
        *outFpsNum = (int32_t)n;
        *outFpsDen = (int32_t)d;
    }
    EnterCriticalSection(&c->lock);
    c->pending = 1;
    ResetEvent(c->idle);
    hr = IMFSourceReader_ReadSample(c->reader, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, NULL, NULL, NULL, NULL);
    if (FAILED(hr)) c->pending = 0;
    LeaveCriticalSection(&c->lock);

done:
    (void)where;
    if (cur) IMFMediaType_Release(cur);
    if (out) IMFMediaType_Release(out);
    if (nt) IMFMediaType_Release(nt);
    if (ra) IMFAttributes_Release(ra);
    if (FAILED(hr)) {
        if (c) {
            if (c->reader) IMFSourceReader_Release(c->reader);
            if (c->source) {
                IMFMediaSource_Shutdown(c->source);
                IMFMediaSource_Release(c->source);
            }
            cap_release(&c->iface);
        }
        if (started) MFShutdown();
        return hr;
    }
    *capture = c;
    return hr;
}

void tfmf_capture_stop(void *capture) {
    TFMFCapture *c = (TFMFCapture *)capture;
    int pending;
    if (!c) return;
    ensure_com();
    // Con el cerrojo: una devolución de llamada en curso termina antes; las que lleguen después ven `stopping`.
    EnterCriticalSection(&c->lock);
    c->stopping = 1;
    pending = c->pending;
    LeaveCriticalSection(&c->lock);
    if (pending) {
        IMFSourceReader_Flush(c->reader, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM);
        WaitForSingleObject(c->idle, 2000);
    }
    IMFMediaSource_Shutdown(c->source);
    IMFSourceReader_Release(c->reader);
    IMFMediaSource_Release(c->source);
    c->reader = NULL;
    c->source = NULL;
    cap_release(&c->iface);
    MFShutdown();
}

typedef struct TFMFWatch {
    HCMNOTIFICATION handle;
    tfmf_change_callback cb;
    void *ctx;
} TFMFWatch;

static DWORD CALLBACK watch_cb(HCMNOTIFICATION h, PVOID ctx, CM_NOTIFY_ACTION action, PCM_NOTIFY_EVENT_DATA data, DWORD size) {
    TFMFWatch *w = (TFMFWatch *)ctx;
    (void)h; (void)data; (void)size;
    if (action == CM_NOTIFY_ACTION_DEVICEINTERFACEARRIVAL || action == CM_NOTIFY_ACTION_DEVICEINTERFACEREMOVAL) w->cb(w->ctx);
    return ERROR_SUCCESS;
}

void *tfmf_watch_cameras(tfmf_change_callback callback, void *context) {
    TFMFWatch *w = (TFMFWatch *)calloc(1, sizeof *w);
    CM_NOTIFY_FILTER f;
    if (!w) return NULL;
    w->cb = callback;
    w->ctx = context;
    memset(&f, 0, sizeof f);
    f.cbSize = sizeof f;
    f.FilterType = CM_NOTIFY_FILTER_TYPE_DEVICEINTERFACE;
    f.u.DeviceInterface.ClassGuid = TF_KSCATEGORY_VIDEO_CAMERA;
    if (CM_Register_Notification(&f, w, watch_cb, &w->handle) != CR_SUCCESS) {
        free(w);
        return NULL;
    }
    return w;
}

void tfmf_unwatch_cameras(void *watch) {
    TFMFWatch *w = (TFMFWatch *)watch;
    if (!w) return;
    CM_Unregister_Notification(w->handle);   // espera a que termine una devolución de llamada en curso
    free(w);
}
#endif
