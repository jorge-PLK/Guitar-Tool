"""P7 paso 5: frecuencia de corte (-60 dB vs pico) y % de energía > 16 kHz de un WAV PCM16."""
import sys
import wave

import numpy as np

CORTE_DB = 60.0  # caída respecto al pico del espectro medio
F_ALTA_HZ = 16000.0
N = 8192

w = wave.open(sys.argv[1])
sr, ch, n = w.getframerate(), w.getnchannels(), w.getnframes()
x = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float32) / 32768.0
x = x.reshape(-1, ch).mean(axis=1)
win = np.hanning(N).astype(np.float32)
acc = np.zeros(N // 2 + 1)
cnt = 0
for i in range(0, len(x) - N, N // 2):
    acc += np.abs(np.fft.rfft(x[i:i + N] * win)) ** 2
    cnt += 1
p = acc / cnt
f = np.fft.rfftfreq(N, 1 / sr)
db = 10 * np.log10(p + 1e-20)
# suaviza 1/3 de octava aprox. con media móvil de 32 bins (~170 Hz) para evitar huecos puntuales
k = 32
dbs = 10 * np.log10(np.convolve(p, np.ones(k) / k, mode="same") + 1e-20)
peak = dbs.max()
idx = np.where((dbs < peak - CORTE_DB) & (f > 1000))[0]
cut = f[idx[0]] if len(idx) else None
# último bin con energía por encima de -60 dB (cota superior de contenido)
above = np.where(dbs >= peak - CORTE_DB)[0]
top = f[above[-1]]
hi = p[f > F_ALTA_HZ].sum() / p.sum() * 100
print(f"{sys.argv[1].split('/')[-2]} sr={sr} pico={peak:.1f}dB primera_caida_-60dB={cut:.0f}Hz ultimo_bin_>-60dB={top:.0f}Hz energia>16kHz={hi:.5f}%")
