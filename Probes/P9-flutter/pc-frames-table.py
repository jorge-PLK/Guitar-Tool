"""Tabla de la prueba 7 (frames) de P9 en el PC. Uso: python3 -I pc-frames-table.py <carpeta con p3-*.json>"""
import json
import os
import sys

d = sys.argv[1]
print("combinacion  prod/dist  desc dup  cpu%  rss5/30/60  wd  prod p99/max  pet p99/max")
for tag in ["gpu-720", "gpu-1080", "pixel-720", "pixel-1080", "bgra-720", "bgra-1080", "gpu-720-precise", "pixel-720-precise"]:
    p = os.path.join(d, "p3-%s.json" % tag)
    if not os.path.exists(p):
        print("%-17s sin informe" % tag)
        continue
    try:
        r = json.load(open(p))
    except Exception as e:
        print("%-17s ilegible (%s)" % (tag, e))
        continue
    c = r.get("counts", {})
    m = r.get("rssMb", {})
    pi, fi = r.get("producerIntervalMs", {}), r.get("fetchIntervalMs", {})
    print("%-17s %s/%s %s %s %s %s/%s/%s %s %s/%s %s/%s" % (
        tag, c.get("produced"), c.get("distinctDelivered"), c.get("discarded"), c.get("duplicateCopies"),
        r.get("cpu", {}).get("percentOfCoreWindow"), m.get("5s"), m.get("30s"), m.get("60s"), r.get("watchdogMaxMs"),
        pi.get("p99"), pi.get("max"), fi.get("p99"), fi.get("max")))
