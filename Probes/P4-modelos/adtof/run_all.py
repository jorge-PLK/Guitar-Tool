"""Repite la prueba ADTOF entera con un comando:
    Tools/py/.venv/bin/python Probes/P4-modelos/adtof/run_all.py [--vias torch coreml_fp32n] [--convert]

Pasos (cada proceso pesado bajo common/guard.py a 10 GB, uno a la vez, un proceso por tema):
1. reference.py: golpes de referencia desde las pistas sueltas (out/ref/).
2. (--convert) convert.py: Core ML a out/conv/ (FP32 con GRU nativa = vía coreml_fp32n, CPU_ONLY).
3. run.py por vía y tema: activaciones, golpes, MIDI y tiempos.
4. evaluate.py: out/results/drum_table.{csv,json}.
5. listen.py: WAV de escucha (out/listen/) con la vía elegida (la última de --vias).
Requisito fuera del venv: clon del puerto en out/repo (commit en ad_common.REPO_COMMIT).
"""
import argparse
import subprocess
import sys

import ad_common as C

ap = argparse.ArgumentParser()
ap.add_argument("--vias", nargs="*", default=["torch", "coreml_fp32n"])
ap.add_argument("--convert", action="store_true")
a = ap.parse_args()
log = C.setup_log("run_all")
PY = sys.executable


def guarded(tag, args):
    g = C.OUT / "logs" / f"guard_{tag}.log"
    g.unlink(missing_ok=True)
    r = subprocess.run([PY, str(C.GUARD), "--limit-gb", "10", "--log", str(g), "--", PY, *args],
                       capture_output=True, text=True)
    log.info("%s rc=%d\n%s\n%s", tag, r.returncode, r.stdout[-2000:], r.stderr[-3000:])
    if r.returncode != 0:
        sys.exit(f"{tag} falló (rc={r.returncode}); ver out/logs/run_all.log")


guarded("reference", [str(C.HERE / "reference.py")])
if a.convert:
    guarded("convert_fp32n", [str(C.HERE / "convert.py"), "--prec", "fp32", "--gru", "native"])
for via in a.vias:
    for song in C.SONGS:
        guarded(f"{via}_{song}", [str(C.HERE / "run.py"), "--song", song, "--via", via])
r = subprocess.run([PY, str(C.HERE / "evaluate.py"), "--vias", *a.vias], capture_output=True, text=True)
log.info("evaluate\n%s\n%s", r.stdout, r.stderr[-3000:])
print(r.stdout.strip())
r = subprocess.run([PY, str(C.HERE / "listen.py"), "--via", a.vias[-1]], capture_output=True, text=True)
log.info("listen\n%s\n%s", r.stdout, r.stderr[-3000:])
C.progress("run_all", "T1-T3", "+".join(a.vias), "tabla en out/results/drum_table.csv")
