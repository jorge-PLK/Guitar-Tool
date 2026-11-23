# P9 7g: tabla de fps real del WebView en Flutter (Windows). Uso: python3 -I pc-wvfps-table.py <dir con wvfps-*.json y wvfps-load.txt>
# Sin umbrales: solo numeros. El detector muestrea a ~50-60 capturas/s: "distintas/capt" es el techo observable.
import json
import os
import sys

d = sys.argv[1]
load = {}
p = os.path.join(d, "wvfps-load.txt")
if os.path.exists(p):
    for line in open(p):
        w = line.split()
        if len(w) >= 3:
            load.setdefault(w[0], []).append(w[1] + " " + w[2])
print("%-24s %-15s %6s %6s %7s %7s %6s %9s %11s %9s %7s %6s %10s" % (
    "pasada", "carga/escala", "capt", "capt/s", "dist/s", "min1s", "dist/c", "paron ms", "partidas", "sinbarra", "rafFps", "rafGap", "dpiScale"))
for f in sorted(os.listdir(d)):
    if not (f.startswith("wvfps-") and f.endswith(".det.json")):
        continue
    name = f[: -len(".det.json")]
    det = json.load(open(os.path.join(d, f)))
    rep = {}
    fp = os.path.join(d, name + ".json")
    if os.path.exists(fp):
        rep = json.load(open(fp))
    s = det.get("series", {})
    print("%-24s %-15s %6s %6s %7s %7s %6s %9s %11s %9s %7s %6s %10s" % (
        name, ",".join(load.get(name, ["?"])), det["captures"], det["capturesPerSecond"],
        s.get("distinctPerSecMean"), s.get("distinctPerSecMin"), s.get("distinctRatio"), s.get("longestStallMs"),
        "%d (%.2f%%)" % (det["tornCaptures"], det["tornPercent"]), det["noBarCaptures"],
        "%.1f" % rep["rafFps"] if "rafFps" in rep else "-", "%.0f" % rep["rafMaxGapMs"] if "rafMaxGapMs" in rep else "-",
        "%s/%s" % (det.get("dpiScale"), rep.get("devicePixelRatio"))))
