"""Fase 5b: métricas reales de transcripción frente a la tablatura de Songsterr (verdad de referencia).

1. Songsterr (Temp/p5b/songsterr/<songId>/<parte>.json, de songsterr_fetch.py) → lista de notas por pista: tiempo en
   negras (compás + posición, con repeticiones desplegadas), duración, MIDI (afinación + cuerda + traste), cuerda
   (1 = la más aguda, como Guitab), traste; ligaduras unidas a la nota anterior de la misma cuerda; silencios fuera;
   muertas/fantasma/bends/slides marcados.
2. Alineación: negra k de la tablatura → tiempo con la rejilla de pulsos de la app (cache/analysis.json, Beat This!).
   Criterio: saliencia CQT del stem (guitarras → guitar.wav, bajo → bass.wav) en la altura exacta de cada nota tras su
   ataque (sin modelos). Desfase global entero de negras, luego desfase por bloques de 4 compases tocados (Viterbi con
   penalización por cambio) y ajuste fino en ms por F de ataques. La F de ataques sola y la DTW por croma se registran
   como diagnóstico: con rasgueo periódico no distinguen desfases de 2 negras.
3. Asignación pista → stem por correlación de croma y F de ataques (solo audio, sin modelos).
4. Métricas por stem × modelo (mir_eval): nota exacta (ataque ±50 ms + altura), clase de altura, solo ataque; para
   Guitab, cuerda/traste en las notas emparejadas; versión con puerta de silencio aproximada (fuera las notas cuyo
   ataque cae en silencio digital del stem). Solista: solo en el span 158,3–183,52 s.

Uso: Tools/py/.venv/bin/python Probes/P5b-guitarra/eval_reference.py [--song DIR] [--songsterr Temp/p5b/songsterr/50624]
Log: Temp/p5b/eval_reference.log; tabla: Temp/p5b/reference_metrics.{json,tsv}. No imprime contenido de la tablatura.
"""
import argparse
import json
import logging
import sys
import traceback
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run as R  # noqa: E402  (carga de stems, transcripción y caché de notas)

OUT = R.OUT
log = logging.getLogger("p5b.ref")
log.setLevel(logging.INFO)
log.propagate = False
_fh = logging.FileHandler(OUT / "eval_reference.log", mode="w")
_fh.setFormatter(logging.Formatter("%(asctime)s %(message)s"))
log.addHandler(_fh)


def _excepthook(t, v, tb):
    log.error("".join(traceback.format_exception(t, v, tb)))
    print(f"ERROR: {t.__name__}: {v} (ver {OUT / 'eval_reference.log'})")


sys.excepthook = _excepthook

import librosa  # noqa: E402
import mir_eval  # noqa: E402

TOL = 0.05
SOLO = (158.3, 183.52)
GUITAR_STEMS = ["guitar_L", "guitar_R", "guitar_lead"]
MODELS_GTR = ["basic_pitch", "guitab_e25", "guitab_e25_f03"]
SILENCE = 1e-5  # máx |x| por trama (≈ −100 dBFS) = silencio digital


# ---------------------------------------------------------------- 1. Songsterr → notas en negras

def expand_measures(measures):
    order, i, start, done = [], 0, 0, {}
    while i < len(measures):
        m = measures[i]
        if m.get("repeatStart"):
            start = i
        if m.get("alternateEnding"):
            log.warning("finales alternativos en el compás %d: no soportados", i + 1)
        order.append(i)
        if isinstance(m.get("repeat"), int) and m["repeat"] > 1:
            c = done.get(i, 0) + 1
            done[i] = c
            if c < m["repeat"]:
                i = start
                continue
        i += 1
    return order


def track_notes(j):
    tuning = j["tuning"]
    measures = j["measures"]
    order = expand_measures(measures)
    sig = [4, 4]
    sig_of = []
    for m in measures:
        sig = m.get("signature", sig)
        sig_of.append(sig)
    notes, flags = [], {"tie": 0, "dead": 0, "ghost": 0, "bend": 0, "slide": 0, "multi_voice_measures": 0}
    q0 = 0.0
    for play_idx, mi in enumerate(order):
        m = measures[mi]
        if len(m.get("voices", [])) > 1:
            flags["multi_voice_measures"] += 1
        for v in m.get("voices", [])[:1]:
            pos = 0.0
            last_on_string = {}
            for b in v.get("beats", []):
                num, den = b.get("duration", [1, 4])
                dq = 4.0 * num / den
                if not b.get("rest"):
                    for n in b.get("notes", []):
                        if n.get("rest") or "fret" not in n:
                            continue
                        s = int(n["string"])
                        for k in ("dead", "ghost", "bend", "slide"):
                            if n.get(k):
                                flags[k] += 1
                        if n.get("tie"):
                            flags["tie"] += 1
                            prev = last_on_string.get(s)
                            if prev is None:  # ligadura que viene del compás anterior
                                prev = next((x for x in reversed(notes) if x["string"] == s + 1), None)
                            if prev is not None:
                                prev["end_q"] = q0 + pos + dq
                                continue
                        note = {"q": q0 + pos, "end_q": q0 + pos + dq, "pitch": tuning[s] + int(n["fret"]),
                                "string": s + 1, "fret": int(n["fret"]), "bar": mi + 1, "play_bar": play_idx + 1,
                                "dead": bool(n.get("dead")), "ghost": bool(n.get("ghost"))}
                        notes.append(note)
                        last_on_string[s] = note
                pos += dq
        num, den = sig_of[mi]
        q0 += 4.0 * num / den
    return notes, flags, q0, order


# ---------------------------------------------------------------- 2. alineación con la rejilla de pulsos

class Grid:
    def __init__(self, beats):
        self.b = np.asarray(beats, float)
        self.step = float(np.median(np.diff(self.b[-16:])))
        self.step0 = float(np.median(np.diff(self.b[:16])))

    def time(self, q):
        q = np.asarray(q, float)
        n = len(self.b)
        i = np.floor(q).astype(int)
        frac = q - i
        out = np.empty_like(q)
        inside = (i >= 0) & (i < n - 1)
        out[inside] = self.b[i[inside]] + frac[inside] * (self.b[i[inside] + 1] - self.b[i[inside]])
        lo = i < 0
        out[lo] = self.b[0] + q[lo] * self.step0
        hi = i >= n - 1
        out[hi] = self.b[-1] + (q[hi] - (n - 1)) * self.step
        return out


def unique_onsets(t):
    t = np.sort(np.asarray(t))
    out = []
    for x in t:
        if not out or x - out[-1] > 0.03:
            out.append(x)
    return np.array(out)


def onset_f(ref_audio_on, tab_on):
    if len(ref_audio_on) == 0 or len(tab_on) == 0:
        return 0.0
    return mir_eval.onset.f_measure(ref_audio_on, tab_on, window=TOL)[0]


def align(grid, tabs, audio_on, beats_range=range(-48, 49)):
    """tabs: {nombre: notas}; audio_on: {nombre: onsets del stem}. Desfase en negras + fino en s."""
    qs = {k: unique_onsets([n["q"] for n in v]) for k, v in tabs.items()}

    def score(off_q, fine):
        return float(np.mean([onset_f(audio_on[k], grid.time(qs[k] + off_q) + fine) for k in tabs]))

    coarse = sorted(((score(o, 0.0), o) for o in beats_range), reverse=True)
    best_q = coarse[0][1]
    fine = sorted(((score(best_q, f), f) for f in np.arange(-0.08, 0.0801, 0.005)), reverse=True)
    return best_q, float(fine[0][1]), fine[0][0], coarse[:5], float(np.median([c[0] for c in coarse]))


def dtw_align(grid, tracks, y_mix, total_q, pad_beats=8):
    """DTW entre croma por negra de la tablatura (todas las pistas) y croma por pulso del audio (guitarras + bajo).
    Rejilla ampliada con pad_beats pulsos extrapolados a cada lado. Devuelve: tiempo de cada negra entera
    (np.nan si la negra no tiene pulso propio), tramos fuera de la diagonal y la ruta."""
    nq = int(np.ceil(total_q))
    tab = np.zeros((12, nq), np.float32)
    for v in tracks.values():
        for n in v["notes"]:
            a, b = n["q"], max(n["end_q"], n["q"] + 0.25)
            for k in range(int(a), min(int(np.ceil(b)), nq)):
                tab[n["pitch"] % 12, k] += min(b, k + 1) - max(a, k)
    dur = len(y_mix) / R.SR
    pre = [grid.b[0] - i * grid.step0 for i in range(pad_beats, 0, -1)]
    post = [grid.b[-1] + i * grid.step for i in range(1, pad_beats + 1)]
    bt = np.array([t for t in pre if t >= 0] + list(grid.b) + [t for t in post if t < dur])
    hop = 512
    ch = librosa.feature.chroma_cqt(y=y_mix, sr=R.SR, hop_length=hop)
    frames = librosa.time_to_frames(np.append(bt, min(bt[-1] + grid.step, dur)), sr=R.SR, hop_length=hop)
    aud = np.stack([ch[:, frames[i]:max(frames[i + 1], frames[i] + 1)].mean(1) for i in range(len(bt))], 1)
    # 13.ª dimensión «silencio» para que el coseno exista en negras/pulsos vacíos
    tab = np.vstack([tab / (tab.max(0, keepdims=True) + 1e-9), (tab.sum(0, keepdims=True) == 0).astype(np.float32)]) + 1e-4
    aud = np.vstack([aud, (aud.max(0, keepdims=True) < 1e-3).astype(np.float32)]) + 1e-4
    cost = librosa.sequence.dtw(X=tab, Y=aud, metric="cosine", subseq=False,
                                            step_sizes_sigma=np.array([[1, 1], [1, 0], [0, 1]]),
                                            weights_add=np.array([0.0, 0.3, 0.3]), backtrack=True)
    _, wp = cost
    wp = wp[::-1]
    q2b = {}
    for q, b in wp:
        q2b.setdefault(int(q), []).append(int(b))
    tq = np.full(nq + 1, np.nan)
    used = set()
    for q in range(nq):
        bs = q2b.get(q, [])
        b = bs[0] if bs else None
        if b is not None and b not in used:  # varias negras en un pulso: solo la primera tiene tiempo
            tq[q] = bt[b]
            used.add(b)
    # tramos fuera de la diagonal (≥ 2 pasos seguidos): negras sin pulso (sobran en la tablatura) o pulsos sin negra
    runs, cur = [], None
    for (q0, b0), (q1, b1) in zip(wp[:-1], wp[1:]):
        kind = "diag" if (q1 - q0, b1 - b0) == (1, 1) else ("tab_extra" if b1 == b0 else "audio_extra")
        if cur and cur[0] == kind:
            cur[2] = (q1, b1)
            cur[3] += 1
        else:
            if cur:
                runs.append(cur)
            cur = [kind, (q0, b0), (q1, b1), 1]
    runs.append(cur)
    off = [r for r in runs if r[0] != "diag" and r[3] >= 2]
    diag_frac = sum(r[3] for r in runs if r[0] == "diag") / max(len(wp) - 1, 1)
    return tq, bt, off, diag_frac, wp


def apply_dtw_times(notes, tq, fine):
    """Tiempo de cada nota por interpolación entre negras enteras con tiempo; notas en negras sin tiempo: fuera."""
    out = []
    nq = len(tq) - 1
    for n in notes:
        k = int(np.floor(n["q"]))
        if k >= nq or np.isnan(tq[k]):
            continue
        nxt = tq[k + 1] if k + 1 <= nq and not np.isnan(tq[k + 1]) else tq[k] + 60 / 172
        on = tq[k] + (n["q"] - k) * (nxt - tq[k]) + fine
        e = n["end_q"]
        ke = min(int(np.floor(e)), nq - 1)
        if not np.isnan(tq[ke]):
            nx = tq[ke + 1] if ke + 1 <= nq and not np.isnan(tq[ke + 1]) else tq[ke] + 60 / 172
            off = tq[ke] + (e - ke) * (nx - tq[ke]) + fine
        else:
            off = on + (e - n["q"]) * 60 / 172
        out.append(dict(n, onset=float(on), offset=float(max(off, on + 0.02))))
    return out


CQT_MIDI0 = 28  # E1


def cqt_salience(y):
    """CQT 12 bins/octava desde E1 (84 bins), hop 256, normalizada por trama a [0, 1]."""
    c = np.abs(librosa.cqt(y, sr=R.SR, hop_length=256, fmin=librosa.midi_to_hz(CQT_MIDI0), n_bins=84,
                           bins_per_octave=12))
    return c / (c.max(axis=0, keepdims=True) + 1e-9)


def salience(grid, notes, shift, sal, fine=0.0):
    """Media de la saliencia CQT en la altura de cada nota, en las 4 tramas tras su ataque (con el desfase dado)."""
    if not notes:
        return 0.0
    t = grid.time(np.array([n["q"] for n in notes]) + shift) + fine
    f = np.clip((t * R.SR / 256).astype(int), 0, sal.shape[1] - 4)
    b = np.clip(np.array([n["pitch"] for n in notes]) - CQT_MIDI0, 0, sal.shape[0] - 1)
    return float(np.mean(np.max(np.stack([sal[b, f + d] for d in range(4)]), axis=0)))


def piecewise_align(grid, tracks, sal_for, off_q, fine, block_bars=4, shifts=range(-12, 13), penalty=0.02):
    """Desfase por bloques de compases tocados (Viterbi): puntuación = saliencia CQT media de las notas de todas las
    pistas en su stem; cada cambio de desfase cuesta `penalty`. Devuelve desfase (negras) por bloque."""
    n_bars = int(max(n["play_bar"] for v in tracks.values() for n in v["notes"]))
    blocks = list(range(1, n_bars + 1, block_bars))
    S = list(shifts)
    score = np.zeros((len(blocks), len(S)))
    for bi, b0 in enumerate(blocks):
        for k, v in tracks.items():
            sel = [n for n in v["notes"] if b0 <= n["play_bar"] < b0 + block_bars]
            if len(sel) < 3:
                continue
            for si, s in enumerate(S):
                score[bi, si] += salience(grid, sel, off_q + s, sal_for[k], fine) / len(tracks)
    acc = score[0].copy()
    back = np.zeros((len(blocks), len(S)), int)
    for bi in range(1, len(blocks)):
        trans = acc[None, :] - penalty * (np.arange(len(S))[:, None] != np.arange(len(S))[None, :])
        back[bi] = trans.argmax(1)
        acc = score[bi] + trans.max(1)
    path = [int(acc.argmax())]
    for bi in range(len(blocks) - 1, 0, -1):
        path.append(int(back[bi, path[-1]]))
    path = path[::-1]
    return {b0: S[p] for b0, p in zip(blocks, path)}, block_bars


def structure_check(grid, notes, audio_on, off_q, fine, block_bars=4):
    """Por bloques de 4 compases tocados: mejor desfase local (±8 negras) frente al global."""
    out = []
    bars = sorted({n["play_bar"] for n in notes})
    for b0 in range(1, max(bars) + 1, block_bars):
        sel = [n for n in notes if b0 <= n["play_bar"] < b0 + block_bars]
        if len(sel) < 4:
            continue
        q = unique_onsets([n["q"] for n in sel])
        t_lo, t_hi = grid.time([q.min() + off_q - 8])[0] - 0.1, grid.time([q.max() + off_q + 8])[0] + 0.1
        aon = audio_on[(audio_on >= t_lo) & (audio_on <= t_hi)]
        sc = {d: onset_f(aon, grid.time(q + off_q + d) + fine) for d in range(-8, 9)}
        best = max(sc, key=sc.get)
        out.append({"bars": f"{b0}-{b0 + block_bars - 1}", "src_bars": f"{sel[0]['bar']}-{sel[-1]['bar']}",
                    "f0": round(sc[0], 3), "best_shift_q": best, "f_best": round(sc[best], 3)})
    return out


# ---------------------------------------------------------------- 3. asignación pista → stem

def chroma_roll(notes_t, n_frames, fps):
    c = np.zeros((12, n_frames), np.float32)
    for n in notes_t:
        a, b = int(n["onset"] * fps), max(int(n["offset"] * fps), int(n["onset"] * fps) + 1)
        c[n["pitch"] % 12, a:min(b, n_frames)] += 1
    return c


def chroma_corr(y, notes_t, span=None):
    fps = R.SR / 2048
    ch = librosa.feature.chroma_cqt(y=y, sr=R.SR, hop_length=2048)
    roll = chroma_roll(notes_t, ch.shape[1], fps)
    act = (roll.sum(0) > 0) & (ch.max(0) > 0)
    if span:
        t = np.arange(ch.shape[1]) / fps
        act &= (t >= span[0]) & (t < span[1])
    if act.sum() < 10:
        return float("nan")
    a = ch[:, act] / (np.linalg.norm(ch[:, act], axis=0) + 1e-9)
    b = roll[:, act] / (np.linalg.norm(roll[:, act], axis=0) + 1e-9)
    return float((a * b).sum(0).mean())


# ---------------------------------------------------------------- 4. métricas de notas

def arr(notes):
    if not notes:
        return np.zeros((0, 2)), np.zeros(0)
    iv = np.array([[n["onset"], max(n["offset"], n["onset"] + 0.02)] for n in notes])
    return iv, np.array([440.0 * 2 ** ((n["pitch"] - 69) / 12) for n in notes])


def prf(ref, est, mode):
    if not ref or not est:
        return (0.0, 0.0, 0.0)
    if mode == "pc":
        ref = [dict(n, pitch=60 + n["pitch"] % 12) for n in ref]
        est = [dict(n, pitch=60 + n["pitch"] % 12) for n in est]
    elif mode == "onset":
        ref = [dict(n, pitch=60) for n in ref]
        est = [dict(n, pitch=60) for n in est]
    ri, rp = arr(ref)
    ei, ep = arr(est)
    p, r, f, _ = mir_eval.transcription.precision_recall_f1_overlap(ri, rp, ei, ep, onset_tolerance=TOL,
                                                                    pitch_tolerance=50.0, offset_ratio=None)
    return (p, r, f)


def string_fret(ref, est):
    if not ref or not est or "string" not in est[0]:
        return None
    ri, rp = arr(ref)
    ei, ep = arr(est)
    pairs = mir_eval.transcription.match_notes(ri, rp, ei, ep, onset_tolerance=TOL, pitch_tolerance=50.0, offset_ratio=None)
    if not pairs:
        return None
    same = [ref[i]["string"] == est[j]["string"] for i, j in pairs]
    return {"matched": len(pairs), "string_fret_agree": float(np.mean(same))}


def silent_frames(y):
    fr = librosa.util.frame(np.pad(y, (0, 1024)), frame_length=1024, hop_length=256)
    return np.abs(fr).max(axis=0) < SILENCE


def gate(notes, sil):
    return [n for n in notes if not sil[min(int(n["onset"] * R.SR / 256), len(sil) - 1)]]


def in_span(notes, span):
    return [n for n in notes if span[0] <= n["onset"] < span[1]] if span else notes


def get_notes(tag, stem, model, y):
    nj = OUT / tag / f"{stem}_{model}.json"
    if nj.exists():
        return json.loads(nj.read_text())["notes"]
    notes, dt, info = R.transcribe(model, y, "cpu")
    nj.write_text(json.dumps({"notes": notes, "infer_s": dt, "info": info}))
    return notes


# ---------------------------------------------------------------- principal

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--song", type=Path, default=R.DEFAULT_SONG)
    ap.add_argument("--songsterr", type=Path, default=OUT / "songsterr" / "50624")
    ap.add_argument("--stems", default=",".join(GUITAR_STEMS + ["guitar", "bass"]))
    ap.add_argument("--extra", default="", help="modelos extra para los stems de guitarra (JSON ya en Temp/p5b/<tema>/)")
    ap.add_argument("--out-tag", default="", help="sufijo de reference_metrics<_tag>.{json,tsv}")
    a = ap.parse_args()
    extra = [m for m in a.extra.split(",") if m]
    sfx = f"_{a.out_tag}" if a.out_tag else ""
    song = a.song.expanduser()
    tag = R.song_tag(song)
    (OUT / tag).mkdir(exist_ok=True)
    meta = json.loads((a.songsterr / "meta.json").read_text())
    _, _, beats = R.load_song(song)
    grid = Grid(beats["beats"])
    log.info("rejilla: %d pulsos, primer %.3f s, bpm %.2f", len(grid.b), grid.b[0], beats["bpm"])

    tracks = {}
    for t in meta["tracks"]:
        f = a.songsterr / f"{t['partId']}.json"
        if not f.exists():
            continue
        j = json.loads(f.read_text())
        notes, flags, total_q, order = track_notes(j)
        kind = "bass" if j["strings"] == 4 or "Bass" in j["instrument"] else "guitar"
        name = (t.get("name") or t.get("title") or str(t["partId"])).split(" - ")[0]
        tracks[name] = {"notes": notes, "kind": kind, "flags": flags, "total_q": total_q, "n_bars": len(j["measures"]),
                        "played_bars": len(order), "tempo": [(x["measure"] + 1, x["bpm"]) for x in j["automations"]["tempo"]]}
        log.info("pista %s (%s): %d notas, %d compases (%d tocados con repeticiones), %.0f negras; marcas %s; tempo %s",
                 name, kind, len(notes), len(j["measures"]), len(order), total_q, flags, tracks[name]["tempo"])

    stems = {s: R.load_stem(song / "stems" / f"{s}.wav") for s in GUITAR_STEMS + ["guitar", "bass"]}
    act = {s: R.stem_activity(y) for s, y in stems.items()}
    aon = {s: R.ref_onsets(y, act[s]) for s, y in stems.items()}

    # 2. alineación global (todas las pistas a la vez: guitarras frente a guitar.wav, bajo frente a bass.wav)
    tabs = {k: v["notes"] for k, v in tracks.items()}
    audio_for = {k: aon["bass" if v["kind"] == "bass" else "guitar"] for k, v in tracks.items()}
    off_q, fine, f_best, top, f_median = align(grid, tabs, audio_for)
    log.info("alineación por ataques: desfase %d negras + %.0f ms, F ataques %.3f (mediana de desfases %.3f); top5 %s",
             off_q, fine * 1000, f_best, f_median, top)
    sal_stem = {"guitar": cqt_salience(stems["guitar"]), "bass": cqt_salience(stems["bass"])}
    sal_for = {k: sal_stem["bass" if v["kind"] == "bass" else "guitar"] for k, v in tracks.items()}
    gs = sorted(((float(np.mean([salience(grid, v["notes"], o, sal_for[k]) for k, v in tracks.items()])), o)
                 for o in range(-48, 49)), reverse=True)
    sal_global = gs[0][0]
    log.info("alineación por saliencia CQT: top5 %s, mediana %.3f", [(round(s, 3), o) for s, o in gs[:5]],
             float(np.median([s for s, _ in gs])))
    if gs[0][1] != off_q:
        off_q = gs[0][1]
        fine = sorted(((float(np.mean([onset_f(audio_for[k], grid.time(unique_onsets([n["q"] for n in v["notes"]]) + off_q) + f)
                                       for k, v in tracks.items()])), f) for f in np.arange(-0.08, 0.0801, 0.005)),
                      reverse=True)[0][1]
        f_best = float(np.mean([onset_f(audio_for[k], grid.time(unique_onsets([n["q"] for n in v["notes"]]) + off_q) + fine)
                                for k, v in tracks.items()]))
        log.info("desfase global por saliencia: %d negras + %.0f ms (F ataques %.3f)", off_q, fine * 1000, f_best)
    struct = {}
    for k, v in tracks.items():
        sc = structure_check(grid, v["notes"], audio_for[k], off_q, fine)
        bad = [s for s in sc if s["best_shift_q"] != 0 and s["f_best"] - s["f0"] > 0.15]
        struct[k] = {"global_blocks": len(sc), "global_mismatch": bad,
                     "global_f0_median": float(np.median([s["f0"] for s in sc]))}
        log.info("estructura (desfase global) %s: %d bloques, F0 mediana %.3f, bloques con otro desfase local: %s",
                 k, len(sc), struct[k]["global_f0_median"], [(s["src_bars"], s["best_shift_q"]) for s in bad])

    # 2b. DTW por pulsos (admite repeticiones que faltan o sobran)
    total_q = max(v["total_q"] for v in tracks.values())
    tq, bt, offdiag, diag_frac, _ = dtw_align(grid, tracks, stems["guitar"] + stems["bass"], total_q)
    q_bar = {}
    for v in tracks.values():
        for n in v["notes"]:
            q_bar.setdefault(int(n["q"]) // 4, n["bar"])
    offdiag_bars = [(r[0], f"compás tocado {r[1][0] // 4 + 1}-{r[2][0] // 4 + 1} (original {q_bar.get(r[1][0] // 4, '?')}-"
                     f"{q_bar.get(r[2][0] // 4, '?')})", f"{bt[r[1][1]]:.1f}-{bt[r[2][1]]:.1f} s", r[3]) for r in offdiag]
    log.info("DTW: %.1f %% de pasos en diagonal; tramos fuera de la diagonal (≥2): %s", diag_frac * 100, offdiag_bars)

    def dtw_score(fine_s):
        return float(np.mean([onset_f(audio_for[k], unique_onsets([n["onset"] for n in apply_dtw_times(v["notes"], tq, fine_s)]))
                              for k, v in tracks.items()]))
    fines = sorted(((dtw_score(f), f) for f in np.arange(-0.08, 0.0801, 0.005)), reverse=True)
    dtw_f, dtw_fine = fines[0]
    log.info("DTW: ajuste fino %+.0f ms, F ataques %.3f (desfase global: %.3f)", dtw_fine * 1000, dtw_f, f_best)
    # 2c. desfase por tramos (Viterbi sobre bloques de 4 compases tocados)
    pw, bb = piecewise_align(grid, tracks, sal_for, off_q, fine)
    changes, prev = [], None
    for b0, s in pw.items():
        if s != prev:
            src = next((n["bar"] for v in tracks.values() for n in v["notes"] if n["play_bar"] >= b0), "?")
            changes.append((b0, src, s))
            prev = s
    q_shift = lambda n: pw[1 + ((n["play_bar"] - 1) // bb) * bb]  # noqa: E731

    def pw_times(notes):
        q = np.array([n["q"] + off_q + q_shift(n) for n in notes])
        e = np.array([n["end_q"] + off_q + q_shift(n) for n in notes])
        return [dict(n, onset=float(o), offset=float(x)) for n, o, x in zip(notes, grid.time(q) + fine, grid.time(e) + fine)]
    pw_f = float(np.mean([onset_f(audio_for[k], unique_onsets([n["onset"] for n in pw_times(v["notes"])]))
                          for k, v in tracks.items()]))
    sal_pw = float(np.mean([np.mean([salience(grid, [n], off_q + q_shift(n), sal_for[k], fine) for n in v["notes"]])
                            for k, v in tracks.items()]))
    log.info("por tramos: cambios de desfase (compás tocado, compás original, negras sobre el global) %s; F ataques %.3f; "
             "saliencia %.3f (global %.3f)", changes, pw_f, sal_pw, sal_global)
    struct["piecewise"] = {"changes": changes, "F": pw_f, "salience": sal_pw, "salience_global": sal_global}
    use_dtw = False  # la DTW por croma no distingue desfases de 2 negras (ver log); queda como diagnóstico
    use_pw = sal_pw > sal_global + 0.01
    struct["method"] = "dtw" if use_dtw else ("piecewise" if use_pw else "global")
    for k, v in tracks.items():
        if use_pw:
            v["notes"] = pw_times(v["notes"])
        elif use_dtw:
            kept = apply_dtw_times(v["notes"], tq, dtw_fine)
            log.info("pista %s: %d de %d notas con tiempo DTW (las demás caen en negras que sobran)", k, len(kept), len(v["notes"]))
            v["notes"] = kept
        else:
            q = np.array([n["q"] for n in v["notes"]]) + off_q
            on, en = grid.time(q) + fine, grid.time(np.array([n["end_q"] for n in v["notes"]]) + off_q) + fine
            for n, o, e in zip(v["notes"], on, en):
                n["onset"], n["offset"] = float(o), float(e)
        per_track_f = onset_f(audio_for[k], unique_onsets([n["onset"] for n in v["notes"]]))
        struct[k]["final_onset_F"] = per_track_f
        log.info("pista %s: F ataques final %.3f, primera nota %.2f s, última %.2f s", k, per_track_f,
                 min(n["onset"] for n in v["notes"]), max(n["onset"] for n in v["notes"]))
    struct["dtw"] = {"used": use_dtw, "diag_frac": diag_frac, "fine_ms": dtw_fine * 1000, "F": dtw_f, "offdiag": offdiag_bars}

    # 3. asignación pista → stem (croma + ataques; solista solo en el span del solo)
    assign = {}
    for k, v in tracks.items():
        for s in (["bass"] if v["kind"] == "bass" else GUITAR_STEMS + ["guitar"]):
            span = SOLO if s == "guitar_lead" else None
            cc = chroma_corr(stems[s], in_span(v["notes"], span), span)
            ref_on = aon[s] if not span else aon[s][(aon[s] >= span[0]) & (aon[s] < span[1])]
            of = onset_f(ref_on, unique_onsets([n["onset"] for n in in_span(v["notes"], span)]))
            assign[(k, s)] = (cc, of)
            log.info("asignación %s → %s: croma %.3f, F ataques %.3f", k, s, cc, of)
    gtr = [k for k, v in tracks.items() if v["kind"] == "guitar"]
    mapping = {"bass": [k for k, v in tracks.items() if v["kind"] == "bass"]}
    for s in GUITAR_STEMS:
        mapping[s] = [max(gtr, key=lambda k: assign[(k, s)][0] + assign[(k, s)][1])]
    if mapping["guitar_L"] == mapping["guitar_R"]:  # una pista por lado: la asignación conjunta de mayor puntuación
        a1 = sum(assign[(gtr[0], "guitar_L")]) + sum(assign[(gtr[1], "guitar_R")])
        a2 = sum(assign[(gtr[1], "guitar_L")]) + sum(assign[(gtr[0], "guitar_R")])
        mapping["guitar_L"], mapping["guitar_R"] = ([gtr[0]], [gtr[1]]) if a1 >= a2 else ([gtr[1]], [gtr[0]])
    mapping["guitar"] = gtr
    log.info("asignación final: %s", mapping)

    # 4. métricas
    res = {}
    for s in a.stems.split(","):
        span = SOLO if s == "guitar_lead" else None
        ref = in_span([n for k in mapping[s] for n in tracks[k]["notes"]], span)
        sil = silent_frames(stems[s])
        for model in (["basic_pitch"] if s == "bass" else MODELS_GTR + extra):
            est_all = get_notes(tag, s, model, stems[s])
            for gated in ((False,) if model.startswith("btc_") else (False, True)):
                est = in_span(gate(est_all, sil) if gated else est_all, span)
                row = {"n_ref": len(ref), "n_est": len(est)}
                for mode in ("note", "pc", "onset"):
                    p, r, f = prf(ref, est, mode)
                    row.update({f"{mode}_P": p, f"{mode}_R": r, f"{mode}_F": f})
                sf_ = string_fret(ref, est)
                if sf_:
                    row.update(sf_)
                key = f"{tag}/{s}/{model}{'/gate' if gated else ''}"
                res[key] = row
                log.info("%s %s", key, json.dumps({k: (round(v, 3) if isinstance(v, float) else v) for k, v in row.items()}))
    summary = {"url": meta["url"], "songId": meta["songId"], "revisionId": meta["revisionId"],
               "tracks": {k: {kk: v[kk] for kk in ("kind", "flags", "n_bars", "played_bars", "total_q", "tempo")} | {"n_notes": len(v["notes"])} for k, v in tracks.items()},
               "offset_q": off_q, "fine_ms": fine * 1000, "align_F": f_best, "align_F_median_offsets": f_median,
               "structure": struct, "mapping": mapping,
               "assign": {f"{k}->{s}": v for (k, s), v in assign.items()}, "metrics": res}
    (OUT / f"reference_metrics{sfx}.json").write_text(json.dumps(summary, indent=1, ensure_ascii=False))
    cols = ["n_ref", "n_est", "note_P", "note_R", "note_F", "pc_F", "onset_F", "string_fret_agree"]
    lines = ["key\t" + "\t".join(cols)]
    for k, m in res.items():
        lines.append(k + "\t" + "\t".join(f"{m[c]:.3f}" if isinstance(m.get(c), float) else str(m.get(c, "")) for c in cols))
    (OUT / f"reference_metrics{sfx}.tsv").write_text("\n".join(lines) + "\n")
    # notas de referencia ya alineadas, para análisis por compases (Temp, no se versiona)
    (OUT / tag / f"reference_aligned{sfx}.json").write_text(json.dumps(
        {s: [n for k in mapping[s] for n in tracks[k]["notes"]] for s in mapping}))
    print(f"desfase {off_q} negras {fine * 1000:+.0f} ms, F alineación {f_best:.3f}; asignación {mapping}; "
          f"{len(res)} filas en {OUT / f'reference_metrics{sfx}.tsv'}")


if __name__ == "__main__":
    main()
