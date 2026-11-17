"""Fase 5b, prototipo B: limpieza del solista (independiente del modelo), en el span del solo 158,3–183,52 s.

Entrada: Basic Pitch con puerta de silencio digital y Guitab E25 sobre guitar_lead. Pasos (umbrales fijados a priori):
  1 techo de registro: fuera notas > MIDI 86 (traste 22 en la 1.ª cuerda, E4 = 64 + 22; las guitarras de 22 trastes
    son las más comunes y la pista solista de Songsterr declara su número de trastes, ver log).
  2 armónicos/octavas: fuera una nota si otra que suena a la vez (solape > 0) está 12, 19 o 24 semitonos por debajo y
    tiene amplitud ≥ la suya.
  3 sangrado de la rítmica: fuera si amplitud < percentil 25 de las amplitudes del span Y su clase de altura está en el
    acorde BTC vigente Y su altura < mediana de alturas del span.
  4 monofonía: en cada grupo de ataques (≤ 30 ms) solo la nota más fuerte.
Ablación: cada paso solo sobre la base, y acumulado 1→2→3→4.
Métricas frente a la referencia alineada (reference_aligned_btc.json de eval_reference.py).
CHECK_: Temp/p5b/El_roce/CHECK_El_roce_lead_<modelo>_clean_estereo.wav, 155–186 s, stem izquierda y síntesis derecha.

Uso: Tools/py/.venv/bin/python Probes/P5b-guitarra/lead_clean.py
"""
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import eval_reference as E  # noqa: E402

R = E.R
SPAN = E.SOLO
CAP = 86
HARM = (12, 19, 24)
CLIP = (155.0, 186.0)


def step_cap(notes, ctx):
    return [n for n in notes if n["pitch"] <= CAP]


def step_harm(notes, ctx):
    drop = set()
    for i, n in enumerate(notes):
        for j, m in enumerate(notes):
            if i != j and (n["pitch"] - m["pitch"]) in HARM and m["amp"] >= n["amp"] \
                    and min(n["offset"], m["offset"]) - max(n["onset"], m["onset"]) > 0:
                drop.add(i)
                break
    return [n for i, n in enumerate(notes) if i not in drop]


def step_bleed(notes, ctx):
    amp25, pmed = ctx["amp25"], ctx["pmed"]
    segs, starts = ctx["segs"], ctx["starts"]

    def chord_pcs(t):
        j = max(int(np.searchsorted(starts, t, side="right")) - 1, 0)
        return R.chord_pcs(segs[j]["index"]) or set()
    return [n for n in notes if not (n["amp"] < amp25 and n["pitch"] % 12 in chord_pcs(n["onset"]) and n["pitch"] < pmed)]


def step_mono(notes, ctx):
    out, group = [], []
    for n in sorted(notes, key=lambda n: n["onset"]):
        if group and n["onset"] - group[0]["onset"] > 0.03:
            out.append(max(group, key=lambda m: m["amp"]))
            group = []
        group.append(n)
    if group:
        out.append(max(group, key=lambda m: m["amp"]))
    return out


STEPS = [("1_cap", step_cap), ("2_harm", step_harm), ("3_bleed", step_bleed), ("4_mono", step_mono)]


def scores(ref, est):
    p, r, f = E.prf(ref, est, "note")
    return {"n": len(est), "P": p, "R": r, "F": f, "pcF": E.prf(ref, est, "pc")[2]}


def main():
    song = R.DEFAULT_SONG
    tag = R.song_tag(song)
    d = R.OUT / tag
    an = json.loads((song / "cache" / "analysis.json").read_text())["analysis"]
    segs = an["chords"]["segments"]
    ref = E.in_span(json.loads((d / "reference_aligned_btc.json").read_text())["guitar_lead"], SPAN)
    meta = json.loads((R.OUT / "songsterr" / "50624" / "meta.json").read_text())
    lead_part = json.loads((R.OUT / "songsterr" / "50624" / "0.json").read_text())  # Uoho = solista (asignación)
    y = R.load_stem(song / "stems" / "guitar_lead.wav")
    sil = E.silent_frames(y)
    rc = [n["onset"] for n in ref]
    groups = []
    for t in sorted(rc):
        if groups and t - groups[-1][0] <= 0.03:
            groups[-1][1] += 1
        else:
            groups.append([t, 1])
    lines = [f"referencia solista en el span: {len(ref)} notas, {len(groups)} ataques, monofónicos "
             f"{np.mean([c == 1 for _, c in groups]):.2f}; notas > {CAP}: {sum(n['pitch'] > CAP for n in ref)}; "
             f"máx MIDI {max(n['pitch'] for n in ref)}; trastes declarados por la pista: {lead_part.get('frets')}",
             f"(pista de Songsterr usada: {meta['tracks'][0].get('name') or meta['tracks'][0].get('title')})",
             "modelo\tvariante\tn\tP\tR\tF\tpcF\tquitadas"]
    for model in ("basic_pitch", "guitab_e25"):
        raw = json.loads((d / f"guitar_lead_{model}.json").read_text())["notes"]
        base = E.in_span(E.gate(raw, sil), SPAN)
        amps = np.array([n["amp"] for n in base])
        ctx = {"amp25": float(np.percentile(amps, 25)), "pmed": float(np.median([n["pitch"] for n in base])),
               "segs": segs, "starts": np.array([s["start"] for s in segs])}
        lines.append(f"# {model}: base {len(base)} notas (puerta + span); notas > {CAP}: {sum(n['pitch'] > CAP for n in base)}; "
                     f"amp p25 {ctx['amp25']:.3f}; mediana MIDI {ctx['pmed']:.0f}")
        b = scores(ref, base)
        lines.append(f"{model}\tbase\t{b['n']}\t{b['P']:.3f}\t{b['R']:.3f}\t{b['F']:.3f}\t{b['pcF']:.3f}\t0")
        for name, fn in STEPS:  # cada paso solo
            out = fn(base, ctx)
            s = scores(ref, out)
            lines.append(f"{model}\tsolo {name}\t{s['n']}\t{s['P']:.3f}\t{s['R']:.3f}\t{s['F']:.3f}\t{s['pcF']:.3f}\t{len(base) - len(out)}")
        cur = base
        for name, fn in STEPS:  # acumulado
            out = fn(cur, ctx)
            s = scores(ref, out)
            lines.append(f"{model}\tacum. hasta {name}\t{s['n']}\t{s['P']:.3f}\t{s['R']:.3f}\t{s['F']:.3f}\t{s['pcF']:.3f}\t{len(cur) - len(out)}")
            cur = out
        (d / f"guitar_lead_{model}_clean.json").write_text(json.dumps({"notes": cur, "infer_s": 0.0, "info": {}}))
        # CHECK_ recortado a 155–186 s
        a, z = int(CLIP[0] * R.SR), int(CLIP[1] * R.SR)
        clip = [dict(n, onset=n["onset"] - CLIP[0], offset=n["offset"] - CLIP[0]) for n in cur
                if CLIP[0] <= n["onset"] < CLIP[1]]
        x = R.synth(clip, z - a)
        ys = y[a:z] / (np.abs(y[a:z]).max() + 1e-9) * 0.8
        R.sf.write(str(d / f"CHECK_{tag}_lead_{model}_clean_estereo.wav"), np.stack([ys, x], 1), R.SR, subtype="PCM_16")
    (R.OUT / "lead_clean_metrics.tsv").write_text("\n".join(lines) + "\n")
    print(R.OUT / "lead_clean_metrics.tsv")


if __name__ == "__main__":
    main()
