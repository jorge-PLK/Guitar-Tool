"""Fase 5b, prototipo A: rítmica híbrida por bloques de compás.

Bloque «rasgueado» → BTC p58 con ataques de Guitab (btc_p58_gt, de btc_rhythm.py); bloque «riff» → notas de Guitab E25.
La decisión usa SOLO salidas de modelo, nunca la referencia: proporción de grupos de ataque (≤ 30 ms) con ≥ 2 notas
simultáneas en el bloque, medida en Guitab E25 (`gt`) o en Basic Pitch con puerta de silencio (`bp`). Compases =
downbeats de la app (Beat This!). Bloques de 1 y 2 compases.
El rasgo y el umbral se eligen en guitar_L (frente a Songsterr); guitar_R es la prueba independiente (no se ajusta).
Requiere: run.py, btc_rhythm.py y eval_reference.py ejecutados (Temp/p5b/<tema>/reference_aligned_btc.json).

Uso: Tools/py/.venv/bin/python Probes/P5b-guitarra/hybrid.py
Escribe <stem>_hybrid_b{1,2}.json, CHECK_El_roce_<stem>_hybrid_estereo.wav y Temp/p5b/hybrid_metrics.tsv.
"""
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import eval_reference as E  # noqa: E402

R = E.R
THRESHOLDS = [round(x, 1) for x in np.arange(0.1, 0.95, 0.1)]


def clusters(notes):
    """Lista de tamaños de grupo de ataque por tiempo de inicio (grupos ≤ 30 ms)."""
    out = []
    for n in sorted(notes, key=lambda n: n["onset"]):
        if out and n["onset"] - out[-1][0] <= 0.03:
            out[-1][1] += 1
        else:
            out.append([n["onset"], 1])
    return out


def poly_share(cl, t0, t1):
    sel = [c for t, c in cl if t0 <= t < t1]
    return (np.mean([c >= 2 for c in sel]), len(sel)) if sel else (0.0, 0)


def build(gt, btc, feat_cl, downbeats, k, thr):
    edges = list(downbeats[::k]) + [1e9]
    out, strummed = [], []
    first = [n for n in gt if n["onset"] < edges[0]]
    out += first
    for t0, t1 in zip(edges[:-1], edges[1:]):
        share, n = poly_share(feat_cl, t0, t1)
        is_strum = n > 0 and share >= thr
        strummed.append(is_strum)
        src = btc if is_strum else gt
        out += [n for n in src if t0 <= n["onset"] < t1]
    return out, float(np.mean(strummed))


def main():
    song = R.DEFAULT_SONG
    tag = R.song_tag(song)
    d = R.OUT / tag
    an = json.loads((song / "cache" / "analysis.json").read_text())["analysis"]
    downbeats = an["beats"]["downbeats"]
    ref_all = json.loads((d / "reference_aligned_btc.json").read_text())
    stems = ["guitar_L", "guitar_R", "guitar"]
    data = {}
    for s in stems:
        y = R.load_stem(song / "stems" / f"{s}.wav")
        sil = E.silent_frames(y)
        ld = lambda m: json.loads((d / f"{s}_{m}.json").read_text())["notes"]  # noqa: E731
        data[s] = {"y": y, "gt": ld("guitab_e25"), "btc": ld("btc_p58_gt"), "bp": E.gate(ld("basic_pitch"), sil),
                   "bp_raw": ld("basic_pitch"), "ref": ref_all[s]}
        data[s]["cl"] = {"gt": clusters(data[s]["gt"]), "bp": clusters(data[s]["bp"])}

    # ajuste en guitar_L
    L = data["guitar_L"]
    tune = []
    for k in (1, 2):
        for feat in ("gt", "bp"):
            for thr in THRESHOLDS:
                notes, frac = build(L["gt"], L["btc"], L["cl"][feat], downbeats, k, thr)
                p, r, f = E.prf(L["ref"], notes, "note")
                tune.append((f, k, feat, thr, frac))
    lines = ["# ajuste en guitar_L (note F, bloque, rasgo, umbral, fracción de bloques rasgueados)"]
    best = {}
    for k in (1, 2):
        cand = sorted([t for t in tune if t[1] == k], reverse=True)
        best[k] = cand[0]
        lines.append(f"b{k} top3: " + "; ".join(f"F {f:.3f} {feat}>={thr} rasg {fr:.2f}" for f, _, feat, thr, fr in cand[:3]))

    cols = ["n_est", "note_P", "note_R", "note_F", "pc_F", "onset_F", "sf_agree"]
    lines.append("key\t" + "\t".join(cols))
    for s in stems:
        D = data[s]
        rows = {"basic_pitch": D["bp_raw"], "guitab_e25": D["gt"], "btc_p58_gt": D["btc"]}
        for k in (1, 2):
            _, _, feat, thr, _ = best[k]
            notes, frac = build(D["gt"], D["btc"], D["cl"][feat], downbeats, k, thr)
            rows[f"hybrid_b{k}"] = notes
            (d / f"{s}_hybrid_b{k}.json").write_text(json.dumps({"notes": notes, "infer_s": 0.0,
                                                                 "info": {"feat": feat, "thr": thr, "strum_frac": frac}}))
            lines.append(f"# {s} hybrid_b{k}: {feat}>={thr}, bloques rasgueados {frac:.2f}")
        for m, notes in rows.items():
            P = E.prf(D["ref"], notes, "note")
            pc = E.prf(D["ref"], notes, "pc")[2]
            on = E.prf(D["ref"], notes, "onset")[2]
            sf_ = E.string_fret(D["ref"], notes)
            vals = [len(notes), *P, pc, on, sf_["string_fret_agree"] if sf_ else float("nan")]
            lines.append(f"{s}/{m}\t" + "\t".join(f"{v:.3f}" if isinstance(v, float) else str(v) for v in vals))
    (R.OUT / "hybrid_metrics.tsv").write_text("\n".join(lines) + "\n")
    # CHECK_ con el bloque que mejor quede en guitar_L
    kbest = max((1, 2), key=lambda k: best[k][0])
    for s in ("guitar_L", "guitar_R"):
        notes = json.loads((d / f"{s}_hybrid_b{kbest}.json").read_text())["notes"]
        x = R.synth(notes, len(data[s]["y"]))
        y = data[s]["y"] / (np.abs(data[s]["y"]).max() + 1e-9) * 0.8
        R.sf.write(str(d / f"CHECK_{tag}_{s}_hybrid_estereo.wav"), np.stack([y, x], 1), R.SR, subtype="PCM_16")
    print(f"{R.OUT / 'hybrid_metrics.tsv'}; CHECK_ con b{kbest}")


if __name__ == "__main__":
    main()
