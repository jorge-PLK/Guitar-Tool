"""WAV de escucha: 30 s de guitarra (ventana de más energía de la guitarra real), igualados a -16 LUFS.
Uso: listen.py <modelo> T1 [T2 T3]
Salida: out/listen/<T>_guitar_{real,bs_roformer_sw,<modelo>}_-16LUFS.wav"""
import sys
from pathlib import Path

import numpy as np
import pyloudnorm as pyln

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "common"))
from metrics import load_wav, loudest_window, save_wav  # noqa: E402

MAIN = Path("/Volumes/SSD Mac/Personales/Guitar Tool")
TESTAUDIO = MAIN / "Probes/testaudio/out"
SW = MAIN / "Probes/P4-modelos/bs_roformer_sw/out/ref_torch"
OUT = HERE / "out"
model = sys.argv[1]
for t in sys.argv[2:]:
    real = TESTAUDIO / t / "stems" / "guitar.wav"
    start = loudest_window(real, 30.0)
    for lab, p in [("real", real), ("bs_roformer_sw", SW / t / "guitar.wav"), (model, OUT / "sep" / model / t / "guitar.wav")]:
        x, sr = load_wav(p)
        a = int(start * sr)
        x = x[:, a:a + 30 * sr].astype(np.float64)
        y = pyln.normalize.loudness(x.T, pyln.Meter(sr).integrated_loudness(x.T), -16.0).T
        dst = OUT / "listen" / f"{t}_guitar_{lab}_-16LUFS.wav"
        save_wav(dst, y, sr)
        print(f"{dst} (desde {start:.0f} s, pico {np.abs(y).max():.2f})")
