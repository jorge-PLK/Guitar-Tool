#include "CSignalsmith.h"
#include "signalsmith-stretch/signalsmith-stretch.h"

struct tf_stretch {
    signalsmith::stretch::SignalsmithStretch<float> impl;
};

tf_stretch *tf_stretch_create(int channels, float sample_rate) {
    try {
        tf_stretch *s = new tf_stretch;
        s->impl.presetDefault(channels, sample_rate);
        return s;
    } catch (...) {
        return nullptr;
    }
}

void tf_stretch_set_transpose_factor(tf_stretch *s, float factor, float tonality_limit) {
    s->impl.setTransposeFactor(factor, tonality_limit);
}

void tf_stretch_process(tf_stretch *s, const float *const *in, int in_n, float *const *out, int out_n) {
    s->impl.process(in, in_n, out, out_n);
}

int tf_stretch_input_latency(const tf_stretch *s) { return s->impl.inputLatency(); }
int tf_stretch_output_latency(const tf_stretch *s) { return s->impl.outputLatency(); }
int tf_stretch_output_seek_length(const tf_stretch *s, float rate) { return s->impl.outputSeekLength(rate); }

void tf_stretch_output_seek(tf_stretch *s, const float *const *in, int in_n) { s->impl.outputSeek(in, in_n); }

void tf_stretch_seek(tf_stretch *s, const float *const *in, int in_n, double rate) { s->impl.seek(in, in_n, rate); }

void tf_stretch_flush(tf_stretch *s, float *const *out, int out_n, float rate) { s->impl.flush(out, out_n, rate); }

int tf_stretch_block_samples(const tf_stretch *s) { return s->impl.blockSamples(); }
int tf_stretch_interval_samples(const tf_stretch *s) { return s->impl.intervalSamples(); }

void tf_stretch_reset(tf_stretch *s) { s->impl.reset(); }
void tf_stretch_destroy(tf_stretch *s) { delete s; }
