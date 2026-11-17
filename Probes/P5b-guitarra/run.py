"""Fase 5b: candidatos de transcripción de guitarra frente a Basic Pitch, fuera de la app, con métricas proxy
(sin verdad de referencia) y fallar rápido.

Modelos:
  basic_pitch  línea base, con el contrato y los parámetros de la app (TabKit/BasicPitch: onset 0,5, frame 0,3,
               nota mínima 127,70 ms = 11 tramas, energy_tol 11, infer_onsets, melodia_trick, sin límites de
               frecuencia; mono = media de canales, 22 050 Hz). Modelo oficial nmp.mlpackage en CPU+GPU.
  guitab_e25   danmor/guitab E25 (6,2 M), decodificación propia del checkpoint; da cuerda y traste.
  guitab_e19   danmor/guitab E19 (24 M), profesor de E25.
  (MuScriptor small: restringido en HF, ver fetch.py; no hay corredor.)

Métricas por modelo×stem: % notas en registro de guitarra estándar (MIDI 40-88, E2-E6, = Tuning.guitarStandard +
24 trastes de TabKit), concordancia de clase de altura con el acorde BTC vigente (ponderada por duración, sin N/X),
por sección rítmica y solista (spans solo de project.json), onsets frente a librosa.onset_detect del stem (±50 ms,
precisión/exhaustividad), notas/s sobre el audio activo, polifonía media y segundos de inferencia por minuto.

Fallar rápido: en el primer stem del primer tema, un candidato peor que Basic Pitch en acordes Y en registro se
descarta sin seguir.

Uso:
  Tools/py/.venv/bin/python Probes/P4-modelos/common/guard.py --log Temp/p5b/guard.log -- \\
    Tools/py/.venv/bin/python Probes/P5b-guitarra/run.py [--song DIR]... [--stems guitar_L,guitar_R,...]
    [--models basic_pitch,guitab_e25,guitab_e19] [--force]
Sin --song: El roce de tu cuerpo. Para añadir un tema: --song "~/Music/ToneForge/<tema>" (repetible).
Salidas en Temp/p5b/<tema>/ (JSON de notas, MIDI, CHECK_*.wav) y Temp/p5b/metrics.{json,tsv}; log en Temp/p5b/run.log.
"""
import argparse
import json
import logging
import sys
import time
import traceback
import warnings
from pathlib import Path

import numpy as np
import soundfile as sf

warnings.filterwarnings("ignore")
REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "Temp" / "p5b"
OUT.mkdir(parents=True, exist_ok=True)
GUITAB_SRC = OUT / "src" / "guitab"
DEFAULT_SONG = Path.home() / "Music" / "ToneForge" / "El roce de tu cuerpo - Platero Y Tu"
DEFAULT_STEMS = ["guitar_L", "guitar_R", "guitar_lead", "guitar"]
MODELS = ["basic_pitch", "guitab_e25", "guitab_e19", "guitab_e25_f03"]
SR = 22050
REG_LO, REG_HI = 40, 88          # E2..E6
ONSET_TOL = 0.05
ACTIVE_DB = -40.0                # audio activo: RMS > máx − 40 dB

log = logging.getLogger("p5b")
log.setLevel(logging.INFO)
log.propagate = False
_fh = logging.FileHandler(OUT / "run.log", mode="a")
_fh.setFormatter(logging.Formatter("%(asctime)s %(message)s"))
log.addHandler(_fh)


def _excepthook(t, v, tb):
    log.error("".join(traceback.format_exception(t, v, tb)))
    print(f"ERROR: {t.__name__}: {v} (ver {OUT / 'run.log'})")


sys.excepthook = _excepthook

import librosa  # noqa: E402
import mir_eval  # noqa: E402
import pretty_midi  # noqa: E402
import soxr  # noqa: E402

# ---------------------------------------------------------------- tema: audio, acordes BTC, secciones

ROOTS = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
QUAL = {"min": [0, 3, 7], "maj": [0, 4, 7], "dim": [0, 3, 6], "aug": [0, 4, 8], "min6": [0, 3, 7, 9],
        "maj6": [0, 4, 7, 9], "min7": [0, 3, 7, 10], "minmaj7": [0, 3, 7, 11], "maj7": [0, 4, 7, 11],
        "7": [0, 4, 7, 10], "dim7": [0, 3, 6, 9], "hdim7": [0, 3, 6, 10], "sus2": [0, 2, 7], "sus4": [0, 5, 7]}
QORDER = list(QUAL)  # mismo orden que btc_common.QUALITIES: índice = raíz*14 + calidad; 168 X, 169 N


def chord_pcs(idx: int):
    if idx >= 168:
        return None
    r, q = divmod(idx, 14)
    return {(r + i) % 12 for i in QUAL[QORDER[q]]}


def song_tag(song: Path) -> str:
    title = song.name.split(" - ")[0]
    return "_".join(title.split()[:2])


def load_song(song: Path):
    an = json.loads((song / "cache" / "analysis.json").read_text())["analysis"]
    pj = json.loads((song / "project.json").read_text())
    segs = [(s["start"], s["end"], chord_pcs(s["index"])) for s in an["chords"]["segments"]]
    solos = [(s["start"], s["end"]) for s in pj.get("sections", []) if s.get("solo")]
    solos += [(s["start"], s["end"]) for s in pj.get("guitarApplied", {}).get("options", {}).get("soloSpans", [])]
    return segs, sorted(set(solos)), an["beats"]


def load_stem(path: Path) -> np.ndarray:
    x, sr = sf.read(str(path), dtype="float32", always_2d=True)
    y = x.mean(axis=1)
    return soxr.resample(y, sr, SR, quality="HQ").astype(np.float32) if sr != SR else y


# ---------------------------------------------------------------- modelos

def run_basic_pitch(y: np.ndarray):
    import coremltools as ct
    import basic_pitch
    from basic_pitch import constants as C
    from basic_pitch import note_creation as nc
    from basic_pitch.inference import unwrap_output, window_audio_file

    m = ct.models.MLModel(str(Path(basic_pitch.__file__).parent / "saved_models/icassp_2022/nmp.mlpackage"),
                          compute_units=ct.ComputeUnit.CPU_AND_GPU)
    n_olap = 30
    olap = n_olap * C.FFT_HOP
    hop = C.AUDIO_N_SAMPLES - olap
    t0 = time.perf_counter()
    padded = np.concatenate([np.zeros(olap // 2, np.float32), y])
    outs = {"note": [], "onset": [], "contour": []}
    for w, _ in window_audio_file(padded, hop):
        r = m.predict({"input_2": w[None].astype(np.float32)})
        outs["note"].append(r["Identity_1"])
        outs["onset"].append(r["Identity_2"])
        outs["contour"].append(r["Identity"])
    out = {k: unwrap_output(np.concatenate(v), len(y), n_olap) for k, v in outs.items()}
    _, ev = nc.model_output_to_notes(out, onset_thresh=0.5, frame_thresh=0.3, infer_onsets=True,
                                     min_note_len=int(np.round(127.70 / 1000 * (SR / C.FFT_HOP))),
                                     min_freq=None, max_freq=None, melodia_trick=True)
    dt = time.perf_counter() - t0
    notes = [{"onset": float(s), "offset": float(e), "pitch": int(p), "amp": float(a)} for s, e, p, a, _ in ev]
    return sorted(notes, key=lambda n: (n["onset"], n["pitch"])), dt, {"units": "CoreML CPU_AND_GPU"}


def run_guitab(y: np.ndarray, which: str, device: str, override: dict | None = None):
    import torch
    sys.path.insert(0, str(GUITAB_SRC))
    from guitab.audio import compute_cqt
    from guitab.inference import DEFAULT_PARAMS, extract_notes, load_model, predict

    model = load_model(GUITAB_SRC / "weights" / f"guitab_{which}.safetensors", device)
    dec = {**model.decoding, **(override or {})}
    params = {**DEFAULT_PARAMS, **dec}
    torch.set_grad_enabled(False)
    t0 = time.perf_counter()
    feat = compute_cqt(y)
    t1 = time.perf_counter()
    tab, onset = predict(model, feat, device)
    notes = extract_notes(tab, onset, dec)
    dt = time.perf_counter() - t0
    out = [{"onset": float(n["onset"]), "offset": float(n["offset"]), "pitch": int(n["pitch"]),
            "amp": float(n["score"]), "string": int(n["string"]), "fret": int(n["fret"])} for n in notes]
    nparams = sum(p.numel() for p in model.parameters())
    return out, dt, {"units": f"torch {device}", "cqt_s": round(t1 - t0, 2), "params": nparams, "decoding": params}


# ---------------------------------------------------------------- métricas

def in_spans(t: float, spans) -> bool:
    return any(a <= t < b for a, b in spans)


def chord_agreement(notes, segs, solos):
    """Fracción (ponderada por solape en segundos) de duración de nota cuya clase de altura está en el acorde BTC."""
    starts = np.array([s[0] for s in segs])
    acc = {"all": [0.0, 0.0], "rhythm": [0.0, 0.0], "solo": [0.0, 0.0], "count": [0.0, 0.0]}
    for n in notes:
        j = max(int(np.searchsorted(starts, n["onset"], side="right")) - 1, 0)
        if segs[j][2] is not None:  # sin ponderar: acorde vigente en el ataque
            acc["count"][0] += float(n["pitch"] % 12 in segs[j][2])
            acc["count"][1] += 1
        pc = n["pitch"] % 12
        part = "solo" if in_spans(n["onset"], solos) else "rhythm"
        i = max(int(np.searchsorted(starts, n["onset"], side="right")) - 1, 0)
        while i < len(segs) and segs[i][0] < n["offset"]:
            a, b, pcs = segs[i]
            ov = min(b, n["offset"]) - max(a, n["onset"])
            if ov > 0 and pcs is not None:
                hit = ov if pc in pcs else 0.0
                for k in ("all", part):
                    acc[k][0] += hit
                    acc[k][1] += ov
            i += 1
    return {k: (h / d if d > 0 else float("nan")) for k, (h, d) in acc.items()}


def stem_activity(y: np.ndarray):
    rms = librosa.feature.rms(y=y, frame_length=1024, hop_length=256)[0]
    db = 20 * np.log10(rms + 1e-9) - 20 * np.log10(rms.max() + 1e-9)
    return db


def ref_onsets(y: np.ndarray, db: np.ndarray) -> np.ndarray:
    on = librosa.onset.onset_detect(y=y, sr=SR, hop_length=256, units="frames", backtrack=False)
    # solo onsets con el stem activo (máximo de RMS en los 50 ms siguientes > máx − 40 dB): fuera, ruido de separación
    keep = [f for f in on if db[f:f + 5].max(initial=-200) > ACTIVE_DB]
    return librosa.frames_to_time(np.array(keep, dtype=int), sr=SR, hop_length=256)


def est_onsets(notes) -> np.ndarray:
    ts = sorted(n["onset"] for n in notes)
    out = []
    for t in ts:  # notas de un mismo acorde (≤ 30 ms) = un ataque
        if not out or t - out[-1] > 0.03:
            out.append(t)
    return np.array(out)


def metrics(notes, y, segs, solos, db, ref_on, infer_s):
    dur = len(y) / SR
    active_s = float((db > ACTIVE_DB).mean() * dur)
    pitches = np.array([n["pitch"] for n in notes]) if notes else np.zeros(0)
    reg = float(((pitches >= REG_LO) & (pitches <= REG_HI)).mean()) if len(pitches) else float("nan")
    ch = chord_agreement(notes, segs, solos)
    est = est_onsets(notes)
    if len(est) and len(ref_on):
        f, p, r = mir_eval.onset.f_measure(ref_on, est, window=ONSET_TOL)
    else:
        f = p = r = 0.0
    grid = np.zeros(int(dur * 100) + 1, np.int32)
    for n in notes:
        grid[int(n["onset"] * 100):max(int(n["offset"] * 100), int(n["onset"] * 100) + 1)] += 1
    sounding = grid[grid > 0]
    return {"n_notes": len(notes), "register": reg, "chord_all": ch["all"], "chord_rhythm": ch["rhythm"],
            "chord_solo": ch["solo"], "chord_count": ch["count"], "short_frac": float(np.mean(
                [n["offset"] - n["onset"] < 0.013 for n in notes])) if notes else 0.0, "onset_P": float(p), "onset_R": float(r), "onset_F": float(f),
            "n_ref_onsets": int(len(ref_on)), "notes_per_s_active": len(notes) / active_s if active_s else float("nan"),
            "polyphony": float(sounding.mean()) if len(sounding) else 0.0, "pitch_min": int(pitches.min()) if len(pitches) else 0,
            "pitch_max": int(pitches.max()) if len(pitches) else 0, "s_per_min": infer_s / (dur / 60), "dur_s": dur,
            "active_s": active_s}


# ---------------------------------------------------------------- escucha

def write_midi(notes, path: Path):
    pm = pretty_midi.PrettyMIDI()
    inst = pretty_midi.Instrument(program=29, name=path.stem)  # overdriven guitar
    for n in notes:
        vel = int(np.clip(40 + 87 * n["amp"], 1, 127))
        inst.notes.append(pretty_midi.Note(velocity=vel, pitch=n["pitch"], start=n["onset"], end=max(n["offset"], n["onset"] + 0.02)))
    pm.instruments.append(inst)
    pm.write(str(path))


def synth(notes, n_samples: int) -> np.ndarray:
    """Pulsación aditiva sencilla (6 armónicos con caída), solo para oír alturas y ataques."""
    out = np.zeros(n_samples + SR, np.float32)
    rel = int(0.06 * SR)
    for n in notes:
        s = int(n["onset"] * SR)
        length = max(int((n["offset"] - n["onset"]) * SR), int(0.03 * SR))
        t = np.arange(length + rel) / SR
        f0 = 440.0 * 2 ** ((n["pitch"] - 69) / 12)
        w = np.zeros_like(t)
        for k in range(1, 7):
            if k * f0 < SR / 2:
                w += np.sin(2 * np.pi * k * f0 * t) * np.exp(-t * (1.0 + 1.5 * k)) / k
        env = np.ones_like(t)
        env[:int(0.004 * SR)] = np.linspace(0, 1, int(0.004 * SR))
        env[length:] = np.linspace(1, 0, rel)
        seg = (w * env * (0.3 + 0.7 * min(max(n["amp"], 0.0), 1.0))).astype(np.float32)
        e = min(s + len(seg), len(out))
        out[s:e] += seg[:e - s]
    out = out[:n_samples]
    peak = np.abs(out).max()
    return out / peak * 0.8 if peak > 0 else out


def write_check(notes, y, tag, stem, model, d: Path):
    x = synth(notes, len(y))
    sf.write(str(d / f"CHECK_{tag}_{stem}_{model}.wav"), x, SR, subtype="PCM_16")
    yp = y / (np.abs(y).max() + 1e-9) * 0.8
    sf.write(str(d / f"CHECK_{tag}_{stem}_{model}_estereo.wav"), np.stack([yp, x], 1), SR, subtype="PCM_16")


# ---------------------------------------------------------------- principal

def transcribe(model, y, device):
    if model == "basic_pitch":
        return run_basic_pitch(y)
    parts = model.split("_")  # guitab_e25 | guitab_e25_f03 (umbral de actividad de cuerda 0,3 en vez de 0,6)
    override = {"frame": int(parts[2][1:]) / 10} if len(parts) > 2 and parts[2].startswith("f") else None
    return run_guitab(y, parts[1], device, override)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--song", action="append", type=Path)
    ap.add_argument("--stems", default=",".join(DEFAULT_STEMS))
    ap.add_argument("--models", default=",".join(MODELS))
    ap.add_argument("--device", default="cpu")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    songs = [s.expanduser() for s in (a.song or [DEFAULT_SONG])]
    stems = a.stems.split(",")
    alive = a.models.split(",")
    assert alive[0] == "basic_pitch", "basic_pitch va primero: es la referencia de la puerta"
    mfile = OUT / "metrics.json"
    allm = json.loads(mfile.read_text()) if mfile.exists() else {}
    discarded = {}
    log.info("=== run songs=%s stems=%s models=%s", [s.name for s in songs], stems, alive)
    for si, song in enumerate(songs):
        tag = song_tag(song)
        d = OUT / tag
        d.mkdir(exist_ok=True)
        segs, solos, _ = load_song(song)
        log.info("%s: %d segmentos de acorde, solos=%s", tag, len(segs), solos)
        for sti, stem in enumerate(stems):
            y = load_stem(song / "stems" / f"{stem}.wav")
            db = stem_activity(y)
            ref_on = ref_onsets(y, db)
            for model in list(alive):
                key = f"{tag}/{stem}/{model}"
                nj = d / f"{stem}_{model}.json"
                if nj.exists() and not a.force:
                    cached = json.loads(nj.read_text())
                    notes, dt, info = cached["notes"], cached["infer_s"], cached["info"]
                else:
                    notes, dt, info = transcribe(model, y, a.device)
                    nj.write_text(json.dumps({"notes": notes, "infer_s": dt, "info": info}))
                m = metrics(notes, y, segs, solos, db, ref_on, dt)
                m["info"] = {k: v for k, v in info.items() if k != "decoding"}
                allm[key] = m
                log.info("%s %s", key, json.dumps({k: (round(v, 4) if isinstance(v, float) else v) for k, v in m.items()}))
                if info.get("decoding"):
                    log.info("%s decoding=%s", key, info["decoding"])
                write_midi(notes, d / f"{tag}_{stem}_{model}.mid")
                write_check(notes, y, tag, stem, model, d)
            if si == 0 and sti == 0:  # puerta de fallar rápido
                base = allm[f"{tag}/{stem}/basic_pitch"]
                for model in alive[1:]:
                    c = allm[f"{tag}/{stem}/{model}"]
                    if c["chord_all"] < base["chord_all"] and c["register"] < base["register"]:
                        discarded[model] = (f"peor que Basic Pitch en {tag}/{stem}: acordes {c['chord_all']:.3f} < "
                                            f"{base['chord_all']:.3f} y registro {c['register']:.3f} < {base['register']:.3f}")
                        alive.remove(model)
                        log.info("DESCARTADO %s: %s", model, discarded[model])
                if len(alive) == 1:
                    log.info("ningún candidato pasa la puerta: fin")
                    break
            mfile.write_text(json.dumps(allm, indent=1))
        mfile.write_text(json.dumps(allm, indent=1))
    cols = ["n_notes", "register", "chord_all", "chord_rhythm", "chord_solo", "chord_count", "short_frac", "onset_P", "onset_R", "notes_per_s_active",
            "polyphony", "s_per_min"]
    lines = ["key\t" + "\t".join(cols)]
    for k, m in allm.items():
        lines.append(k + "\t" + "\t".join(f"{m[c]:.3f}" if isinstance(m[c], float) else str(m[c]) for c in cols))
    (OUT / "metrics.tsv").write_text("\n".join(lines) + "\n")
    print(f"{len(allm)} filas en {OUT / 'metrics.tsv'}; descartados: {discarded or 'ninguno'}")


if __name__ == "__main__":
    main()
