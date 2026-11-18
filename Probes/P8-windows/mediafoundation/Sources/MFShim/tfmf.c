// Implementación de tfmf.h: IMFSinkWriter en C con COBJMACROS (prueba d del paso 4, Fase 7c).
#ifdef _WIN32
#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "tfmf.h"

#define W 640
#define H 360
#define FPS 30
#define SR 48000
#define FRAME_100NS (10000000LL / FPS)
#define AUDIO_PER_FRAME (SR / FPS)

#define CHECK(expr, name) do { hr = (expr); if (FAILED(hr)) { *step = name; goto done; } } while (0)

static HRESULT set_size(IMFMediaType *t, const GUID *key, UINT32 a, UINT32 b) {
    return IMFMediaType_SetUINT64(t, key, ((UINT64)a << 32) | b);
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

int32_t tfmf_write(const char *pathUTF8, int seconds, int hevc, int withAudio, const char **step) {
    HRESULT hr = S_OK;
    IMFAttributes *attr = NULL;
    IMFSinkWriter *w = NULL;
    IMFMediaType *vo = NULL, *vi = NULL, *ao = NULL, *ai = NULL;
    DWORD vs = 0, as = 0;
    BYTE *frame = NULL;
    short *pcm = NULL;
    int started = 0;
    *step = "ok";

    int n = MultiByteToWideChar(CP_UTF8, 0, pathUTF8, -1, NULL, 0);
    wchar_t *wpath = (wchar_t *)malloc(sizeof(wchar_t) * (size_t)n);
    MultiByteToWideChar(CP_UTF8, 0, pathUTF8, -1, wpath, n);

    CHECK(CoInitializeEx(NULL, COINIT_MULTITHREADED), "CoInitializeEx");
    CHECK(MFStartup(MF_VERSION, MFSTARTUP_FULL), "MFStartup");
    started = 1;
    CHECK(MFCreateAttributes(&attr, 1), "MFCreateAttributes");
    CHECK(IMFAttributes_SetUINT32(attr, &MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE), "SetUINT32 hw");
    CHECK(MFCreateSinkWriterFromURL(wpath, NULL, attr, &w), "MFCreateSinkWriterFromURL");

    // Vídeo: NV12 → H.264/HEVC.
    CHECK(MFCreateMediaType(&vo), "MFCreateMediaType vo");
    IMFMediaType_SetGUID(vo, &MF_MT_MAJOR_TYPE, &MFMediaType_Video);
    IMFMediaType_SetGUID(vo, &MF_MT_SUBTYPE, hevc ? &MFVideoFormat_HEVC : &MFVideoFormat_H264);
    IMFMediaType_SetUINT32(vo, &MF_MT_AVG_BITRATE, 2000000);
    IMFMediaType_SetUINT32(vo, &MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    set_size(vo, &MF_MT_FRAME_SIZE, W, H);
    set_size(vo, &MF_MT_FRAME_RATE, FPS, 1);
    set_size(vo, &MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    CHECK(IMFSinkWriter_AddStream(w, vo, &vs), hevc ? "AddStream HEVC" : "AddStream H.264");
    CHECK(MFCreateMediaType(&vi), "MFCreateMediaType vi");
    IMFMediaType_SetGUID(vi, &MF_MT_MAJOR_TYPE, &MFMediaType_Video);
    IMFMediaType_SetGUID(vi, &MF_MT_SUBTYPE, &MFVideoFormat_NV12);
    IMFMediaType_SetUINT32(vi, &MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    set_size(vi, &MF_MT_FRAME_SIZE, W, H);
    set_size(vi, &MF_MT_FRAME_RATE, FPS, 1);
    set_size(vi, &MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    CHECK(IMFSinkWriter_SetInputMediaType(w, vs, vi, NULL), hevc ? "SetInputMediaType NV12→HEVC" : "SetInputMediaType NV12→H.264");

    // Audio: PCM 16 bits 48 kHz estéreo → AAC 128 kb/s (16000 B/s).
    if (withAudio) {
        CHECK(MFCreateMediaType(&ao), "MFCreateMediaType ao");
        IMFMediaType_SetGUID(ao, &MF_MT_MAJOR_TYPE, &MFMediaType_Audio);
        IMFMediaType_SetGUID(ao, &MF_MT_SUBTYPE, &MFAudioFormat_AAC);
        IMFMediaType_SetUINT32(ao, &MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
        IMFMediaType_SetUINT32(ao, &MF_MT_AUDIO_SAMPLES_PER_SECOND, SR);
        IMFMediaType_SetUINT32(ao, &MF_MT_AUDIO_NUM_CHANNELS, 2);
        IMFMediaType_SetUINT32(ao, &MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 16000);
        CHECK(IMFSinkWriter_AddStream(w, ao, &as), "AddStream AAC");
        CHECK(MFCreateMediaType(&ai), "MFCreateMediaType ai");
        IMFMediaType_SetGUID(ai, &MF_MT_MAJOR_TYPE, &MFMediaType_Audio);
        IMFMediaType_SetGUID(ai, &MF_MT_SUBTYPE, &MFAudioFormat_PCM);
        IMFMediaType_SetUINT32(ai, &MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
        IMFMediaType_SetUINT32(ai, &MF_MT_AUDIO_SAMPLES_PER_SECOND, SR);
        IMFMediaType_SetUINT32(ai, &MF_MT_AUDIO_NUM_CHANNELS, 2);
        IMFMediaType_SetUINT32(ai, &MF_MT_AUDIO_BLOCK_ALIGNMENT, 4);
        IMFMediaType_SetUINT32(ai, &MF_MT_AUDIO_AVG_BYTES_PER_SECOND, SR * 4);
        CHECK(IMFSinkWriter_SetInputMediaType(w, as, ai, NULL), "SetInputMediaType PCM→AAC");
    }

    CHECK(IMFSinkWriter_BeginWriting(w), "BeginWriting");

    DWORD frameBytes = W * H * 3 / 2;
    frame = (BYTE *)malloc(frameBytes);
    pcm = (short *)malloc(sizeof(short) * 2 * AUDIO_PER_FRAME);
    for (int i = 0; i < seconds * FPS; i++) {
        // Barra que se mueve sobre gris; el fotograma 30 (t = 1 s) entero blanco.
        BYTE base = (i == FPS) ? 235 : 60;
        memset(frame, base, W * H);
        if (i != FPS) for (int y = 0; y < H; y++) memset(frame + y * W + (i * 8) % (W - 40), 200, 40);
        memset(frame + W * H, 128, W * H / 2);
        CHECK(write_buffer(w, vs, frame, frameBytes, i * FRAME_100NS, FRAME_100NS), "WriteSample vídeo");
        if (withAudio) {
            for (int k = 0; k < AUDIO_PER_FRAME; k++) {
                long idx = (long)i * AUDIO_PER_FRAME + k;
                double v = 0.1 * sin(2.0 * 3.14159265358979323846 * 440.0 * idx / SR);
                if (idx >= SR && idx < SR + 48) v = 0.9;   // clic de 1 ms en t = 1,000 s
                pcm[2 * k] = pcm[2 * k + 1] = (short)(v * 32767);
            }
            CHECK(write_buffer(w, as, (BYTE *)pcm, AUDIO_PER_FRAME * 4, i * FRAME_100NS, FRAME_100NS), "WriteSample audio");
        }
    }
    CHECK(IMFSinkWriter_Finalize(w), "Finalize");

done:
    free(frame);
    free(pcm);
    free(wpath);
    if (ai) IMFMediaType_Release(ai);
    if (ao) IMFMediaType_Release(ao);
    if (vi) IMFMediaType_Release(vi);
    if (vo) IMFMediaType_Release(vo);
    if (w) IMFSinkWriter_Release(w);
    if (attr) IMFAttributes_Release(attr);
    if (started) MFShutdown();
    return (int32_t)hr;
}
#else
#include "tfmf.h"
int32_t tfmf_write(const char *pathUTF8, int seconds, int hevc, int withAudio, const char **step) {
    (void)pathUTF8; (void)seconds; (void)hevc; (void)withAudio;
    *step = "solo Windows";
    return -1;
}
#endif
