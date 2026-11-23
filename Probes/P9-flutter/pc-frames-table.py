"""Tabla de la prueba 7 (frames) de P9 en el PC. Uso: python3 -I pc-frames-table.py <carpeta con p3-*.json>"""
import json
import os
import sys

d = sys.argv[1]
print("combinacion  prod/pres  desc  cpu%   rss5/30/60        wd_max  fallos")
for tag in ["gpu-720", "gpu-1080", "pixel-720", "pixel-1080", "bgra-720", "bgra-1080", "solid-gpu", "solid-pixel"]:
    p = os.path.join(d, "p3-%s.json" % tag)
    if not os.path.exists(p):
        print("%-12s sin informe" % tag)
        continue
    try:
        r = json.load(open(p))
    except Exception as e:
        print("%-12s informe ilegible (%s)" % (tag, e))
        continue
    c = r.get("counts", {})
    cpu = r.get("cpu", {}).get("percentOfCoreWindow")
    m = r.get("rssMb", {})
    print("%-12s %s/%s  %s  %s  %s/%s/%s  %s  %s" % (
        tag, c.get("produced"), c.get("presented"), c.get("discarded"), cpu,
        m.get("5s"), m.get("30s"), m.get("60s"), r.get("watchdogMaxMs"), ",".join(r.get("failed", [])) or "-"))
