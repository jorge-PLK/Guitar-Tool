#include "CResampler.h"
#include "r8brain/CDSPResampler.h"

struct tf_r8b {
    r8b::CDSPResampler24 *impl;
};

tf_r8b *tf_r8b_create(double src_rate, double dst_rate, int max_in_len) {
    try {
        tf_r8b *r = new tf_r8b;
        r->impl = new r8b::CDSPResampler24(src_rate, dst_rate, max_in_len);
        return r;
    } catch (...) {
        return nullptr;
    }
}

int tf_r8b_process(tf_r8b *r, double *in, int n, const double **out) {
    double *o = nullptr;
    int count = r->impl->process(in, n, o);
    *out = o;
    return count;
}

int tf_r8b_latency(const tf_r8b *r) { return r->impl->getLatency(); }

void tf_r8b_clear(tf_r8b *r) { r->impl->clear(); }

void tf_r8b_destroy(tf_r8b *r) {
    if (!r) return;
    delete r->impl;
    delete r;
}
