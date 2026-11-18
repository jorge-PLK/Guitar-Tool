// Implementación de tfma.h sobre miniaudio 0.11.26 (dominio público / MIT-0, fuente vendorizada).
#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
#include "tfma.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
int64_t tfma_qpc(void) { LARGE_INTEGER c; QueryPerformanceCounter(&c); return c.QuadPart; }
int64_t tfma_qpc_frequency(void) { LARGE_INTEGER f; QueryPerformanceFrequency(&f); return f.QuadPart; }
static void tfma_sleep(uint32_t ms) { Sleep(ms); }
static wchar_t *tfma_wide(const char *s) {
    int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
    wchar_t *w = (wchar_t *)malloc(sizeof(wchar_t) * (size_t)n);
    MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n);
    return w;
}
#else
#include <time.h>
#include <unistd.h>
int64_t tfma_qpc(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (int64_t)t.tv_sec * 1000000000 + t.tv_nsec; }
int64_t tfma_qpc_frequency(void) { return 1000000000; }
static void tfma_sleep(uint32_t ms) { usleep(ms * 1000); }
#endif

typedef struct { tfma_period_cb cb; void *user; } tfma_user;

static void tfma_data(ma_device *d, void *out, const void *in, ma_uint32 frames) {
    (void)in;
    int64_t t = tfma_qpc();
    tfma_user *u = (tfma_user *)d->pUserData;
    if (out) memset(out, 0, frames * ma_get_bytes_per_frame(d->playback.format, d->playback.channels));
    if (u && u->cb) u->cb(u->user, frames, t);
}

int tfma_wasapi_report(void) {
    ma_backend backends[] = { ma_backend_wasapi };
    ma_context ctx;
    ma_result r = ma_context_init(backends, 1, NULL, &ctx);
    if (r != MA_SUCCESS) {
        printf("  ma_context_init(wasapi) = %d (%s)\n", r, ma_result_description(r));
        return r < 0 ? r : -r;
    }
    ma_device_info *pb = NULL, *cap = NULL;
    ma_uint32 npb = 0, ncap = 0;
    r = ma_context_get_devices(&ctx, &pb, &npb, &cap, &ncap);
    if (r != MA_SUCCESS) {
        printf("  ma_context_get_devices = %d (%s)\n", r, ma_result_description(r));
        ma_context_uninit(&ctx);
        return r < 0 ? r : -r;
    }
    printf("  contexto %s: %u salidas, %u entradas\n", ma_get_backend_name(ctx.backend), npb, ncap);
    for (ma_uint32 i = 0; i < npb; i++) printf("    salida %u: %s%s\n", i, pb[i].name, pb[i].isDefault ? " (por defecto)" : "");
    for (ma_uint32 i = 0; i < ncap; i++) printf("    entrada %u: %s%s\n", i, cap[i].name, cap[i].isDefault ? " (por defecto)" : "");
    fflush(stdout);
    ma_context_uninit(&ctx);
    return (int)(npb + ncap);
}

int tfma_null_playback(uint32_t sampleRate, uint32_t periodFrames, uint32_t milliseconds, tfma_period_cb cb, void *user) {
    ma_backend backends[] = { ma_backend_null };
    ma_context ctx;
    ma_result r = ma_context_init(backends, 1, NULL, &ctx);
    if (r != MA_SUCCESS) return r < 0 ? r : -r;
    tfma_user u = { cb, user };
    ma_device_config cfg = ma_device_config_init(ma_device_type_playback);
    cfg.playback.format = ma_format_f32;
    cfg.playback.channels = 2;
    cfg.sampleRate = sampleRate;
    cfg.periodSizeInFrames = periodFrames;
    cfg.dataCallback = tfma_data;
    cfg.pUserData = &u;
    ma_device dev;
    r = ma_device_init(&ctx, &cfg, &dev);
    if (r == MA_SUCCESS) {
        r = ma_device_start(&dev);
        if (r == MA_SUCCESS) tfma_sleep(milliseconds);
        ma_device_uninit(&dev);
    }
    ma_context_uninit(&ctx);
    return r == MA_SUCCESS ? 0 : (r < 0 ? r : -r);
}

int tfma_wasapi_duplex(uint32_t periodFrames, uint32_t milliseconds, tfma_period_cb cb, void *user) {
    ma_backend backends[] = { ma_backend_wasapi };
    ma_context ctx;
    ma_result r = ma_context_init(backends, 1, NULL, &ctx);
    if (r != MA_SUCCESS) return r < 0 ? r : -r;
    tfma_user u = { cb, user };
    ma_device_config cfg = ma_device_config_init(ma_device_type_duplex);
    cfg.playback.format = ma_format_f32;
    cfg.playback.channels = 2;
    cfg.capture.format = ma_format_f32;
    cfg.capture.channels = 0; /* nativo */
    cfg.sampleRate = 48000;
    cfg.periodSizeInFrames = periodFrames;
    cfg.performanceProfile = ma_performance_profile_low_latency;
    cfg.wasapi.noAutoConvertSRC = MA_TRUE;
    cfg.dataCallback = tfma_data;
    cfg.pUserData = &u;
    ma_device dev;
    r = ma_device_init(&ctx, &cfg, &dev);
    printf("  ma_device_init(dúplex wasapi compartido, 48 kHz, %u) = %d (%s)\n", periodFrames, r, ma_result_description(r));
    if (r == MA_SUCCESS) {
        printf("    salida «%s», entrada «%s», periodo interno %u, %u ch de entrada\n", dev.playback.name, dev.capture.name,
               dev.playback.internalPeriodSizeInFrames, dev.capture.internalChannels);
        fflush(stdout);
        r = ma_device_start(&dev);
        if (r == MA_SUCCESS) tfma_sleep(milliseconds);
        ma_device_uninit(&dev);
    }
    fflush(stdout);
    ma_context_uninit(&ctx);
    return r == MA_SUCCESS ? 0 : (r < 0 ? r : -r);
}

int tfma_write_wav(const char *pathUTF8, uint32_t sampleRate, uint32_t frames) {
    ma_encoder_config cfg = ma_encoder_config_init(ma_encoding_format_wav, ma_format_f32, 2, sampleRate);
    ma_encoder enc;
#ifdef _WIN32
    wchar_t *w = tfma_wide(pathUTF8);
    ma_result r = ma_encoder_init_file_w(w, &cfg, &enc);
    free(w);
#else
    ma_result r = ma_encoder_init_file(pathUTF8, &cfg, &enc);
#endif
    if (r != MA_SUCCESS) return r < 0 ? r : -r;
    float *buf = (float *)malloc(sizeof(float) * 2 * frames);
    for (uint32_t i = 0; i < frames; i++) {
        float v = 0.125f * (float)sin(2.0 * 3.14159265358979323846 * 1000.0 * i / sampleRate);
        buf[2 * i] = v;
        buf[2 * i + 1] = v;
    }
    ma_uint64 written = 0;
    r = ma_encoder_write_pcm_frames(&enc, buf, frames, &written);
    free(buf);
    ma_encoder_uninit(&enc);
    if (r != MA_SUCCESS) return r < 0 ? r : -r;
    return written == frames ? 0 : -1000;
}

int tfma_decode(const char *pathUTF8, uint64_t *frames, uint32_t *sampleRate, uint32_t *channels,
                double *rms, double *peak, int64_t *firstAbove) {
    ma_decoder_config cfg = ma_decoder_config_init(ma_format_f32, 0, 0);
    ma_decoder dec;
#ifdef _WIN32
    wchar_t *w = tfma_wide(pathUTF8);
    ma_result r = ma_decoder_init_file_w(w, &cfg, &dec);
    free(w);
#else
    ma_result r = ma_decoder_init_file(pathUTF8, &cfg, &dec);
#endif
    if (r != MA_SUCCESS) return r < 0 ? r : -r;
    ma_format fmt; ma_uint32 ch, sr;
    ma_decoder_get_data_format(&dec, &fmt, &ch, &sr, NULL, 0);
    float buf[4096 * 8];
    ma_uint32 chunk = 4096;
    uint64_t total = 0;
    double sum = 0, pk = 0;
    int64_t first = -1;
    for (;;) {
        ma_uint64 got = 0;
        r = ma_decoder_read_pcm_frames(&dec, buf, ch <= 8 ? chunk : 1, &got);
        for (ma_uint64 i = 0; i < got; i++) {
            double v = buf[i * ch];
            sum += v * v;
            if (fabs(v) > pk) pk = fabs(v);
            if (first < 0 && fabs(v) > 0.01) first = (int64_t)(total + i);
        }
        total += got;
        if (got == 0 || r != MA_SUCCESS) break;
    }
    ma_decoder_uninit(&dec);
    *frames = total;
    *sampleRate = sr;
    *channels = ch;
    *rms = total ? sqrt(sum / (double)total) : 0;
    *peak = pk;
    *firstAbove = first;
    return 0;
}
