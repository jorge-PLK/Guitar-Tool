"""Fixtures de referencia de la Fase 2 (StudyKit: pulso, acordes, tonalidad) para validar los ports a Swift.

Uso (cada etapa en su propio proceso, las de modelo bajo el vigilante):
    PY=Tools/py/.venv/bin/python
    $PY Probes/P4-modelos/common/guard.py --limit-gb 10 --log Probes/P4-modelos/fixtures/out/guard_<etapa>.log -- \
        $PY Probes/P4-modelos/fixtures/make_fase2_fixtures.py --stage <etapa>
Etapas, en orden: audio · btc (Core ML FP16 ANE) · beat (mlmodelc comunitario CPU+GPU) · key (T1–T3 completos,
solo librosa) · readme. `--stage all` las encadena en un proceso (no recomendado: mide peor la memoria).

Reutiliza btc/btc_common.py y beat_this/bt_common.py (mismo preproceso, troceado y postproceso que P4).
Escribe en Packages/StudyKit/Tests/StudyKitTests/Fixtures/ y deja el log y descargas en fixtures/out/."""
from __future__ import annotations

import argparse
import json
import logging
import sys
import traceback
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
P4 = HERE.parent
REPO = P4.parents[1]
sys.path[:0] = [str(P4 / "btc"), str(P4 / "beat_this")]
import btc_common as BC  # noqa: E402
import bt_common as BT  # noqa: E402

FIX = REPO / "Packages" / "StudyKit" / "Tests" / "StudyKitTests" / "Fixtures"
WORK = HERE / "out"
STEMS_T1 = P4 / "bs_roformer_sw" / "out" / "stems" / "T1"            # = conv/coremlpub_cpu_gpu/T1 (idénticos)
STEMS_P4 = P4 / "bs_roformer_sw" / "out" / "conv" / "coremlpub_cpu_gpu"  # entrada de BTC en P4
MIX_T1 = REPO / "Probes" / "testaudio" / "out" / "T1" / "mix.wav"
P4_PRED = P4 / "btc" / "out" / "pred" / "coreml_ane_fp16"               # .npz de P4 (stems, ANE FP16)

START_S = 60.0       # tramo con armonía clara
DUR_S = 12.0         # 30 s no caben en 2,5 MB (ver README)
STEREO_S = 2.0
MEL_URL = f"https://huggingface.co/{BT.ONNX_REPO}/resolve/{BT.ONNX_SHA}/mel-filterbank.bin"

# Temperley (2007), perfiles Kostka-Payne (los de music21 TemperleyKostkaPayne), índice 0 = tónica.
TKP_MAJOR = [0.748, 0.060, 0.488, 0.082, 0.670, 0.460, 0.096, 0.715, 0.104, 0.366, 0.057, 0.400]
TKP_MINOR = [0.712, 0.084, 0.474, 0.618, 0.049, 0.460, 0.105, 0.747, 0.404, 0.067, 0.133, 0.330]
# Notas de cada calidad (semitonos sobre la raíz), mismo orden que el vocabulario de BTC.
QUALITY_PCS = {"min": [0, 3, 7], "maj": [0, 4, 7], "dim": [0, 3, 6], "aug": [0, 4, 8], "min6": [0, 3, 7, 9],
               "maj6": [0, 4, 7, 9], "min7": [0, 3, 7, 10], "minmaj7": [0, 3, 7, 11], "maj7": [0, 4, 7, 11],
               "7": [0, 4, 7, 10], "dim7": [0, 3, 6, 9], "hdim7": [0, 3, 6, 10], "sus2": [0, 2, 7],
               "sus4": [0, 5, 7]}
KEY_NAMES = [f"{r}:maj" for r in BC.ROOTS] + [f"{r}:min" for r in BC.ROOTS]

ap = argparse.ArgumentParser()
ap.add_argument("--stage", required=True, choices=["audio", "btc", "beat", "key", "readme", "all"])
a = ap.parse_args()

WORK.mkdir(parents=True, exist_ok=True)
FIX.mkdir(parents=True, exist_ok=True)
log = logging.getLogger("fixtures")
log.setLevel(logging.INFO)
_h = logging.FileHandler(WORK / "make.log")
_h.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
log.addHandler(_h)
sys.excepthook = lambda et, ev, tb: (log.error("EXCEPCIÓN:\n%s", "".join(traceback.format_exception(et, ev, tb))),
                                     sys.__excepthook__(et, ev, tb))
log.info("=== etapa %s ===", a.stage)


def save_f32(name: str, arr: np.ndarray) -> None:
    np.ascontiguousarray(arr, dtype="<f4").tofile(FIX / name)
    log.info("%s %s float32 %d B", name, arr.shape, (FIX / name).stat().st_size)


def save_i32(name: str, arr: np.ndarray) -> None:
    np.ascontiguousarray(arr, dtype="<i4").tofile(FIX / name)
    log.info("%s %s int32 %d B", name, arr.shape, (FIX / name).stat().st_size)


def save_json(path: Path, obj) -> None:
    path.write_text(json.dumps(obj, indent=1, ensure_ascii=False) + "\n")


def read_wav(name: str) -> np.ndarray:
    """Lee un WAV PCM 16 del fixture como float32 = muestra/32768 (igual que AVAudioFile)."""
    import soundfile as sf
    x, sr = sf.read(str(FIX / name), dtype="float32")
    assert sr == BC.SR, sr
    return x


def cqt_abs(wav: np.ndarray) -> np.ndarray:
    """|CQT| crudo (144, T): mismo troceado de 10 s que btc_common.cqt_features (que es su log + 1e-6)."""
    import librosa
    step = int(BC.SR * BC.INST_LEN)
    parts, cur = [], 0
    while len(wav) > cur + step:
        parts.append(librosa.cqt(wav[cur:cur + step], sr=BC.SR, n_bins=BC.N_BINS, bins_per_octave=BC.BPO,
                                 hop_length=BC.HOP))
        cur += step
    parts.append(librosa.cqt(wav[cur:], sr=BC.SR, n_bins=BC.N_BINS, bins_per_octave=BC.BPO, hop_length=BC.HOP))
    return np.abs(np.concatenate(parts, axis=1)).astype(np.float32)


def fold_chroma(cabs: np.ndarray) -> np.ndarray:
    """(144, T) → (12, T): bin k (fmin C1, 24 por octava) va a la clase (k // 2) % 12, 0 = C."""
    return cabs.reshape(BC.N_BINS // 2, 2, -1).sum(1).reshape(BC.N_BINS // 24, 12, -1).sum(0)


def segments(pred_flat: np.ndarray, n_valid: int) -> list[tuple[float, float, int]]:
    """Segmentos exactos (sin redondear) de las tramas válidas; equivale a frames_to_lab."""
    p = pred_flat[:n_valid]
    out, s = [], 0
    for i in range(1, n_valid + 1):
        if i == n_valid or p[i] != p[s]:
            out.append((s * BC.FRAME_S, i * BC.FRAME_S, int(p[s])))
            s = i
    return out


def chord_histogram(segs) -> np.ndarray:
    h = np.zeros(12)
    for st, en, idx in segs:
        if idx >= 168:  # X (168) y N (169) fuera
            continue
        root, q = divmod(idx, 14)
        for iv in QUALITY_PCS[BC.QUALITIES[q]]:
            h[(root + iv) % 12] += en - st
    return h


def pearson(x: np.ndarray, y: np.ndarray) -> float:
    x, y = x - x.mean(), y - y.mean()
    d = np.sqrt((x * x).sum() * (y * y).sum())
    return float((x * y).sum() / d) if d > 0 else 0.0


def key_estimate(chroma12: np.ndarray, hist12: np.ndarray) -> dict:
    scores = []
    for prof in (TKP_MAJOR, TKP_MINOR):
        for t in range(12):
            pr = np.roll(np.asarray(prof), t)  # pr[pc] = prof[(pc - t) % 12]
            scores.append(0.5 * pearson(chroma12, pr) + 0.5 * pearson(hist12, pr))
    order = np.argsort(scores)[::-1]
    return {"chroma": [float(v) for v in chroma12], "histogram": [float(v) for v in hist12],
            "scores": [float(v) for v in scores], "key_index": int(order[0]), "key": KEY_NAMES[order[0]],
            "alternative_index": int(order[1]), "alternative": KEY_NAMES[order[1]],
            "confidence": float(scores[order[0]] - scores[order[1]])}


def versions() -> dict:
    import importlib
    v = {}
    for m in ("numpy", "librosa", "soxr", "soundfile", "torch", "torchaudio", "coremltools", "scipy"):
        try:
            v[m] = importlib.import_module(m).__version__
        except Exception as e:  # informativo
            v[m] = f"? ({e!r})"
    return v


# ---------------------------------------------------------------- etapas
def stage_audio() -> None:
    import librosa
    import soundfile as sf
    import soxr
    i0, n = int(START_S * 44100), int(DUR_S * 44100)
    stems = []
    for s in BC.STEMS_NO_VOX_DRUMS:
        x, sr = sf.read(str(STEMS_T1 / f"{s}.wav"), dtype="float32", always_2d=True, start=i0, frames=n)
        assert sr == 44100
        stems.append(x)
    harm = np.sum(stems, axis=0)                                    # (n, 2) suma de stems a 44,1 kHz
    peak = float(np.abs(harm).max())
    log.info("suma armónica: pico %.3f", peak)
    assert peak < 1.0, "la suma satura en PCM 16"
    harm22 = librosa.resample(harm.mean(1), orig_sr=44100, target_sr=BC.SR)   # soxr_hq, como btc_common
    sf.write(str(FIX / "harm_22k.wav"), harm22, BC.SR, subtype="PCM_16")
    sf.write(str(FIX / "harm_44k_stereo.wav"), harm[:int(STEREO_S * 44100)], 44100, subtype="PCM_16")
    mix, sr = sf.read(str(MIX_T1), dtype="float64", always_2d=True, start=i0, frames=n)
    mix22 = soxr.resample(mix.mean(1), in_rate=sr, out_rate=BT.SR)            # como bt_common.to_mono_22k
    sf.write(str(FIX / "mix_22k.wav"), mix22, BT.SR, subtype="PCM_16")
    log.info("audio: harm_22k %d, harm_44k_stereo %s, mix_22k %d muestras", len(harm22),
             harm[:int(STEREO_S * 44100)].shape, len(mix22))


def stage_btc() -> None:
    import coremltools as ct
    wav = read_wav("harm_22k.wav")
    cabs = cqt_abs(wav)
    feat = np.log(cabs + 1e-6).T                       # (T, 144) = btc_common.cqt_features
    ref = BC.cqt_features(wav)
    log.info("cqt_abs %s · log frente a cqt_features: máx %.2e", cabs.shape, float(np.abs(feat - ref).max()))
    _, mean, std = BC.load_torch_model()
    wins, num_pad = BC.normalize_windows(feat, mean, std)
    ml = ct.models.MLModel(str(BC.OUT / "coreml" / "BTC_large_voca_fp16.mlpackage"),
                           compute_units=ct.ComputeUnit.CPU_AND_NE)
    logits = np.stack([ml.predict({"cqt": wins[i:i + 1]})["logits"][0] for i in range(wins.shape[0])])
    pred = logits.argmax(-1)
    lines = BC.frames_to_lab(pred, num_pad, BC.idx2voca())
    n_valid = int(pred.size - num_pad)
    segs = segments(pred.reshape(-1), n_valid)
    assert len(segs) == len(lines)
    chroma = fold_chroma(cabs)
    save_f32("chord_cqt_abs.f32", cabs)
    save_f32("chord_input.f32", ((feat - mean) / std).astype(np.float32))
    save_f32("chord_logits.f32", logits.astype(np.float32))
    save_i32("chord_argmax.i32", pred.reshape(-1))
    save_f32("chord_chroma.f32", chroma.astype(np.float32))
    (FIX / "chord.lab").write_text("".join(lines))
    save_json(FIX / "chord_ref.json", {"mean": mean, "std": std, "num_pad": int(num_pad), "n_frames": n_valid,
                                       "n_windows": int(wins.shape[0]), "frame_s": BC.FRAME_S,
                                       "segments": [[s, e, i] for s, e, i in segs]})
    log.info("btc: %d tramas, %d ventanas, num_pad %d, %d segmentos", n_valid, wins.shape[0], num_pad, len(segs))


def stage_beat() -> None:
    import coremltools as ct
    import torch
    BT.ensure_repo(log)
    BT.ensure_comm(log)
    mel_bin = WORK / "mel-filterbank.bin"
    BT.download(MEL_URL, mel_bin, log)
    fb = np.fromfile(mel_bin, dtype="<f4")
    assert fb.size == 513 * 128, fb.size
    fb = fb.reshape(513, 128)
    from beat_this.preprocessing import LogMelSpect
    tfb = LogMelSpect(device="cpu").spect_class.mel_scale.fb.numpy()   # (513, 128) de torchaudio
    log.info("banco mel musetric frente a torchaudio: máx %.2e", float(np.abs(fb - tfb).max()))
    save_f32("beat_melbank.f32", fb)
    wav = read_wav("mix_22k.wav")
    spect = BT.log_mel(wav.astype(np.float64))
    save_f32("beat_logmel.f32", spect.numpy())
    mdl = ct.models.CompiledMLModel(str(BT.COMM_MODEL), compute_units=ct.ComputeUnit.CPU_AND_GPU)

    def f(x):
        """Entrada fija de 1500: un trozo más corto (tema < 30 s) se rellena con ceros a la derecha y se recorta."""
        n = x.shape[1]
        xp = np.pad(x, ((0, 0), (0, BT.CHUNK - n), (0, 0))) if n < BT.CHUNK else x
        o = mdl.predict({"spect": xp})
        return np.asarray(o["beat"]).reshape(-1)[:n], np.asarray(o["downbeat"]).reshape(-1)[:n]
    bl, dl, nch = BT.predict_frames(spect, f)
    # Informativo: PyTorch oficial sobre el trozo corto sin rellenar (lo que haría beat_this con < 30 s).
    tm = BT.load_torch_model()

    def ft(x):
        with torch.inference_mode():
            p = tm(torch.from_numpy(x))
        return p["beat"][0].numpy(), p["downbeat"][0].numpy()
    tbl, tdl, _ = BT.predict_frames(spect, ft)
    tb, td = BT.postprocess(tbl, tdl)
    save_f32("beat_logits_beat.f32", bl)
    save_f32("beat_logits_downbeat.f32", dl)
    beats, downs = BT.postprocess(bl, dl)
    from beat_this.inference import split_piece
    starts = {}
    for n in (int(spect.shape[0]), 1000, 1500, 3050):
        _, st = split_piece(torch.zeros(n, 128), BT.CHUNK, border_size=BT.BORDER, avoid_short_end=True)
        starts[str(n)] = [int(s) for s in st]
    save_json(FIX / "beat_ref.json", {
        "frames": int(spect.shape[0]), "fps": BT.FPS, "chunks_used": nch,
        "beats": [round(float(b), 4) for b in beats], "downbeats": [round(float(d), 4) for d in downs],
        "bpm_mean": BT.tempo_fine(beats), "bar_histogram": BT.bar_histogram(beats, downs),
        "chunk_starts": starts, "chunk": BT.CHUNK, "border": BT.BORDER,
        "torch_unpadded": {"logit_maxdiff": float(np.abs(np.concatenate([bl - tbl, dl - tdl])).max()),
                           "beats_match_pct": BT.match_pct(tb, beats), "downbeats_match_pct": BT.match_pct(td, downs)}})
    log.info("beat: %d tramas, %d trozos, %d pulsos, %d downbeats, trozos %s", spect.shape[0], nch, len(beats),
             len(downs), starts)


def stage_key() -> None:
    import soundfile as sf
    meta = json.loads((FIX / "chord_ref.json").read_text())
    cabs = np.fromfile(FIX / "chord_cqt_abs.f32", dtype="<f4").reshape(BC.N_BINS, -1)
    segs = [tuple(s) for s in meta["segments"]]
    fx = key_estimate(fold_chroma(cabs).sum(1), chord_histogram(segs))
    save_json(FIX / "key_fixture.json", fx)
    log.info("key fixture: %s (alt %s) conf %.4f", fx["key"], fx["alternative"], fx["confidence"])
    songs = {}
    for tema in BC.TEMAS:
        xs = []
        for s in BC.STEMS_NO_VOX_DRUMS:
            x, sr = sf.read(str(STEMS_P4 / tema / f"{s}.wav"), dtype="float32", always_2d=True)
            xs.append(x.T.copy())
        wav = BC.to_mono_22k(xs, sr)
        del xs
        cabs = cqt_abs(wav)
        z = np.load(P4_PRED / f"{tema}_stems.npz")
        pred, num_pad = z["pred"], int(z["num_pad"])
        n_valid = int(pred.size - num_pad)
        assert n_valid == cabs.shape[1], (n_valid, cabs.shape)
        segs = segments(pred.reshape(-1), n_valid)
        r = key_estimate(fold_chroma(cabs).sum(1), chord_histogram(segs))
        r.update({"n_frames": n_valid, "n_segments": len(segs), "lab": f"btc/out/lab/coreml_ane_fp16/{tema}_stems.lab"})
        songs[tema] = r
        log.info("key %s: %s (alt %s) conf %.4f", tema, r["key"], r["alternative"], r["confidence"])
    save_json(FIX / "key_songs.json", songs)


DESC = [  # (fichero, forma, tipo, descripción)
    ("mix_22k.wav", "264600", "WAV PCM 16 mono 22 050 Hz",
     f"T1 mezcla, {START_S:.0f}–{START_S + DUR_S:.0f} s: media de canales + soxr HQ (como `bt_common.to_mono_22k`)"),
    ("harm_22k.wav", "264600", "WAV PCM 16 mono 22 050 Hz",
     f"T1 bass+guitar+other+piano (BS-RoFormer), {START_S:.0f}–{START_S + DUR_S:.0f} s: suma, media de canales, "
     "`librosa.resample` soxr_hq"),
    ("harm_44k_stereo.wav", "88200 × 2", "WAV PCM 16 estéreo 44 100 Hz",
     f"suma armónica antes de remuestrear, {START_S:.0f}–{START_S + STEREO_S:.0f} s (prueba de remuestreo)"),
    ("beat_melbank.f32", "[513, 128]", "float32", "`mel-filterbank.bin` de musetric/beat-this-onnx, fila = bin STFT"),
    ("beat_logmel.f32", "[601, 128]", "float32", "log-mel oficial (`LogMelSpect`, torchaudio) de mix_22k.wav"),
    ("beat_logits_beat.f32", "[601]", "float32", "logits `beat` del mlmodelc comunitario, troceado oficial"),
    ("beat_logits_downbeat.f32", "[601]", "float32", "logits `downbeat`, ídem"),
    ("beat_ref.json", "—", "JSON", "pulsos/downbeats «minimal» (s), tempo, compases, inicios de trozo"),
    ("chord_cqt_abs.f32", "[144, 130]", "float32", "|CQT| crudo de librosa de harm_22k.wav (bins × tramas)"),
    ("chord_input.f32", "[130, 144]", "float32", "(log(|CQT|+1e-6) − mean)/std, sin relleno"),
    ("chord_logits.f32", "[2, 108, 170]", "float32", "logits Core ML FP16 ANE por ventana (la 2.ª con 86 de relleno)"),
    ("chord_argmax.i32", "[216]", "int32", "argmax por trama, incluye las 86 tramas de relleno"),
    ("chord_chroma.f32", "[12, 130]", "float32", "croma plegado por trama (clase × trama), 0 = C"),
    ("chord.lab", "—", "texto", "`.lab` con la lógica literal de test.py de BTC"),
    ("chord_ref.json", "—", "JSON", "mean, std, num_pad, n_frames, segmentos exactos [inicio, fin, índice]"),
    ("key_fixture.json", "—", "JSON", "tonalidad del tramo: croma, histograma, 24 puntuaciones, key, alternative"),
    ("key_songs.json", "—", "JSON", "ídem para T1–T3 completos (suma armónica, .lab Core ML ANE de P4)"),
]


def stage_readme() -> None:
    b = json.loads((FIX / "beat_ref.json").read_text())
    c = json.loads((FIX / "chord_ref.json").read_text())
    ks = json.loads((FIX / "key_songs.json").read_text())
    v = versions()
    rows = "\n".join(f"| `{n}` | {s} | {t} | {(FIX / n).stat().st_size} | {d} |" for n, s, t, d in DESC)
    total = sum((FIX / n).stat().st_size for n, *_ in DESC)
    keys = ", ".join(f"{t} {r['key']} ({r['confidence']:.4f})" for t, r in ks.items())
    md = f"""# Fixtures de StudyKit (Fase 2)

Referencias en Python para validar los ports a Swift de pulso (Beat This!), acordes (BTC) y tonalidad.
Generadas por `Probes/P4-modelos/fixtures/make_fase2_fixtures.py` (ver su cabecera; etapas audio, btc, beat, key,
readme, cada una bajo `Probes/P4-modelos/common/guard.py`). No se versionan audios completos: solo tramos de T1.

## Formato

- `.f32` / `.i32`: binario crudo little-endian, sin cabecera, orden C (row-major: el último índice es el más rápido).
- `.wav`: PCM 16 bits. **Todas las referencias se calcularon a partir de estas mismas muestras leídas como float
  (muestra / 32768, lo mismo que hace `AVAudioFile`)**, así que la entrada que ve Swift es idéntica a la de Python.
- Tiempos en segundos desde el inicio del tramo.

| Fichero | Forma | Tipo | Bytes | Contenido |
|---|---|---|---|---|
{rows}

Total: {total} B.

## Pulso (Beat This!)

- Preproceso: mono, 22 050 Hz, STFT 1024, hop 441, Hann periódica, centrada con `reflect`; **módulo / sqrt(1024)**
  (`normalized="frame_length"` de torchaudio = `torch.stft(normalized=True)`, es decir / sqrt(n_fft) = /32, **no**
  / sqrt(Σ win²) como dicen P4 y la mini-spec: con Σ win² el log-mel se desvía ~0,49); mel = |X|ᵀ · melbank;
  log1p(1000 · mel). Con `beat_melbank.f32` y esa normalización, la reconstrucción en numpy da máx 3,6e-5 frente a
  `beat_logmel.f32`.
- `beat_melbank.f32` frente al banco de torchaudio (el que usa `LogMelSpect`): máx 1,8e-5; frente a
  `librosa.filters.mel(..., norm=None)` en float64: máx 1,2e-5. Un banco calculado en Swift en doble debería quedar
  < 1e-6 de librosa, no del fichero.
- El tramo tiene {b['frames']} tramas (< 1500): un solo trozo, inicio −6, de 601 + 6 + 6 = 613 tramas, rellenado con
  ceros a la derecha hasta 1500 para el mlmodelc (entrada fija) y recortado a 613; luego se quita el borde de 6.
  Informativo: PyTorch oficial sobre el trozo de 613 sin rellenar da logits distintos (máx
  {b['torch_unpadded']['logit_maxdiff']:.2f}) y coincide el {b['torch_unpadded']['beats_match_pct']:.1f} % de pulsos.
- Postproceso «minimal» de `beat_this` sobre `beat_logits_*`: {len(b['beats'])} pulsos, {len(b['downbeats'])} downbeats,
  tempo (media a ±20 % de la mediana) {b['bpm_mean']:.2f}.
- `chunk_starts`: inicios de `split_piece(spect, 1500, border_size=6, avoid_short_end=True)` para 601, 1000, 1500 y
  3050 tramas: {b['chunk_starts']}. Cada trozo = spect[max(s,0) : min(s+1500, T)] con relleno de ceros
  max(0, −s) a la izquierda y max(0, min(6, s+1500−T)) a la derecha.

## Acordes (BTC)

- CQT: `librosa.cqt(y, sr=22050, n_bins=144, bins_per_octave=24, hop_length=2048)` (fmin C1 por defecto), por trozos de
  10 s (220 500 muestras) concatenados; el tramo de 12 s da 108 + 22 = {c['n_frames']} tramas.
- `chord_input.f32` = (log(|CQT| + 1e-6) − {c['mean']!r}) / {c['std']!r}. Ventanas de 108 sin solape, la última
  rellena con ceros ({c['num_pad']} tramas); entrada Core ML `cqt` [1,108,144], salida `logits` [1,108,170].
- Logits: `BTC_large_voca_fp16.mlpackage` (el del zip de la app), `CPU_AND_NE`. Fotograma = 10/108 s.

## Tonalidad (receta de la mini-spec, §1 KeyDetector)

1. Croma: bin k de |CQT| (144 bins, 24 por octava, fmin C1) → clase (k div 2) mod 12 (0 = C); suma sobre todas las
   tramas (`chord_chroma.f32` es el plegado por trama, antes de sumar).
2. Histograma: por segmento (excluidos 168 = X y 169 = N), duración (fin − inicio, exacta en múltiplos de 10/108 s)
   sumada a cada nota del acorde: raíz = índice div 14, calidad = índice mod 14 con notas min 0,3,7 · maj 0,4,7 ·
   dim 0,3,6 · aug 0,4,8 · min6 0,3,7,9 · maj6 0,4,7,9 · min7 0,3,7,10 · minmaj7 0,3,7,11 · maj7 0,4,7,11 ·
   7 0,4,7,10 · dim7 0,3,6,9 · hdim7 0,3,6,10 · sus2 0,2,7 · sus4 0,5,7.
3. Perfiles Temperley Kostka-Payne (índice 0 = tónica): mayor {TKP_MAJOR}; menor {TKP_MINOR}.
   Perfil de la tonalidad con tónica t: p_t[pc] = p[(pc − t) mod 12]. s = ½·r(croma, p_t) + ½·r(histograma, p_t),
   r = Pearson (0 si una varianza es 0).
4. `scores` en orden: 0–11 = C, C#, D, D#, E, F, F#, G, G#, A, A#, B mayor; 12–23 = las mismas menores. key = argmax,
   alternative = segunda, confidence = s1 − s2. Nombres «C:maj» / «A:min».

Resultados: tramo {json.loads((FIX / 'key_fixture.json').read_text())['key']}; {keys}.

## Versiones

{", ".join(f"{k} {val}" for k, val in v.items())}; BTC commit {BC.BTC_COMMIT[:7]}; beat_this commit
{BT.BT_COMMIT[:7]}; mlmodelc {BT.COMM_REPO}@{BT.COMM_SHA[:7]}; melbank {BT.ONNX_REPO}@{BT.ONNX_SHA[:7]}.

## Regenerar

```
PY=Tools/py/.venv/bin/python
mkdir -p Probes/P4-modelos/fixtures/out
for s in audio btc beat key readme; do
  $PY Probes/P4-modelos/common/guard.py --limit-gb 10 --log Probes/P4-modelos/fixtures/out/guard_$s.log -- \\
    $PY Probes/P4-modelos/fixtures/make_fase2_fixtures.py --stage $s
done
```
Requiere las salidas de P4 (stems de BS-RoFormer, `btc/out/coreml`, `btc/out/pred`, `beat_this/out/hf_supracut`).
"""
    (FIX / "README.md").write_text(md)
    log.info("README.md %d B", (FIX / "README.md").stat().st_size)


STAGES = {"audio": stage_audio, "btc": stage_btc, "beat": stage_beat, "key": stage_key, "readme": stage_readme}
for name in (list(STAGES) if a.stage == "all" else [a.stage]):
    STAGES[name]()
log.info("versiones: %s", versions())
total = sum(p.stat().st_size for p in FIX.iterdir() if p.is_file())
print(f"etapa {a.stage} ok · Fixtures/ = {total} B ({total / 1e6:.2f} MB) · log: {WORK / 'make.log'}")
