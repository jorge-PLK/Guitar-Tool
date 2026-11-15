# /// script
# requires-python = ">=3.12"
# dependencies = ["numpy", "scipy", "soundfile", "librosa"]
# ///
"""P6: Apple AVAudioUnitTimePitch (overlap 8 y 32) frente a Rubber Band R2/R3 en tiempo real.

Uso: uv run --python 3.12 p6.py [--synth] [clip.wav ...]
Renderiza 4 motores x 3 casos por clip, genera los ficheros ciegos, la clave, la hoja y las métricas.
Normalmente se lanza desde run.sh (compila el render de Apple y comprueba Rubber Band).
"""
import json
import random
import resource
import shutil
import subprocess
import sys
import time
from pathlib import Path

import librosa
import numpy as np
import soundfile as sf

HERE = Path(__file__).resolve().parent
OUT = HERE / "out"
APPLE_BIN = HERE / "AppleRender/.build/release/applerender"
RUBBERBAND = shutil.which("rubberband") or "/opt/homebrew/bin/rubberband"
SEED = 6  # semilla fija del barajado ciego

# Casos: nombre -> (velocidad, semitonos). Plan, P6: 50 %, 70 % y +2 st a 100 %.
CASES = {"v50": (0.5, 0.0), "v70": (0.7, 0.0), "p2": (1.0, 2.0)}
ENGINES = ["apple_o8", "apple_o32", "rb_r2", "rb_r3"]

SILENCE_DB = -60.0  # umbral para medir el tramo con señal (duración)
ONSET_HOP = 128
PITCH_SR = 22050
PYIN_RESOLUTION = 0.05  # semitonos por bin (5 cents); con 0.01 y 0.02 el Viterbi de pyin falla con la salida de Apple


def log(msg: str) -> None:
    with open(OUT / "log.txt", "a") as f:
        f.write(msg + "\n")


# ---------------------------------------------------------------- señal sintética
def make_synth(path: Path, dur: float = 10.0, sr: int = 44100) -> None:
    rng = np.random.default_rng(6)
    t = np.arange(int(dur * sr)) / sr
    # Nota A3 con vibrato de 5 Hz (+-15 cents) y armónicos; se re-ataca cada 2 s con caída exponencial.
    f0 = 220.0 * 2 ** ((15 * np.sin(2 * np.pi * 5 * t)) / 1200)
    phase = 2 * np.pi * np.cumsum(f0) / sr
    tone = sum(np.sin(k * phase) / k for k in range(1, 7))
    env = np.exp(-((t % 2.0)) * 1.2)
    env *= np.minimum(1.0, (t % 2.0) / 0.003)  # ataque de 3 ms
    sig = 0.35 * tone * env / np.max(np.abs(tone))
    # Clics (impulsos con caída de 4 ms) en los segundos .5
    clicks = np.zeros_like(t)
    for c in np.arange(0.5, dur, 1.0):
        i = int(c * sr)
        n = int(0.02 * sr)
        clicks[i:i + n] += 0.6 * rng.standard_normal(n) * np.exp(-np.arange(n) / (0.004 * sr))
    # Ráfagas de ruido de 150 ms
    noise = np.zeros_like(t)
    for c in (3.2, 7.2):
        i = int(c * sr)
        n = int(0.15 * sr)
        noise[i:i + n] += 0.25 * rng.standard_normal(n) * np.hanning(n)
    left = sig + clicks + noise
    right = 0.9 * sig + 0.8 * clicks + 0.6 * noise + 0.0 * left
    st = np.stack([left, right], axis=1)
    st = 0.8 * st / np.max(np.abs(st))
    path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(path, st.astype(np.float32), sr, subtype="PCM_16")


# ---------------------------------------------------------------- render
def render_apple(src: Path, dst: Path, rate: float, semis: float, overlap: int) -> dict:
    cmd = [str(APPLE_BIN), str(src), str(dst), "--rate", str(rate),
           "--pitch-cents", str(semis * 100), "--overlap", str(overlap)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    log(f"$ {' '.join(cmd)}\n{r.stdout}{r.stderr}")
    if r.returncode != 0:
        raise RuntimeError(f"applerender falló: {r.stderr[-300:]}")
    return {"cpu_s": json.loads(r.stdout.strip().splitlines()[-1])["cpu_s"]}


def render_rb(src: Path, dst: Path, rate: float, semis: float, engine: str) -> dict:
    cmd = [RUBBERBAND, "-q", "--realtime", "--ignore-clipping", "-2" if engine == "r2" else "-3"]
    if rate != 1.0:
        cmd += ["--tempo", str(rate)]
    if semis != 0.0:
        cmd += ["--pitch", str(semis)]
    cmd += [str(src), str(dst)]
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    r = subprocess.run(cmd, capture_output=True, text=True)
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    log(f"$ {' '.join(cmd)}\n{r.stdout}{r.stderr}")
    if r.returncode != 0:
        raise RuntimeError(f"rubberband falló: {r.stderr[-300:]}")
    cpu = (after.ru_utime - before.ru_utime) + (after.ru_stime - before.ru_stime)
    return {"cpu_s": cpu}


def render(engine: str, src: Path, dst: Path, rate: float, semis: float) -> dict:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if engine == "apple_o8":
        return render_apple(src, dst, rate, semis, 8)
    if engine == "apple_o32":
        return render_apple(src, dst, rate, semis, 32)
    return render_rb(src, dst, rate, semis, engine[3:])


# ---------------------------------------------------------------- métricas
def mono(path: Path) -> tuple[np.ndarray, int]:
    x, sr = sf.read(path, dtype="float32", always_2d=True)
    return x.mean(axis=1), sr


def signal_span(x: np.ndarray, sr: int) -> tuple[float, float]:
    """Inicio y fin (s) del tramo con señal, con umbral SILENCE_DB respecto al pico, RMS de 10 ms."""
    hop = int(0.01 * sr)
    n = len(x) // hop
    rms = np.sqrt((x[: n * hop].reshape(n, hop) ** 2).mean(axis=1)) + 1e-12
    db = 20 * np.log10(rms / (np.max(np.abs(x)) + 1e-12))
    idx = np.nonzero(db > SILENCE_DB)[0]
    if len(idx) == 0:
        return 0.0, 0.0
    return idx[0] * 0.01, (idx[-1] + 1) * 0.01


def stable_pitch_cents(x: np.ndarray, sr: int) -> tuple[float, float]:
    """Mediana (cents sobre 440 Hz) del tramo con nota estable y su desviación típica.

    Estable = fotogramas con voz de pyin dentro de +-100 cents de la mediana global.
    """
    y = librosa.resample(x, orig_sr=sr, target_sr=PITCH_SR)
    f0, voiced, _ = librosa.pyin(y, fmin=librosa.note_to_hz("C2"), fmax=librosa.note_to_hz("C6"),
                                 sr=PITCH_SR, frame_length=2048, hop_length=512, resolution=PYIN_RESOLUTION)
    f = f0[voiced & np.isfinite(f0)]
    if len(f) < 5:
        return float("nan"), float("nan")
    c = 1200 * np.log2(f / 440.0)
    med = np.median(c)
    c = c[np.abs(c - med) < 100]
    return float(np.median(c)), float(np.std(c))


def onset_stats(x: np.ndarray, sr: int) -> tuple[float, int]:
    env = librosa.onset.onset_strength(y=x, sr=sr, hop_length=ONSET_HOP)
    peaks = librosa.onset.onset_detect(onset_envelope=env, sr=sr, hop_length=ONSET_HOP, backtrack=False)
    if len(peaks) == 0:
        return 0.0, 0
    return float(np.mean(env[peaks])), int(len(peaks))


def analyse_original(src: Path) -> dict:
    x, sr = mono(src)
    s, e = signal_span(x, sr)
    pc, ps = stable_pitch_cents(x, sr)
    on, n = onset_stats(x, sr)
    return {"span": e - s, "pitch_cents": pc, "onset": on, "onsets": n}


def analyse(out: Path, orig: dict, rate: float, semis: float, cpu_s: float) -> dict:
    x, sr = mono(out)
    s, e = signal_span(x, sr)
    expected = orig["span"] / rate
    pc, ps = stable_pitch_cents(x, sr)
    on, n = onset_stats(x, sr)
    seconds = len(x) / sr
    return {
        "duration_s": e - s,
        "duration_expected_s": expected,
        "duration_error_pct": 100 * ((e - s) - expected) / expected,
        "pitch_drift_cents": pc - orig["pitch_cents"] - 100 * semis,
        "pitch_spread_cents": ps,
        "attack_pct": 100 * on / orig["onset"] if orig["onset"] else float("nan"),
        "onset_count_ratio": n / orig["onsets"] if orig["onsets"] else float("nan"),
        "cpu_s": cpu_s,
        "cpu_per_audio_s": cpu_s / seconds,
        "file_seconds": seconds,
    }


# ---------------------------------------------------------------- principal
def main() -> None:
    args = sys.argv[1:]
    OUT.mkdir(exist_ok=True)
    (OUT / "log.txt").write_text("")
    clips: list[Path] = []
    if "--synth" in args:
        args.remove("--synth")
        synth = OUT / "synth" / "synth.wav"
        make_synth(synth)
        clips.append(synth)
    clips += [Path(a).resolve() for a in args]
    if not clips:
        sys.exit("uso: p6.py [--synth] clip.wav ...")
    if not APPLE_BIN.exists():
        sys.exit(f"falta {APPLE_BIN}; usa run.sh")

    blind = OUT / "blind"
    if blind.exists():
        shutil.rmtree(blind)
    blind.mkdir(parents=True)
    raw = OUT / "render"
    key: dict[str, str] = {}
    metrics: dict = {}
    sheet = ["# P6 · Hoja de puntuación a ciegas", "",
             "Puntúa de 1 (muy malo) a 5 (indistinguible del original) cada fichero. Fíjate en: "
             "ataques blandos o con eco (pre-eco), batido o aspereza en notas sostenidas, "
             "movimiento raro de la afinación y sonido hueco o acuoso.", ""]

    for clip in clips:
        name = "".join(ch if ch.isalnum() or ch in "-" else "-" for ch in clip.stem)
        print(f"[{name}] analizando original…", flush=True)
        orig = analyse_original(clip)
        metrics[name] = {"original": orig, "cases": {}}
        sheet += [f"## {name}", ""]
        for case, (rate, semis) in CASES.items():
            order = ENGINES[:]
            random.Random(f"{SEED}:{name}:{case}").shuffle(order)
            sheet += [f"### {name} · {case}", "", "| Fichero | Puntuación (1-5) | Notas |", "|---|---|---|"]
            metrics[name]["cases"][case] = {}
            for engine in ENGINES:
                dst = raw / name / f"{case}_{engine}.wav"
                t0 = time.time()
                info = render(engine, clip, dst, rate, semis)
                m = analyse(dst, orig, rate, semis, info["cpu_s"])
                metrics[name]["cases"][case][engine] = m
                print(f"  {case} {engine}: {time.time() - t0:.1f}s", flush=True)
            for letter, engine in zip("ABCD", order):
                fname = f"{name}_{case}_{letter}.wav"
                shutil.copyfile(raw / name / f"{case}_{engine}.wav", blind / fname)
                key[fname] = engine
                sheet.append(f"| {fname} |  |  |")
            sheet.append("")

    (OUT / "key.json").write_text(json.dumps({"seed": SEED, "files": key}, indent=2))
    (OUT / "sheet.md").write_text("\n".join(sheet) + "\n")
    (OUT / "metrics.json").write_text(json.dumps(metrics, indent=2))

    print("\nclip case engine        dur_err%  drift_c  attack%  onsets  cpu/audio_s")
    for name, d in metrics.items():
        for case, engs in d["cases"].items():
            for engine, m in engs.items():
                print(f"{name[:10]:10} {case:4} {engine:10} {m['duration_error_pct']:8.2f} "
                      f"{m['pitch_drift_cents']:8.1f} {m['attack_pct']:8.1f} "
                      f"{m['onset_count_ratio']:6.2f} {m['cpu_per_audio_s']:11.4f}")
    print(f"\nSalidas en {OUT}")


if __name__ == "__main__":
    main()
