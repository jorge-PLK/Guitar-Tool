# /// script
# requires-python = ">=3.12"
# dependencies = ["numpy", "scipy", "soundfile", "pyloudnorm"]
# ///
"""Prepara los audios de prueba de P4 (separacion de stems) y P6 (estiramiento).

Uso:  uv run --python 3.12 Probes/testaudio/prepare.py [--songs T1 T2]

Entrada:  out/raw/T<n>/*.wav  (Cambridge MT, multipistas en bruto)
          out/raw/T<n>/reamp/*.wav  (opcional: guitarras reamplificadas que sustituyen a los DI)
Salida:   out/T<n>/{mix.wav, stems/, guitar_parts/, di/}, out/clips/, out/manifest.json
Politica de mezcla: ver README.md. mix == suma exacta de stems (sin limitador).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
import pyloudnorm as pyln
import soundfile as sf
from scipy.signal import find_peaks

HERE = Path(__file__).resolve().parent
SR = 44100
GROUPS = ["drums", "bass", "guitar", "vocals", "piano", "other"]  # mismas 6 clases que BS-RoFormer SW / HTDemucs 6s

# --- Balance por grupo: sonoridad integrada (LUFS) de cada stem ANTES de la normalizacion final de pico.
# Voz y bateria delante, guitarras 3 LU detras, bajo presente.
GROUP_TARGET_LUFS = {"vocals": -20.0, "drums": -20.0, "guitar": -23.0, "bass": -22.0, "piano": -26.0, "other": -28.0}
TRACK_REF_LUFS = -23.0  # referencia a la que se igualan las pistas de un grupo antes de aplicar su offset
PEAK_TARGET_DBFS = -1.0
SILENCE_PEAK = 1e-4  # pico < -80 dBFS: pista vacia

# --- Panorama (-1 = izquierda, +1 = derecha). Solo afecta a pistas mono; las estereo van tal cual.
PAN_HIHAT = 0.3
PAN_TOM_SPREAD = 0.4       # toms mono: repartidos linealmente en [-0.4, +0.4]
PAN_GTR_SINGLE = 0.3       # guitarras sueltas: +-30 %, alternando lado empezando por la izquierda
PAN_BACKING = 0.5          # coros: +-50 %; parejas X/XDT a L/R, sueltos alternan empezando por la derecha
PAN_OTHER = 0.4            # sintetizadores y otros: +-40 %, alternando desde la izquierda
# Ley de panorama de potencia constante: centro = -3 dB por canal; extremo = 0 dB en ese canal.

# Offsets de sonoridad por pista dentro de su grupo (LU respecto a TRACK_REF_LUFS).
DRUM_OFFSETS = [  # (regex sobre nombre en minusculas, offset)
    (r"snaredown", -10.0), (r"sample", -6.0), (r"kickout", -4.0), (r"kick", 0.0), (r"snare", 0.0),
    (r"hihat", -8.0), (r"tom", -6.0), (r"overhead", -2.0), (r"room", -6.0),
]
VOX_BACKING_OFFSET = -6.0
VOX_DOUBLE_OFFSET = -4.0

# --- Tramos P6
CLIP_SECONDS = 30.0
ENV_HOP = 0.5            # resolucion de la envolvente (s)
LEAD_ONSET_PENALTY_DB = 3.0   # dB de puntuacion por onset/s en gtr_lead
ACTIVE_FRACTION = 0.9
ACTIVE_BELOW_P90_DB = 20.0


def sha256(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for b in iter(lambda: f.read(1 << 22), b""):
            h.update(b)
    return h.hexdigest()


def classify(name: str) -> str:
    n = name.lower()
    if re.search(r"kick|snare|hihat|hi-hat|tom|overhead|drum|cymbal|room", n):
        return "drums"
    if "bass" in n:
        return "bass"
    if re.search(r"gtr|guitar", n):
        return "guitar"
    if re.search(r"vox|vocal|voice|choir", n):
        return "vocals"
    if re.search(r"piano|keys|rhodes|organ", n):
        return "piano"
    return "other"


GTR_RE = re.compile(r"^(?P<base>[A-Za-z]*?Gtr)(?P<n>\d+)(?P<var>Amp\d+|DT)?(?P<di>DI)?$", re.I)


@dataclass
class Track:
    path: Path
    name: str            # sin prefijo numerico ni extension
    stem: str            # nombre de fichero sin extension (para salidas)
    group: str
    role: str = "mix"    # mix | di | di_fallback
    reamp: bool = False
    gkey: str | None = None   # clave de guitarra (ElecGtr3)
    is_dt: bool = False
    is_di: bool = False
    pan: float | None = None
    offset_lu: float = 0.0
    channels: int = 0
    frames: int = 0
    sha: str = ""
    silent: bool = False
    trim_db: float = 0.0


def collect(song_dir: Path) -> list[Track]:
    tracks = []
    files = [(p, False) for p in sorted(song_dir.glob("*.wav"))]
    reamp = song_dir / "reamp"
    if reamp.is_dir():
        files += [(p, True) for p in sorted(reamp.glob("*.wav"))]
    for p, is_reamp in files:
        stem = p.stem
        name = re.sub(r"^\d+_", "", stem)
        t = Track(p, name, ("reamp_" + stem) if is_reamp else stem, classify(name), reamp=is_reamp)
        if is_reamp:
            t.group = "guitar"
        if t.group == "guitar":
            m = GTR_RE.match(name)
            if m:
                t.gkey = m["base"] + m["n"]
                var = (m["var"] or "").lower()
                t.is_dt = var == "dt"
                t.is_di = bool(m["di"])
            else:
                t.gkey = name
        info = sf.info(p)
        t.channels, t.frames = info.channels, info.frames
        if info.samplerate != SR:
            raise SystemExit(f"{p}: {info.samplerate} Hz, se esperaba {SR}")
        t.sha = sha256(p)
        tracks.append(t)
    return tracks


def assign_guitar_roles(tracks: list[Track]) -> None:
    """Los DI no entran en la mezcla si existe pista de ampli (o reamp) de esa guitarra."""
    amp_keys = {t.gkey for t in tracks if t.group == "guitar" and not t.is_di}
    for t in tracks:
        if t.group == "guitar" and t.is_di:
            t.role = "di" if t.gkey in amp_keys else "di_fallback"


def assign_pans(tracks: list[Track]) -> None:
    mixers = [t for t in tracks if t.role in ("mix", "di_fallback")]
    # Guitarras
    keys = sorted({t.gkey for t in mixers if t.group == "guitar"})
    single_idx = 0
    for k in keys:
        members = [t for t in mixers if t.group == "guitar" and t.gkey == k]
        has_dt = any(t.is_dt for t in members)
        if has_dt:
            for t in members:
                t.pan = 1.0 if t.is_dt else -1.0
        else:
            side = -1.0 if single_idx % 2 == 0 else 1.0
            single_idx += 1
            for t in members:
                t.pan = side * PAN_GTR_SINGLE
    # Bateria
    mono_toms = [t for t in mixers if t.group == "drums" and "tom" in t.name.lower() and t.channels == 1 and "sample" not in t.name.lower()]
    for i, t in enumerate(mono_toms):
        t.pan = 0.0 if len(mono_toms) == 1 else -PAN_TOM_SPREAD + 2 * PAN_TOM_SPREAD * i / (len(mono_toms) - 1)
    for t in mixers:
        if t.group == "drums" and t.pan is None:
            t.pan = PAN_HIHAT if "hihat" in t.name.lower() else 0.0
    # Voces: parejas BackingVoxN / BackingVoxNDT a -50 % / +50 %; coros sueltos alternan (empezando por la derecha)
    side = 1.0
    vox = [t for t in mixers if t.group == "vocals"]
    vkeys = {re.sub(r"dt$", "", t.name.lower()) for t in vox if t.name.lower().endswith("dt")}
    for t in vox:
        n = t.name.lower()
        if "lead" in n:
            t.pan = 0.0
        elif n in vkeys:
            t.pan = -PAN_BACKING
        elif n.endswith("dt") and n[:-2] in vkeys:
            t.pan = PAN_BACKING
        else:
            t.pan = side * PAN_BACKING
            side = -side
    # Sintetizadores (grupo other): +-40 %, alternando desde la izquierda
    side = -1.0
    for t in mixers:
        if t.group == "other":
            t.pan = side * PAN_OTHER
            side = -side
    for t in mixers:
        if t.pan is None:
            t.pan = 0.0
    # Offsets
    for t in mixers:
        n = t.name.lower()
        if t.group == "drums":
            t.offset_lu = next((o for rx, o in DRUM_OFFSETS if re.search(rx, n)), 0.0)
        elif t.group == "vocals":
            if "lead" not in n:
                t.offset_lu = VOX_BACKING_OFFSET
            elif "dt" in n:
                t.offset_lu = VOX_DOUBLE_OFFSET


def to_stereo(x: np.ndarray, pan: float) -> np.ndarray:
    if x.ndim == 2 and x.shape[1] == 2:
        return x.astype(np.float32, copy=False)
    mono = x if x.ndim == 1 else x[:, 0]
    th = (pan + 1.0) * math.pi / 4.0
    return np.stack([mono * math.cos(th), mono * math.sin(th)], axis=1).astype(np.float32)


def lufs(x: np.ndarray) -> float:
    if x.shape[0] < int(0.5 * SR):
        return -math.inf
    return float(pyln.Meter(SR).integrated_loudness(x.astype(np.float64)))


def write(path: Path, data: np.ndarray, subtype: str = "FLOAT") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(path, data, SR, subtype=subtype)


def process_song(sid: str, raw_root: Path, out_root: Path) -> dict:
    tracks = collect(raw_root / sid)
    assign_guitar_roles(tracks)
    assign_pans(tracks)
    n = max(t.frames for t in tracks)
    out = out_root / sid
    gsum = {g: np.zeros((n, 2), np.float32) for g in GROUPS}
    parts: dict[str, np.ndarray] = {}  # guitar_parts sin escalar por grupo/master
    part_group: dict[str, str] = {}

    # DI tal cual
    for t in tracks:
        if t.role == "di":
            x, _ = sf.read(t.path, dtype="float32", always_2d=False)
            write(out / "di" / f"{t.stem}.wav", x, "PCM_24")

    for t in tracks:
        if t.role == "di":
            continue
        x, _ = sf.read(t.path, dtype="float32", always_2d=False)
        if float(np.abs(x).max()) < SILENCE_PEAK:
            t.silent = True
            continue
        st = to_stereo(x, t.pan)
        l = lufs(st)
        if not math.isfinite(l):
            t.silent = True
            continue
        gain = TRACK_REF_LUFS + t.offset_lu - l
        t.trim_db = gain
        st = (st * np.float32(10 ** (gain / 20))).astype(np.float32)
        gsum[t.group][: st.shape[0]] += st
        if t.group == "guitar":
            padded = np.zeros((n, 2), np.float32)
            padded[: st.shape[0]] = st
            parts[t.stem] = padded
        del x, st

    # Ganancia por grupo hacia su objetivo
    group_gain_db, empty = {}, []
    for g in GROUPS:
        if float(np.abs(gsum[g]).max()) < SILENCE_PEAK:
            empty.append(g)
            continue
        group_gain_db[g] = GROUP_TARGET_LUFS[g] - lufs(gsum[g])
    pre = np.zeros((n, 2), np.float32)
    for g, gd in group_gain_db.items():
        pre += gsum[g] * np.float32(10 ** (gd / 20))
    peak = float(np.abs(pre).max())
    master_db = PEAK_TARGET_DBFS - 20 * math.log10(peak)
    del pre

    # Escritura: stems y partes con ganancia de grupo + master
    stem_info = {}
    for g, gd in group_gain_db.items():
        lin = np.float32(10 ** ((gd + master_db) / 20))
        s = (gsum[g] * lin).astype(np.float32)
        write(out / "stems" / f"{g}.wav", s)
        stem_info[g] = {"file": f"stems/{g}.wav", "target_lufs_pre_master": GROUP_TARGET_LUFS[g],
                        "group_gain_db": round(gd, 3), "lufs_final": round(lufs(s), 2)}
    for stem, p in parts.items():
        gd = group_gain_db["guitar"]
        write(out / "guitar_parts" / f"{stem}.wav", (p * np.float32(10 ** ((gd + master_db) / 20))).astype(np.float32))
    del gsum, parts

    # mix = suma exacta de los stems tal como quedaron en disco; verificacion por lectura
    acc = np.zeros((n, 2), np.float64)
    for g in stem_info:
        acc += sf.read(out / "stems" / f"{g}.wav", dtype="float32")[0].astype(np.float64)
    mix = acc.astype(np.float32)
    write(out / "mix.wav", mix)
    mix_r = sf.read(out / "mix.wav", dtype="float32")[0]
    acc2 = np.zeros((n, 2), np.float64)
    for g in stem_info:
        acc2 += sf.read(out / "stems" / f"{g}.wav", dtype="float32")[0].astype(np.float64)
    err = float(np.abs(mix_r.astype(np.float64) - acc2).max())
    # guitarra: stem vs suma de partes
    gpar_err = None
    gp = sorted((out / "guitar_parts").glob("*.wav")) if (out / "guitar_parts").is_dir() else []
    if gp and "guitar" in stem_info:
        a = np.zeros((n, 2), np.float64)
        for p in gp:
            a += sf.read(p, dtype="float32")[0].astype(np.float64)
        gpar_err = float(np.abs(a - sf.read(out / "stems" / "guitar.wav", dtype="float32")[0]).max())
    mix_lufs = lufs(mix_r)
    mix_peak_db = 20 * math.log10(float(np.abs(mix_r).max()))
    assert err < 1e-5, f"{sid}: error de suma {err}"

    tr_json = []
    for t in tracks:
        tr_json.append({
            "file": str(t.path.relative_to(raw_root)), "sha256": t.sha,
            "group": t.group, "role": t.role, "channels": t.channels, "silent": t.silent,
            "pan": None if t.role == "di" or t.channels == 2 else round(t.pan, 3),
            "pan_applied": None if t.role == "di" else ("stereo tal cual" if t.channels == 2 else "mono, potencia constante"),
            "offset_lu": t.offset_lu, "trim_db": round(t.trim_db, 3),
            "group_gain_db": None if t.role == "di" or t.group not in group_gain_db else round(group_gain_db[t.group], 3),
            "total_gain_db": None if t.role == "di" or t.group not in group_gain_db or t.silent else round(t.trim_db + group_gain_db[t.group] + master_db, 3),
            "output": (f"di/{t.stem}.wav" if t.role == "di" else (f"guitar_parts/{t.stem}.wav" if t.group == "guitar" and not t.silent else None)),
        })
    outputs = {str(p.relative_to(out)): sha256(p) for p in sorted(out.rglob("*.wav"))}
    return {
        "duration_s": round(n / SR, 3), "tracks": tr_json,
        "groups": stem_info, "empty_groups": empty,
        "master_gain_db": round(master_db, 3), "mix_peak_dbfs": round(mix_peak_db, 3),
        "mix_lufs": round(mix_lufs, 2), "sum_error_max_abs": err, "guitar_parts_sum_error_max_abs": gpar_err,
        "output_sha256": outputs,
        "_guitar_keys": {k: [f"guitar_parts/{t.stem}.wav" for t in tracks if t.group == "guitar" and t.gkey == k and t.role != "di" and not t.silent]
                         for k in sorted({t.gkey for t in tracks if t.group == "guitar" and t.role != "di"})},
        "_dt_keys": sorted({t.gkey for t in tracks if t.group == "guitar" and t.is_dt}),
    }


# ---------------------------------------------------------------- tramos P6

def mono_of(x: np.ndarray) -> np.ndarray:
    return x.mean(axis=1) if x.ndim == 2 else x


def envelope(x_mono: np.ndarray) -> np.ndarray:
    h = int(ENV_HOP * SR)
    k = len(x_mono) // h
    return np.sqrt((x_mono[: k * h].reshape(k, h).astype(np.float64) ** 2).mean(axis=1))


def onset_times(x_mono: np.ndarray) -> np.ndarray:
    """Onsets por flujo espectral logaritmico; devuelve instantes en s."""
    win, hop = 2048, 512
    w = np.hanning(win).astype(np.float32)
    nfr = 1 + (len(x_mono) - win) // hop
    flux = np.zeros(nfr, np.float32)
    prev = None
    energy = np.zeros(nfr, np.float32)
    for s in range(0, nfr, 2000):
        e = min(nfr, s + 2000)
        idx = np.arange(s, e)[:, None] * hop + np.arange(win)[None, :]
        fr = x_mono[idx] * w
        energy[s:e] = (fr ** 2).mean(axis=1)
        mag = np.log1p(100.0 * np.abs(np.fft.rfft(fr, axis=1)) / win)
        d = np.diff(mag, axis=0, prepend=(prev if prev is not None else mag[:1]))
        flux[s:e] = np.maximum(d, 0).sum(axis=1)
        prev = mag[-1:]
    flux = np.convolve(flux, np.ones(3) / 3, mode="same")
    thr = flux.mean() + flux.std()
    ok = energy > energy.max() * 1e-6
    pk, _ = find_peaks(np.where(ok, flux, 0), height=thr, distance=int(0.08 * SR / hop))
    return pk * hop / SR


def window_scan(level_db: np.ndarray, onsets: np.ndarray):
    """Por cada inicio (multiplo de ENV_HOP): nivel medio, fraccion activa, onsets/s."""
    w = int(CLIP_SECONDS / ENV_HOP)
    k = len(level_db)
    starts = np.arange(0, k - w + 1)
    p90 = np.percentile(level_db, 90)
    active = (level_db > p90 - ACTIVE_BELOW_P90_DB).astype(float)
    cs = np.concatenate([[0], np.cumsum(level_db)])
    ca = np.concatenate([[0], np.cumsum(active)])
    mean_db = (cs[starts + w] - cs[starts]) / w
    act = (ca[starts + w] - ca[starts]) / w
    counts, _ = np.histogram(onsets, bins=np.arange(0, k + 1) * ENV_HOP)
    cc = np.concatenate([[0], np.cumsum(counts)])
    rate = (cc[starts + w] - cc[starts]) / CLIP_SECONDS
    return starts, mean_db, act, rate


def cut(x: np.ndarray, start_s: float) -> np.ndarray:
    a = int(round(start_s * SR))
    return x[a: a + int(CLIP_SECONDS * SR)]


def make_clips(results: dict, out_root: Path) -> dict:
    clips = {}
    cdir = out_root / "clips"
    # lead: guitarra no doblada de T1/T2
    best = None
    for sid in ("T1", "T2", "T3"):
        if sid not in results:
            continue
        r = results[sid]
        for k, files in r["_guitar_keys"].items():
            if k in r["_dt_keys"] or not files:
                continue
            x = sum(sf.read(out_root / sid / f, dtype="float32")[0].astype(np.float32) for f in files)
            m = mono_of(x)
            lvl = 20 * np.log10(envelope(m) + 1e-9)
            starts, mdb, act, rate = window_scan(lvl, onset_times(m))
            score = np.where(act >= ACTIVE_FRACTION, mdb - LEAD_ONSET_PENALTY_DB * rate, -np.inf)
            i = int(np.argmax(score))
            if np.isfinite(score[i]) and (best is None or score[i] > best[0]):
                best = (float(score[i]), sid, k, starts[i] * ENV_HOP, x, float(rate[i]), float(mdb[i]))
    if best:
        _, sid, k, st, x, rate, mdb = best
        write(cdir / "gtr_lead.wav", cut(x, st))
        clips["gtr_lead"] = {"song": sid, "guitar": k, "start_s": st, "onsets_per_s": round(rate, 2), "mean_level_dbfs_rms": round(mdb, 1)}
    if "T1" in results:
        o = out_root / "T1"
        drums = sf.read(o / "stems" / "drums.wav", dtype="float32")[0]
        gtr = sf.read(o / "stems" / "guitar.wav", dtype="float32")[0]
        pd, pg = envelope(mono_of(drums)) ** 2, envelope(mono_of(gtr)) ** 2
        w = int(CLIP_SECONDS / ENV_HOP)
        k = min(len(pd), len(pg))
        ker = np.ones(w) / w
        score = np.convolve(pd[:k] / pd[:k].mean(), ker, "valid") * np.convolve(pg[:k] / pg[:k].mean(), ker, "valid")
        st = float(np.argmax(score)) * ENV_HOP
        del drums
        mix = sf.read(o / "mix.wav", dtype="float32")[0]
        write(cdir / "mix_dense.wav", cut(mix, st))
        nog = (mix.astype(np.float64) - gtr.astype(np.float64)).astype(np.float32)
        write(cdir / "backing_noguitar.wav", cut(nog, st))
        clips["mix_dense"] = {"song": "T1", "start_s": st, "criterion": "max producto de potencia media normalizada bateria x guitarras"}
        clips["backing_noguitar"] = {"song": "T1", "start_s": st, "criterion": "mix - stem guitar, mismo tramo que mix_dense"}
        # rhythm: mayor tasa de onsets del stem de guitarra con presencia sostenida
        m = mono_of(gtr)
        lvl = 20 * np.log10(envelope(m) + 1e-9)
        starts, mdb, act, rate = window_scan(lvl, onset_times(m))
        ok = (act >= ACTIVE_FRACTION) & (mdb >= np.median(lvl) - 6)
        i = int(np.argmax(np.where(ok, rate, -1)))
        write(cdir / "gtr_rhythm.wav", cut(gtr, starts[i] * ENV_HOP))
        clips["gtr_rhythm"] = {"song": "T1", "start_s": starts[i] * ENV_HOP, "onsets_per_s": round(float(rate[i]), 2),
                               "criterion": "max onsets/s del stem guitar con >=90 % de presencia"}
    for name, c in clips.items():
        c["file"] = f"clips/{name}.wav"
        c["duration_s"] = CLIP_SECONDS
        c["sha256"] = sha256(cdir / f"{name}.wav")
    return clips


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--songs", nargs="+", default=["T1", "T2", "T3"])
    ap.add_argument("--raw", type=Path, default=HERE / "out" / "raw")
    ap.add_argument("--out", type=Path, default=HERE / "out")
    a = ap.parse_args()
    results = {}
    for sid in a.songs:
        print(f"== {sid}", flush=True)
        results[sid] = process_song(sid, a.raw, a.out)
        r = results[sid]
        print(f"   {r['duration_s']} s, mix {r['mix_lufs']} LUFS, pico {r['mix_peak_dbfs']} dBFS, error suma {r['sum_error_max_abs']:.2e}", flush=True)
    clips = make_clips(results, a.out)
    manifest = {"sample_rate": SR, "format": "WAV float32 (di: PCM 24 bit, canales originales)",
                "songs": {s: {k: v for k, v in r.items() if not k.startswith("_")} for s, r in results.items()},
                "clips": clips}
    (a.out / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False, sort_keys=True))
    print("manifest escrito;", {k: v["start_s"] for k, v in clips.items()})


if __name__ == "__main__":
    main()
