"""WAV de escucha para Jorge: tramo de 30 s de la mezcla con clics en los pulsos (1 kHz) y en los downbeats
(2 kHz, más fuerte), uno por tema y vía. Uso: clicks.py [vía ...] (por defecto torch coreml_comm).
Sale en out/listen/<tema>_<vía>_clicks.wav."""
import sys

import numpy as np
import soundfile as sf

import bt_common as C

START, DUR = 30.0, 30.0
vias = sys.argv[1:] or ["torch", "coreml_comm"]
for tema in C.TEMAS:
    sig, sr = C.load_audio(tema)
    seg = sig[int(START * sr):int((START + DUR) * sr)]
    seg = seg if seg.ndim == 2 else seg[:, None]
    for via in vias:
        out = 0.7 * seg.copy()
        beats = C.load_times(C.OUT / "beats" / via / f"{tema}.beats.txt")
        downs = set(np.round(C.load_times(C.OUT / "beats" / via / f"{tema}.downbeats.txt"), 3))
        n = int(0.03 * sr)
        env = np.exp(-np.arange(n) / (0.006 * sr))
        for b in beats[(beats >= START) & (beats < START + DUR)]:
            down = round(float(b), 3) in downs
            click = (0.6 if down else 0.35) * env * np.sin(2 * np.pi * (2000 if down else 1000) * np.arange(n) / sr)
            i = int((b - START) * sr)
            m = min(n, len(out) - i)
            out[i:i + m] += click[:m, None]
        p = C.OUT / "listen" / f"{tema}_{via}_clicks.wav"
        p.parent.mkdir(parents=True, exist_ok=True)
        sf.write(p, np.clip(out, -1, 1), sr, subtype="PCM_16")
        print(p)
