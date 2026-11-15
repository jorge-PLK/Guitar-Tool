"""Vigilante de memoria para procesos pesados de P4.
Uso: guard.py [--limit-gb 10] [--log out/guard.log] [--interval 0.5] -- <comando> [args...]
Lanza el comando en su propio grupo de procesos, sondea la memoria del proceso y de todos sus hijos
(máximo entre RSS y phys_footprint de macOS, que incluye memoria Metal/ANE atribuida) y, si la suma
pasa del límite, mata el grupo entero con SIGKILL. Registra el pico y el motivo de salida en el log.
Código de salida: el del comando; 137 si lo mató el vigilante."""
import argparse
import ctypes
import logging
import os
import signal
import subprocess
import sys
import time

import psutil

ap = argparse.ArgumentParser()
ap.add_argument("--limit-gb", type=float, default=10.0)
ap.add_argument("--log", default="guard.log")
ap.add_argument("--interval", type=float, default=0.5)
ap.add_argument("cmd", nargs=argparse.REMAINDER)
a = ap.parse_args()
cmd = a.cmd[1:] if a.cmd and a.cmd[0] == "--" else a.cmd
if not cmd:
    sys.exit("falta el comando tras --")

log = logging.getLogger("guard")
log.setLevel(logging.INFO)
h = logging.FileHandler(a.log)
h.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
log.addHandler(h)

_lib = ctypes.CDLL("/usr/lib/libproc.dylib") if sys.platform == "darwin" else None


class _Ru(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [(f"f{i}", ctypes.c_uint64) for i in range(35)]


def mem_of(p: psutil.Process) -> int:
    rss = p.memory_info().rss
    if _lib is not None:
        b = _Ru()
        if _lib.proc_pid_rusage(p.pid, 4, ctypes.byref(b)) == 0:
            return max(rss, int(b.f7))
    return rss


limit = int(a.limit_gb * 1e9)
t0 = time.time()
proc = subprocess.Popen(cmd, start_new_session=True)
root = psutil.Process(proc.pid)
log.info("inicio pid %d límite %.1f GB: %s", proc.pid, a.limit_gb, " ".join(cmd))
peak, killed = 0, False
while proc.poll() is None:
    try:
        procs = [root] + root.children(recursive=True)
        total = 0
        for p in procs:
            try:
                total += mem_of(p)
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
    except psutil.NoSuchProcess:
        break
    peak = max(peak, total)
    if total > limit:
        killed = True
        log.error("LÍMITE SUPERADO: %.2f GB > %.1f GB -> SIGKILL al grupo %d", total / 1e9, a.limit_gb, proc.pid)
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        break
    time.sleep(a.interval)
rc = proc.wait()
rc = 137 if killed else rc
log.info("fin rc=%s pico %.2f GB en %.0f s%s", rc, peak / 1e9, time.time() - t0, " (MATADO)" if killed else "")
print(f"guard: rc={rc} pico {peak / 1e9:.2f} GB{' MATADO por límite' if killed else ''}")
sys.exit(rc)
