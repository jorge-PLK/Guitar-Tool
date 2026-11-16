"""Convierte el núcleo del Mel-Band RoFormer Lead_Rhythm_Guitar a Core ML (mlprogram, CPU+GPU, macOS 15).
Contrato y semántica: lr_common.py. Lanzar SIEMPRE bajo ../common/guard.py (límite 10 GB), con python -I.

  convert.py fp32|fp16             # comprueba núcleo vs modelo original, convierte, guarda y zipea en out/
  convert.py fp32|fp16 --install   # además copia el zip a App/Resources/Models

Salida: out/LeadRhythmMelRoformer_<prec>.mlpackage(.zip); log en out/convert.log."""
import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lr_common as C  # noqa: E402
from metrics import load_wav, sdr  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("precision", choices=["fp32", "fp16"])
ap.add_argument("--install", action="store_true")
args = ap.parse_args()
log = C.setup_log("convert")

import torch  # noqa: E402

log.info("==== convert %s", args.precision)
model, cfg = C.load_model(log)

# trozo real: Platero 157 s (guitar.wav, solo lectura)
PLATERO = Path("/Users/jorgefernandezhurtado/Music/ToneForge/El roce de tu cuerpo - Platero Y Tu/stems/guitar.wav")
g, sr = load_wav(PLATERO)
part = np.ascontiguousarray(g[:, 157 * sr: 157 * sr + C.CHUNK])
del g
spec = C.stft_spec(part)
with torch.no_grad():
    ts = torch.stft(torch.from_numpy(part), n_fft=C.N_FFT, hop_length=C.HOP, win_length=C.N_FFT,
                    window=torch.hann_window(C.N_FFT), return_complex=True)          # s F T
    ts = torch.view_as_real(ts).permute(1, 0, 2, 3).reshape(1, 2 * C.F, -1, 2).numpy()
    log.info("stft_spec vs torch.stft: max %.3g (T=%d)", np.abs(spec - ts).max(), spec.shape[2])
    ref = model(torch.from_numpy(part)[None])[0].numpy()                              # (2, CHUNK) original
    core, info = C.make_core(model)                                                   # parchea rotary
    log.info("núcleo: %s", info)
    mask_t = core(torch.from_numpy(spec)).numpy()
rec = C.run_chunk_np(part, lambda s: mask_t)
log.info("núcleo+numpy vs modelo original: max %.3g mean %.3g SDR %.1f dB", np.abs(rec - ref).max(),
         np.abs(rec - ref).mean(), sdr(rec, ref))

t0 = time.perf_counter()
with torch.no_grad():
    traced = torch.jit.trace(core, torch.from_numpy(spec), check_trace=False)
log.info("trace %.1f s", time.perf_counter() - t0)
aten = {}
for n in traced.inlined_graph.nodes():
    aten[n.kind()] = aten.get(n.kind(), 0) + 1
log.info("aten ops: %s", dict(sorted(aten.items(), key=lambda kv: -kv[1])[:30]))

import coremltools as ct  # noqa: E402

prec = ct.precision.FLOAT16 if args.precision == "fp16" else ct.precision.FLOAT32
t0 = time.perf_counter()
ml = ct.convert(
    traced,
    inputs=[ct.TensorType(name="spec", shape=tuple(spec.shape), dtype=np.float32)],
    outputs=[ct.TensorType(name="mask", dtype=np.float32)],
    convert_to="mlprogram",
    minimum_deployment_target=ct.target.macOS15,
    compute_precision=prec,
    compute_units=ct.ComputeUnit.CPU_AND_GPU,     # nunca ANE (ver memoria: colgó el Mac con BS-RoFormer)
)
ml.short_description = ("Mel-Band RoFormer Lead_Rhythm_Guitar (pesos anónimos de HF RandomFilteredStuff, openrail, "
                        "uso personal). spec [1,2050,301,2] (fila 2f+canal, STFT n_fft 2048 hop 441) -> mask "
                        "compleja [1,1,2050,301,2] de la guitarra solista; rítmica = entrada - solista.")
ml.author = "ToneForge (conversión local)"
ml.license = "openrail; checkpoint sha256 " + C.CKPT_SHA
ml.version = f"ep72-{C.HF_COMMIT[:8]}-{args.precision}"
name = C.PACKAGE.format(args.precision)
dst = C.OUT / name
if dst.exists():
    shutil.rmtree(dst)
ml.save(str(dst))
log.info("guardado %s en %.1f s", name, time.perf_counter() - t0)
ops = {}
for f in ml._mil_program.functions.values():
    for op in f.operations:
        ops[op.op_type] = ops.get(op.op_type, 0) + 1
log.info("ops MIL: %s", dict(sorted(ops.items(), key=lambda kv: -kv[1])[:30]))

y = ml.predict({"spec": spec})["mask"]
t0 = time.perf_counter()
y = ml.predict({"spec": spec})["mask"]
dt = time.perf_counter() - t0
rec2 = C.run_chunk_np(part, lambda s: y)
log.info("predict CPU_AND_GPU %.2f s/trozo; máscara vs torch: max %.3g mean %.3g; audio vs original: max %.3g "
         "mean %.3g SDR %.1f dB", dt, np.abs(y - mask_t).max(), np.abs(y - mask_t).mean(), np.abs(rec2 - ref).max(),
         np.abs(rec2 - ref).mean(), sdr(rec2, ref))

# zip reproducible (sin AppleDouble), como BasicPitch_nmp
for root, dirs, files in os.walk(dst):
    for n in files + dirs:
        os.utime(Path(root) / n, (C.FIXED_MTIME, C.FIXED_MTIME))
os.utime(dst, (C.FIXED_MTIME, C.FIXED_MTIME))
z = C.OUT / f"{name}.zip"
z.unlink(missing_ok=True)
subprocess.run(["/usr/bin/ditto", "-c", "-k", "--norsrc", "--noextattr", "--keepParent", str(dst), str(z)], check=True)
listing = subprocess.run(["/usr/bin/unzip", "-l", str(z)], check=True, capture_output=True, text=True).stdout
if "._" in listing:
    raise RuntimeError("el zip lleva ficheros AppleDouble ._*")
zsha, zbytes = C.sha256(z), z.stat().st_size
info = {"zip": z.name, "sha256": zsha, "bytes": zbytes, "sdr_chunk_vs_torch": round(sdr(rec2, ref), 2),
        "sec_per_chunk": round(dt, 3)}
log.info("zip %s", json.dumps(info))
json.dump(info, open(C.OUT / f"convert_{args.precision}.json", "w"), indent=1)
if args.install:
    shutil.copy2(z, C.WT / "App/Resources/Models" / z.name)
    log.info("instalado en App/Resources/Models")
print(f"{z.name}: {zbytes} B sha256 {zsha}; trozo SDR vs torch {info['sdr_chunk_vs_torch']} dB, "
      f"{dt:.2f} s/trozo" + ("  [instalado]" if args.install else ""))
