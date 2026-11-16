"""Referencia de `output_to_notes_polyphonic` de basic-pitch 0.4.0 sobre posteriorgramas sintéticos.

Sirve para probar el port de Swift (`BasicPitchNotes`) sin el modelo: carga del `note_creation.py` original solo
las funciones del paso posteriorgramas → notas (por AST, sin importar librosa ni pretty_midi) y las ejecuta con
los parámetros por defecto de `basic_pitch.inference.predict` (onset 0.5, frame 0.3, 127.70 ms → 11 fotogramas,
infer_onsets y melodia_trick activados, energy_tol 11).

Uso (numpy + scipy; `note_creation.py` sale de la rueda basic_pitch-0.4.0-py2.py3-none-any.whl de PyPI):
    Tools/py/.venv/bin/python -I make_reference.py <ruta/a/basic_pitch/note_creation.py> <carpeta de salida>

Salida por caso `<nombre>`: `<nombre>_note.f32` y `<nombre>_onset.f32` (float32 LE, [fotograma][88]) y
`reference.json` con fotogramas, y por nota [inicio, fin, nota MIDI, amplitud, inicio_s, fin_s].
"""
import ast
import json
import pathlib
import sys
import types
from typing import List, Optional, Tuple

import numpy as np
import scipy.signal

FFT_HOP = 256
AUDIO_SAMPLE_RATE = 22050
AUDIO_N_SAMPLES = AUDIO_SAMPLE_RATE * 2 - FFT_HOP
ANNOT_N_FRAMES = (AUDIO_SAMPLE_RATE // FFT_HOP) * 2
WANTED = {"get_infered_onsets", "constrain_frequency", "model_frames_to_time", "output_to_notes_polyphonic"}


def load_functions(path):
    tree = ast.parse(pathlib.Path(path).read_text())
    body = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in WANTED]
    assert {n.name for n in body} == WANTED, "faltan funciones en note_creation.py"
    librosa = types.SimpleNamespace(core=types.SimpleNamespace(
        frames_to_time=lambda f, sr, hop_length: np.asarray(f) * hop_length / float(sr)))
    ns = dict(np=np, scipy=scipy, librosa=librosa, Optional=Optional, Tuple=Tuple, List=List,
              MIDI_OFFSET=21, MAX_FREQ_IDX=87, FFT_HOP=FFT_HOP, AUDIO_SAMPLE_RATE=AUDIO_SAMPLE_RATE,
              AUDIO_N_SAMPLES=AUDIO_N_SAMPLES, ANNOT_N_FRAMES=ANNOT_N_FRAMES)
    exec(compile(ast.Module(body=body, type_ignores=[]), path, "exec"), ns)
    return ns


def synthetic(rng, n_frames, n_notes):
    """Notas con huecos bajo el umbral, onsets por encima y por debajo de 0.5, energía sin onset y ruido."""
    note = rng.uniform(0.0, 0.18, (n_frames, 88)).astype(np.float32)
    onset = rng.uniform(0.0, 0.25, (n_frames, 88)).astype(np.float32)
    for _ in range(n_notes):
        p = int(rng.integers(18, 70))
        s = int(rng.integers(0, n_frames - 4))
        length = int(rng.integers(4, 70))
        e = min(n_frames, s + length)
        note[s:e, p] = rng.uniform(0.35, 0.95, e - s)
        if rng.random() < 0.3 and e - s > 8:      # caída breve bajo el umbral de frame
            d = s + int(rng.integers(2, e - s - 3))
            note[d:d + int(rng.integers(1, 14)), p] = rng.uniform(0.0, 0.29)
        if rng.random() < 0.4:                    # vecino arrastrado (lo borra la nota)
            note[s:e, min(87, p + 1)] = rng.uniform(0.2, 0.5, e - s)
        if rng.random() < 0.8:                    # onset (algunos < 0.5: esos los recoge melodia)
            onset[s, p] = rng.uniform(0.3, 0.98)
            if s > 0:
                onset[s - 1, p] = onset[s, p] * 0.5
    return note, onset


def cases(rng):
    yield "random_a", *synthetic(rng, 420, 70)
    yield "random_b", *synthetic(rng, 380, 55)
    yield "silence", np.zeros((200, 88), np.float32), np.zeros((200, 88), np.float32)
    # Energía constante sin onsets desde el fotograma 0: frame_diff es todo 0 → NaN en Python; solo melodia,
    # con empate en el argmax (gana el primero en orden C).
    c = np.zeros((150, 88), np.float32)
    c[:, 30] = 0.5
    c[:, 52] = 0.5
    yield "constant", c, np.zeros((150, 88), np.float32)


def main():
    fn = load_functions(sys.argv[1])
    out = pathlib.Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(20261115)
    ref = {"onset_thresh": 0.5, "frame_thresh": 0.3, "min_note_len": 11, "cases": {}}
    min_len = int(np.round(127.70 / 1000 * (AUDIO_SAMPLE_RATE / FFT_HOP)))
    assert min_len == 11
    for name, note, onset in cases(rng):
        note.astype("<f4").tofile(out / f"{name}_note.f32")
        onset.astype("<f4").tofile(out / f"{name}_onset.f32")
        with np.errstate(divide="ignore", invalid="ignore"):
            events = fn["output_to_notes_polyphonic"](note.copy(), onset.copy(), onset_thresh=0.5, frame_thresh=0.3,
                                                      min_note_len=min_len, infer_onsets=True, max_freq=None,
                                                      min_freq=None, melodia_trick=True)
        times = fn["model_frames_to_time"](note.shape[0])
        ref["cases"][name] = {
            "frames": int(note.shape[0]),
            "notes": [[int(s), int(e), int(p), float(a), float(times[s]), float(times[e])] for s, e, p, a in events],
        }
        print(name, note.shape[0], "fotogramas,", len(events), "notas")
    (out / "reference.json").write_text(json.dumps(ref, indent=1))


if __name__ == "__main__":
    main()
