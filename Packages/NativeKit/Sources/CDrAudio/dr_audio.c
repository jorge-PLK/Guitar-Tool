// Implementación de CDrAudio.h sobre dr_wav, dr_flac y dr_mp3 (fuente vendorizada sin modificar).
#define DR_WAV_IMPLEMENTATION
#define DR_FLAC_IMPLEMENTATION
#define DR_MP3_IMPLEMENTATION
#include "dr_wav.h"
#include "dr_flac.h"
#include "dr_mp3.h"
#include "CDrAudio.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
static wchar_t *tfaudio_wide(const char *s) {
    int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
    if (n <= 0) return NULL;
    wchar_t *w = (wchar_t *)malloc(sizeof(wchar_t) * (size_t)n);
    if (w) MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n);
    return w;
}
#endif

struct tfaudio_reader {
    int kind;
    uint32_t sampleRate, channels;
    uint64_t frames;
    drwav wav;
    drflac *flac;
    drmp3 mp3;
};

/// Primeros bytes del fichero para elegir decodificador (sin probar a ciegas: dr_mp3 encuentra «tramas» en
/// cualquier ruido y un fichero corrupto acabaría leyéndose como MP3).
static int tfaudio_sniff(const char *path, unsigned char head[12]) {
    FILE *f = NULL;
#ifdef _WIN32
    wchar_t *w = tfaudio_wide(path);
    if (!w) return 0;
    f = _wfopen(w, L"rb");
    free(w);
#else
    f = fopen(path, "rb");
#endif
    if (!f) return 0;
    size_t n = fread(head, 1, 12, f);
    fclose(f);
    return n == 12;
}

static int tfaudio_detect(const unsigned char h[12]) {
    if (!memcmp(h, "RIFF", 4) || !memcmp(h, "RIFX", 4) || !memcmp(h, "RF64", 4) || !memcmp(h, "riff", 4) ||
        !memcmp(h, "FORM", 4)) return TFAUDIO_WAV;
    if (!memcmp(h, "fLaC", 4)) return TFAUDIO_FLAC;
    if (!memcmp(h, "ID3", 3) || (h[0] == 0xFF && (h[1] & 0xE0) == 0xE0)) return TFAUDIO_MP3;
    return -1;
}

tfaudio_reader *tfaudio_open(const char *path) {
    unsigned char head[12];
    if (!tfaudio_sniff(path, head)) return NULL;
    int kind = tfaudio_detect(head);
    if (kind < 0) return NULL;
    tfaudio_reader *r = (tfaudio_reader *)calloc(1, sizeof(tfaudio_reader));
    if (!r) return NULL;
    r->kind = kind;
    int ok = 0;
#ifdef _WIN32
    wchar_t *w = tfaudio_wide(path);
    if (!w) { free(r); return NULL; }
#endif
    switch (kind) {
    case TFAUDIO_WAV:
#ifdef _WIN32
        ok = drwav_init_file_w(&r->wav, w, NULL);
#else
        ok = drwav_init_file(&r->wav, path, NULL);
#endif
        if (ok) { r->sampleRate = r->wav.sampleRate; r->channels = r->wav.channels; r->frames = r->wav.totalPCMFrameCount; }
        break;
    case TFAUDIO_FLAC:
#ifdef _WIN32
        r->flac = drflac_open_file_w(w, NULL);
#else
        r->flac = drflac_open_file(path, NULL);
#endif
        ok = r->flac != NULL;
        if (ok) { r->sampleRate = r->flac->sampleRate; r->channels = r->flac->channels; r->frames = r->flac->totalPCMFrameCount; }
        break;
    case TFAUDIO_MP3:
#ifdef _WIN32
        ok = drmp3_init_file_w(&r->mp3, w, NULL);
#else
        ok = drmp3_init_file(&r->mp3, path, NULL);
#endif
        if (ok) {
            r->sampleRate = r->mp3.sampleRate;
            r->channels = r->mp3.channels;
            r->frames = drmp3_get_pcm_frame_count(&r->mp3);   // decodifica y vuelve al principio
            if (r->frames == 0) { drmp3_uninit(&r->mp3); ok = 0; }
        }
        break;
    }
#ifdef _WIN32
    free(w);
#endif
    if (!ok || r->channels == 0 || r->sampleRate == 0) {
        if (ok) tfaudio_close(r); else free(r);
        return NULL;
    }
    return r;
}

void tfaudio_close(tfaudio_reader *r) {
    if (!r) return;
    switch (r->kind) {
    case TFAUDIO_WAV: drwav_uninit(&r->wav); break;
    case TFAUDIO_FLAC: drflac_close(r->flac); break;
    case TFAUDIO_MP3: drmp3_uninit(&r->mp3); break;
    }
    free(r);
}

int tfaudio_kind_of(const tfaudio_reader *r) { return r->kind; }
uint32_t tfaudio_sample_rate(const tfaudio_reader *r) { return r->sampleRate; }
uint32_t tfaudio_channels(const tfaudio_reader *r) { return r->channels; }
uint64_t tfaudio_frame_count(const tfaudio_reader *r) { return r->frames; }

uint64_t tfaudio_read_f32(tfaudio_reader *r, float *out, uint64_t frames) {
    switch (r->kind) {
    case TFAUDIO_WAV: return drwav_read_pcm_frames_f32(&r->wav, frames, out);
    case TFAUDIO_FLAC: return drflac_read_pcm_frames_f32(r->flac, frames, out);
    case TFAUDIO_MP3: return drmp3_read_pcm_frames_f32(&r->mp3, frames, out);
    }
    return 0;
}

int tfaudio_seek(tfaudio_reader *r, uint64_t frame) {
    switch (r->kind) {
    case TFAUDIO_WAV: return drwav_seek_to_pcm_frame(&r->wav, frame) ? 1 : 0;
    case TFAUDIO_FLAC: return drflac_seek_to_pcm_frame(r->flac, frame) ? 1 : 0;
    case TFAUDIO_MP3: return drmp3_seek_to_pcm_frame(&r->mp3, frame) ? 1 : 0;
    }
    return 0;
}

struct tfaudio_writer {
    drwav wav;
    uint32_t channels;
    int bits;
    unsigned char *scratch;
    size_t scratchBytes;
};

tfaudio_writer *tfaudio_writer_open(const char *path, uint32_t sampleRate, uint32_t channels, int bits) {
    if (channels == 0 || sampleRate == 0 || (bits != 16 && bits != 24 && bits != 32)) return NULL;
    tfaudio_writer *w = (tfaudio_writer *)calloc(1, sizeof(tfaudio_writer));
    if (!w) return NULL;
    drwav_data_format fmt;
    fmt.container = drwav_container_riff;
    fmt.format = bits == 32 ? DR_WAVE_FORMAT_IEEE_FLOAT : DR_WAVE_FORMAT_PCM;
    fmt.channels = channels;
    fmt.sampleRate = sampleRate;
    fmt.bitsPerSample = (drwav_uint32)bits;
    int ok;
#ifdef _WIN32
    wchar_t *wp = tfaudio_wide(path);
    ok = wp ? drwav_init_file_write_w(&w->wav, wp, &fmt, NULL) : 0;
    free(wp);
#else
    ok = drwav_init_file_write(&w->wav, path, &fmt, NULL);
#endif
    if (!ok) { free(w); return NULL; }
    w->channels = channels;
    w->bits = bits;
    return w;
}

/// Float → entero como Core Audio: redondeo a la mitad lejos de cero (roundf) y recorte. Medido en el Mac con
/// AVAudioFile: ±0,5 LSB → ±1, ±2,5 LSB → ±3, 1,0 → 2^(b-1) − 1, −1,0 → −2^(b-1).
static int32_t tfaudio_quantize(float x, int bits) {
    const float scale = bits == 16 ? 32768.0f : 8388608.0f;
    const float hi = scale - 1.0f, lo = -scale;
    float v = roundf(x * scale);
    if (!(v >= lo)) v = lo;   // también NaN
    if (v > hi) v = hi;
    return (int32_t)v;
}

uint64_t tfaudio_writer_write_f32(tfaudio_writer *w, const float *in, uint64_t frames) {
    if (w->bits == 32) return drwav_write_pcm_frames(&w->wav, frames, in);
    const size_t bps = (size_t)w->bits / 8;
    const uint64_t block = 4096;
    uint64_t written = 0;
    size_t need = (size_t)block * w->channels * bps;
    if (w->scratchBytes < need) {
        unsigned char *p = (unsigned char *)realloc(w->scratch, need);
        if (!p) return 0;
        w->scratch = p;
        w->scratchBytes = need;
    }
    while (written < frames) {
        uint64_t n = frames - written < block ? frames - written : block;
        const float *src = in + written * w->channels;
        size_t count = (size_t)n * w->channels;
        for (size_t i = 0; i < count; i++) {
            int32_t q = tfaudio_quantize(src[i], w->bits);
            unsigned char *d = w->scratch + i * bps;
            d[0] = (unsigned char)(q & 0xFF);
            d[1] = (unsigned char)((q >> 8) & 0xFF);
            if (bps == 3) d[2] = (unsigned char)((q >> 16) & 0xFF);
        }
        uint64_t got = drwav_write_pcm_frames(&w->wav, n, w->scratch);
        written += got;
        if (got < n) break;
    }
    return written;
}

int tfaudio_writer_close(tfaudio_writer *w) {
    if (!w) return 0;
    int ok = drwav_uninit(&w->wav) == DRWAV_SUCCESS;
    free(w->scratch);
    free(w);
    return ok;
}
