"""Conversión del núcleo de BS-RoFormer SW (sin STFT/iSTFT).
Uso: convert.py coreml fp16|fp32 [--chunk 176400]   |   convert.py onnx fp32
Lanzar SIEMPRE con ../common/guard.py (límite 10 GB). Core ML se convierte y carga con CPU_AND_GPU.
Entrada del núcleo: 'spec' (2, 1025, T, 2) float32 = STFT del trozo [canal, frec, trama, re/im],
T = 1 + chunk//512 (1151 oficial; 345 con trozo de 4 s)
Salida: 'stems_spec' (12, 1025, T, 2) = espectro enmascarado [stem*2+canal, frec, trama, re/im]
Escribe out/coreml/*.mlpackage u out/onnx/*.onnx y registra en out/convert.log."""
import argparse
import time

import numpy as np

import sw_common as C
from metrics import load_wav

ap = argparse.ArgumentParser()
ap.add_argument("via", choices=["coreml", "onnx"])
ap.add_argument("precision", choices=["fp16", "fp32"])
ap.add_argument("--chunk", type=int, default=C.CHUNK, help="muestras por trozo (176400 = 4 s, T=345)")
args = ap.parse_args()
n_frames = 1 + args.chunk // C.HOP

log = C.setup_log("convert")
import sys  # noqa: E402

sys.excepthook = lambda t, v, tb: log.error("excepción no capturada", exc_info=(t, v, tb))
import torch  # noqa: E402

log.info("==== %s %s chunk %d (T=%d) (torch %s)", args.via, args.precision, args.chunk, n_frames,
         torch.__version__)
model, _ = C.load_model(log)

# trozo real de T1 (desde el segundo 60) para comprobar equivalencias
mix, _ = load_wav(C.TESTAUDIO / "T1" / "mix.wav")
chunk = mix[:, 60 * C.SR: 60 * C.SR + args.chunk]
spec = C.stft_np(chunk)
with torch.no_grad():
    ts = torch.view_as_real(torch.stft(torch.from_numpy(chunk), n_fft=C.N_FFT, hop_length=C.HOP,
                                       win_length=C.WIN, window=torch.hann_window(C.WIN),
                                       return_complex=True)).numpy()
    log.info("stft_np vs torch.stft: max %.3g", np.abs(spec - ts).max())
    ref = model(torch.from_numpy(chunk)[None])[0].numpy()                   # (6, 2, N), modelo sin tocar
    core = C.make_core(model, n_frames)                                      # parchea rotary
    core_out = core(torch.from_numpy(spec)).numpy()                          # (12, F, T, 2)
    rec = C.istft_np(core_out, args.chunk).reshape(6, 2, -1)
    log.info("núcleo+stft_np/istft_np vs modelo completo: max %.3g mean %.3g",
             np.abs(rec - ref).max(), np.abs(rec - ref).mean())

example = torch.from_numpy(spec)
t0 = time.perf_counter()
with torch.no_grad():
    traced = torch.jit.trace(core, example, check_trace=False)
log.info("trace %.1f s", time.perf_counter() - t0)

if args.via == "coreml":
    import coremltools as ct
    (C.OUT / "coreml").mkdir(exist_ok=True)
    prec = ct.precision.FLOAT16 if args.precision == "fp16" else ct.precision.FLOAT32
    t0 = time.perf_counter()
    ml = ct.convert(
        traced,
        inputs=[ct.TensorType(name="spec", shape=tuple(spec.shape), dtype=np.float32)],
        outputs=[ct.TensorType(name="stems_spec", dtype=np.float32)],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.macOS15,
        compute_precision=prec,
        compute_units=ct.ComputeUnit.CPU_AND_GPU,   # nunca ANE: su compilación colgó el Mac (18 GB)
    )
    ml.short_description = "BS-RoFormer SW (6 stems) núcleo sin STFT. Stems: " + ",".join(C.STEMS)
    dst = C.OUT / "coreml" / f"bs_roformer_sw_{args.precision}_T{n_frames}.mlpackage"
    ml.save(str(dst))
    log.info("coreml guardado %s en %.1f s", dst.name, time.perf_counter() - t0)
    ops = {}
    for f in ml._mil_program.functions.values():
        for op in f.operations:
            ops[op.op_type] = ops.get(op.op_type, 0) + 1
    log.info("ops MIL: %s", dict(sorted(ops.items(), key=lambda kv: -kv[1])[:25]))
    t0 = time.perf_counter()
    y = ml.predict({"spec": spec})["stems_spec"]
    log.info("predict CPU_AND_GPU %.1f s; vs núcleo torch: max %.3g mean %.3g", time.perf_counter() - t0,
             np.abs(y - core_out).max(), np.abs(y - core_out).mean())
    rec2 = C.istft_np(y, args.chunk).reshape(6, 2, -1)
    for k, s in enumerate(C.STEMS):
        num = np.sum(ref[k] ** 2) + 1e-10
        den = np.sum((ref[k] - rec2[k]) ** 2) + 1e-10
        log.info("  trozo %s SDR vs torch %.1f dB", s, 10 * np.log10(num / den))
    print(f"ok {dst.name}; ver out/convert.log")
else:
    (C.OUT / "onnx").mkdir(exist_ok=True)
    dst = C.OUT / "onnx" / "bs_roformer_sw_fp32.onnx"
    t0 = time.perf_counter()
    # Se exporta el módulo ya trazado y sin plegado de constantes: exportar `core` con el exportador
    # TorchScript lo volvía a trazar y el proceso moría por memoria (exit 137) con 18 GB.
    del model, mix
    import gc
    gc.collect()
    torch.onnx.export(traced, (example,), str(dst), input_names=["spec"], output_names=["stems_spec"],
                      opset_version=18, dynamo=False, do_constant_folding=False)
    log.info("onnx guardado %s en %.1f s", dst.name, time.perf_counter() - t0)
    import onnxruntime as ort
    sess = ort.InferenceSession(str(dst), providers=["CPUExecutionProvider"])
    t0 = time.perf_counter()
    y = sess.run(["stems_spec"], {"spec": spec})[0]
    log.info("ort CPU %.1f s; vs núcleo torch: max %.3g mean %.3g", time.perf_counter() - t0,
             np.abs(y - core_out).max(), np.abs(y - core_out).mean())
    print(f"ok {dst.name}; ver out/convert.log")
