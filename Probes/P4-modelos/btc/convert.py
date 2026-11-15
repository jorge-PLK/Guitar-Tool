"""Convierte BTC (vocabulario grande) a Core ML: ventana fija (1, 108, 144) log-CQT normalizada → logits (1, 108, 170).
Uso: convert.py [--precision fp16|fp32]. Log en out/convert.log."""
import argparse
import time
from collections import Counter

import numpy as np
import torch

import btc_common as C

ap = argparse.ArgumentParser()
ap.add_argument("--precision", default="fp16", choices=["fp16", "fp32"])
a = ap.parse_args()
log = C.setup_log("convert")
C.ensure_assets(log)
import coremltools as ct  # noqa: E402

log.info("torch %s, coremltools %s, numpy %s", torch.__version__, ct.__version__, np.__version__)


class Wrap(torch.nn.Module):
    def __init__(self, m):
        super().__init__()
        self.enc = m.self_attn_layers
        self.proj = m.output_layer.output_projection

    def forward(self, x):
        y, _ = self.enc(x)
        return self.proj(y)


model, mean, std = C.load_torch_model()
ref_model, _, _ = C.load_torch_model()
n_masks = C.patch_masks_fp16_safe(model)
log.info("parámetros %d, máscaras parcheadas %d, mean %.6f std %.6f",
         sum(p.numel() for p in model.parameters()), n_masks, mean, std)

# Ventana real de prueba: primeros 10 s de la mezcla de T1.
xs, sr = C.load_input("T1", "mix")
wav = C.to_mono_22k([x[:, : sr * 11] for x in xs], sr)
win, _ = C.normalize_windows(C.cqt_features(wav), mean, std)
x = torch.from_numpy(win[:1])
with torch.no_grad():
    y_ref = ref_model.output_layer.output_projection(ref_model.self_attn_layers(x)[0]).numpy()
    wrap = Wrap(model).eval()
    y_pat = wrap(x).numpy()
    log.info("parche de máscaras frente a original: dif máx %.3g", float(np.abs(y_pat - y_ref).max()))
    traced = torch.jit.trace(wrap, x)
ops = Counter(n.kind() for n in traced.inlined_graph.nodes() if n.kind().startswith("aten::"))
log.info("aten ops: %s", dict(ops))

prec = ct.precision.FLOAT16 if a.precision == "fp16" else ct.precision.FLOAT32
t0 = time.time()
ml = ct.convert(
    traced,
    inputs=[ct.TensorType(name="cqt", shape=(1, C.T, C.N_FEAT), dtype=np.float32)],
    outputs=[ct.TensorType(name="logits", dtype=np.float32)],
    convert_to="mlprogram",
    compute_precision=prec,
    compute_units=ct.ComputeUnit.CPU_AND_GPU,
    minimum_deployment_target=ct.target.macOS15,
)
log.info("ct.convert %.1f s", time.time() - t0)
ml.short_description = "BTC (ISMIR19) acordes, vocabulario grande 170 clases. Pesos no comerciales: uso personal."
ml.user_defined_metadata.update({
    "feature_mean": repr(mean), "feature_std": repr(std), "sample_rate": str(C.SR), "hop_length": str(C.HOP),
    "cqt_bins": str(C.N_BINS), "bins_per_octave": str(C.BPO), "frames_per_window": str(C.T),
    "frame_seconds": repr(C.FRAME_S), "vocabulary": ",".join(C.idx2voca()),
    "source": f"{C.BTC_URL}@{C.BTC_COMMIT} test/btc_model_large_voca.pt",
})
dst = C.OUT / "coreml" / f"BTC_large_voca_{a.precision}.mlpackage"
dst.parent.mkdir(parents=True, exist_ok=True)
ml.save(str(dst))
y_ml = ml.predict({"cqt": win[:1]})["logits"]
d = np.abs(y_ml - y_ref)
agree = float((y_ml.argmax(-1) == y_ref.argmax(-1)).mean())
size = sum(f.stat().st_size for f in dst.rglob("*") if f.is_file())
log.info("guardado %s (%.2f MB); ventana T1: dif máx %.4g media %.4g, argmax igual %.3f",
         dst, size / 1e6, d.max(), d.mean(), agree)
print(f"{dst.name}: {size / 1e6:.1f} MB · dif máx {d.max():.3g} media {d.mean():.3g} · argmax igual {agree:.3f}")
C.progress(f"convert {a.precision} ok, {size / 1e6:.1f} MB, ventana T1 argmax igual {agree:.3f}")
