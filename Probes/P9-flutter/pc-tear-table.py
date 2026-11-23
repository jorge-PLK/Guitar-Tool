# P9 7l: tabla de las medidas de desgarro. Uso: python3 -I pc-tear-table.py <dir con tear-*.json y tear-load.txt>
import json
import os
import sys

d = sys.argv[1]
load = {}
if os.path.exists(os.path.join(d, "tear-load.txt")):
    for line in open(os.path.join(d, "tear-load.txt")):
        p = line.split()
        if len(p) == 2:
            load.setdefault(p[0], []).append(p[1])
rows = []
for f in sorted(os.listdir(d)):
    if not (f.startswith("tear-") and f.endswith("-det.json")):
        continue
    tag = f[: -len("-det.json")]
    det = json.load(open(os.path.join(d, f)))
    fr = {}
    fp = os.path.join(d, tag + ".json")
    if os.path.exists(fp):
        fr = json.load(open(fp))
    c = fr.get("counts", {})
    cap = det["captures"]
    rows.append((
        tag, ",".join(load.get(tag, ["?"])) + "%", cap, det["capturesPerSecond"], det["noBarCaptures"],
        "%d (%.3f%%)" % (det["tornCaptures"], det["tornPercent"]),
        "%s/%s" % (c.get("produced"), c.get("distinctDelivered")), c.get("discarded"),
        fr.get("ring", {}).get("flushes"), fr.get("watchdogMaxMs"),
        "%s/%s/%s" % ((fr.get("gpuWait") or {}).get("meanUs"), (fr.get("gpuWait") or {}).get("maxUs"), (fr.get("gpuWait") or {}).get("waitTimeouts")),
    ))
hdr = ("modo", "carga", "capturas", "cap/s", "sinbarra", "partidas", "prod/dist", "descartes", "flushes", "vigilante_ms", "espera_us(media/max/timeouts)")
print(" | ".join(hdr))
for r in rows:
    print(" | ".join(str(x) for x in r))
