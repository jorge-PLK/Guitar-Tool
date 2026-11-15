"""Deduce el contrato del Core ML de sunnymead ([1,4,1025,256] -> [1,6,4,1025,256]) probando hipótesis
sobre un trozo real de T1 (256 tramas = 130560 muestras, STFT center=True) frente al modelo PyTorch
original a la misma longitud. Hipótesis: orden de los 4 canales y salida = espectro o máscara.
Uso: probe_sunnymead.py   (con ../common/guard.py; CPU_AND_GPU)"""
import sys

import numpy as np

import sw_common as C
from metrics import load_wav, sdr

log = C.setup_log("probe_sunnymead")
sys.excepthook = lambda t, v, tb: log.error("excepción no capturada", exc_info=(t, v, tb))
import torch  # noqa: E402
import coremltools as ct  # noqa: E402

N = 255 * C.HOP                                       # 130560 -> T = 256
mix, _ = load_wav(C.TESTAUDIO / "T1" / "mix.wav")
chunk = mix[:, 60 * C.SR: 60 * C.SR + N]
model, _ = C.load_model(log)
with torch.no_grad():
    ref = model(torch.from_numpy(chunk)[None])[0].numpy()          # (6, 2, N)
del model
spec = C.stft_np(chunk)                                            # (2, F, 256, 2) [canal, f, t, re/im]
mdl = ct.models.MLModel(str(C.OUT / "coreml_pub_sunnymead" / "bs_roformer_6stem.mlpackage"),
                        compute_units=ct.ComputeUnit.CPU_AND_GPU)
LAYOUTS = {  # canal k del tensor de 4 -> (canal estéreo, re/im)
    "Lre,Lim,Rre,Rim": [(0, 0), (0, 1), (1, 0), (1, 1)],
    "Lre,Rre,Lim,Rim": [(0, 0), (1, 0), (0, 1), (1, 1)],
}
best = None
for lname, lay in LAYOUTS.items():
    x = np.stack([spec[c, :, :, ri] for c, ri in lay])[None].astype(np.float32)   # 1,4,F,T
    y = mdl.predict({"spectrogram": x})["stems_spectrogram"][0]                  # 6,4,F,T
    for mode in ("espectro", "mascara"):
        S = np.zeros((6, 2, C.N_FREQ, 256, 2), np.float32)
        for k, (c, ri) in enumerate(lay):
            S[:, c, :, :, ri] = y[:, k]
        if mode == "mascara":
            mr, mi = S[..., 0].copy(), S[..., 1].copy()
            sr_, si_ = spec[None, ..., 0], spec[None, ..., 1]
            S = np.stack([sr_ * mr - si_ * mi, sr_ * mi + si_ * mr], -1)
        rec = C.istft_np(S.reshape(12, C.N_FREQ, 256, 2), N).reshape(6, 2, -1)
        sd = [sdr(rec[i], ref[i]) for i in range(6)]
        log.info("%s / %s: SDR vs torch por stem %s", lname, mode, [round(v, 1) for v in sd])
        if best is None or np.mean(sd) > best[0]:
            best = (float(np.mean(sd)), lname, mode, sd)
print(f"mejor: {best[1]} / {best[2]}  SDR por stem {[round(v, 1) for v in best[3]]}")
