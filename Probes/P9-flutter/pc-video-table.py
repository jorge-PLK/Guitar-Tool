#!/usr/bin/env python3
# P9 7h: tabla / veredicto de los informes traidos por `pc.sh video` (Temp/p9-flutter/pc/vid-fvp-*.json de vp_fvp y
# vid-native-*.json de tf_probe --probe video con `--engine native`).
# Uso: pc-video-table.py table <dir> <prefijo> [sufijo]   |   pc-video-table.py verdict <json>   (exit 0 pasa, 1 incumple)
# Umbrales (spec P9, prueba 7h): error A/V mediana y p95 <= 16,7 ms (medio fotograma a 30 fps); recuperacion tras salto < 300 ms.
import glob, json, os, sys

E_MAX_MS = 16.7
RECOVER_MAX_MS = 300


def load(p):
    try:
        return json.load(open(p))
    except Exception:
        return None


def e_bad(e):
    """Incumple si |mediana|, |p95| o |p05| > E_MAX_MS (el error puede ser negativo: fotograma adelantado).
    Sin p05 (informes anteriores a su alta) solo mediana y p95; min/max son muestras sueltas y no cuentan."""
    if e.get("median") is None or e.get("p95") is None:
        return True
    edge = abs(e["p95"])
    if e.get("p05") is not None:
        edge = max(edge, abs(e["p05"]))
    return abs(e["median"]) > E_MAX_MS or edge > E_MAX_MS


def checks(r):
    """Lista de incumplimientos."""
    bad = []
    if r is None:
        return ["sin informe"]
    if r.get("error"):
        bad.append("error: %s" % str(r["error"])[:80])
    # Candidata nativa (probe5_video.dart): fallos duros de su lista `failed`; los de umbral se reevaluan aqui abajo.
    if r.get("candidate") == "native":
        for f in r.get("failed") or []:
            if not str(f).startswith(("fuera=", "fueraBucle=", "seek@", "vuelta=")):
                bad.append(str(f)[:80])
    res = r.get("result") or {}
    c = r.get("case")
    if c == "steady" and not any(k.startswith("rate_") for k in res):
        bad.append("sin regimen")
    if c == "steady":
        for k, v in res.items():
            if k.startswith("rate_"):
                e = v["e_ms"]
                if e_bad(e):
                    bad.append("%s e med/p95 %s/%s (p05 %s)" % (k, e["median"], e["p95"], e.get("p05", e.get("min"))))
    elif c == "seek":
        for j in res.get("jumps", []):
            if j.get("stayOkMs") is None or j["stayOkMs"] > RECOVER_MAX_MS:
                bad.append("salto %s stay %s ms" % (j["target"], j.get("stayOkMs")))
    elif c == "loop":
        for j in res.get("recovery", []):
            if j.get("stayOkMs") is None or j["stayOkMs"] > RECOVER_MAX_MS:
                bad.append("vuelta stay %s ms" % j.get("stayOkMs"))
        e = (res.get("inLoop") or {}).get("e_ms") or {}
        if e_bad(e):
            bad.append("en bucle e med/p95 %s/%s (p05 %s)" % (e.get("median"), e.get("p95"), e.get("p05", e.get("min"))))
    return bad


def row(name, r, load_pct):
    if r is None:
        return ["%-34s SIN INFORME" % name]
    res = r.get("result") or {}
    c = r.get("case")
    o = r.get("open") or {}
    cpu = None
    if r.get("wallS"):
        cpu = round(100 * (r.get("cpuProcessS") or 0) / r["wallS"], 1)
    dec = r.get("activeDecoder")
    if r.get("candidate") == "native":  # informe de probe5_video.dart: info del lector MF y cpu.percentOfCore
        info = r.get("info") or {}
        cpu = (r.get("cpu") or {}).get("percentOfCore")
        dec = "%s hw=%s" % (info.get("decoder"), info.get("hardwareDecode"))
        o = {"textureSize": [info.get("width"), info.get("height")], "codec": info.get("codec"),
             "rotation": "%s (mf %s, q %s)" % (info.get("rotationDegrees"), info.get("mfRotation"), r.get("quarterTurns"))}
    tail = "dec=%s CPU %s%% vig %s ms carga %s%%" % (dec, cpu, r.get("watchdogMaxMs"), load_pct)
    out = []
    if c == "steady":
        for k, v in res.items():
            if k.startswith("rate_"):
                e = v["e_ms"]
                out.append("%-34s %s e %s/%s/%s rep %s salt %s | %s" % (name, k[5:], e["median"], e["p95"], e["max"], v["repeated"], v["skipped"], tail))
    elif c == "seek":
        out.append("%-34s saltos stay/first ms: %s | %s" % (name, " ".join("%s/%s" % (j.get("stayOkMs"), j.get("firstOkMs")) for j in res.get("jumps", [])), tail))
    elif c == "loop":
        e = (res.get("inLoop") or {}).get("e_ms") or {}
        out.append("%-34s vueltas %s bucle e %s/%s/%s | %s" % (name, " ".join("%s/%s" % (j.get("stayOkMs"), j.get("firstOkMs")) for j in res.get("recovery", [])), e.get("median"), e.get("p95"), e.get("max"), tail))
    else:
        out.append("%-34s tex %s rot %s codec %s | %s" % (name, o.get("textureSize"), o.get("rotation"), o.get("codec"), tail))
    return out or ["%-34s (sin datos)" % name]


def main():
    if sys.argv[1] == "verdict":
        bad = checks(load(sys.argv[2]))
        print("; ".join(bad) if bad else "PASA")
        sys.exit(1 if bad else 0)
    d, pre = sys.argv[2], sys.argv[3]
    loads = {}
    try:
        for l in open(os.path.join(d, "vid-load.txt")):
            p = l.split()
            if len(p) == 2:
                loads[p[0]] = p[1]
    except OSError:
        pass
    n = 0
    for p in sorted(glob.glob(os.path.join(d, pre + "*.json"))):
        name = os.path.basename(p)[:-5]
        for ln in row(name[len(pre):], load(p), loads.get(name)):
            print(ln[:230])
            n += 1
        bad = checks(load(p))
        if bad:
            print("   INCUMPLE: " + "; ".join(bad)[:200])


main()
