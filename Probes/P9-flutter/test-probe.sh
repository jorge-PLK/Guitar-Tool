#!/bin/bash
# Paso FlutterApp de Tools/test.sh (prueba P9 6): analyze + tests, salida <= 12 líneas.
# Salida: 0 verde, 1 fallos de test o avisos de analyze, 2 error de compilación o nada que probar.
# Uso: test-probe.sh [ruta-de-test-o-filtro...]   (el log completo va a Temp/logs/p9-flutter-test.log)
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APPDIR="$ROOT/Probes/P9-flutter/app"
LOGS="$ROOT/Temp/logs"
LOG="$LOGS/p9-flutter-test.log"
mkdir -p "$LOGS"
cd "$APPDIR" || exit 2

{ echo "== flutter analyze"; fvm flutter analyze --no-pub; echo "analyze-exit=$?"; } >"$LOG" 2>&1
JSON="$LOGS/p9-flutter-test.json"
fvm flutter test --reporter=json "$@" >"$JSON" 2>"$LOGS/p9-flutter-test.err"
{ echo "== flutter test (json en $JSON)"; cat "$LOGS/p9-flutter-test.err"; } >>"$LOG"

python3 -I - "$LOG" "$JSON" "$LOGS/p9-flutter-test.err" <<'PY'
import json, re, sys
log, jpath, errpath = sys.argv[1:4]
out = []
# analyze
issues = []
for l in open(log, errors="replace"):
    if l.startswith("== flutter test"):
        break
    m = re.match(r"\s+(info|warning|error) • (.*) • (\S+?:\d+):\d+ • ", l)
    if m:
        issues.append(f"analyze {m[1]} {m[3]}: {m[2]}")
# tests
names, urls, lines = {}, {}, {}
passed = failed = skipped = 0
loadfail = []
fails = []
for raw in open(jpath, errors="replace"):
    try:
        e = json.loads(raw)
    except ValueError:
        continue
    t = e.get("type")
    if t == "testStart":
        n = e["test"]
        names[n["id"]] = n["name"]
        lines[n["id"]] = (n.get("url") or "", n.get("line"))
    elif t == "error":
        tid = e["testID"]
        msg = " ".join(str(e["error"]).split())[:110]
        st = e.get("stackTrace", "")
        m = re.search(r"^(test/\S+?\.dart)[: ](\d+):\d+", st, re.M)
        if m:
            loc = f"{m[1]}:{m[2]}"
        else:
            u, ln = lines.get(tid, ("", None))
            loc = f"{u.split('/')[-1]}:{ln}"
        if names.get(tid, "").startswith("loading "):
            loadfail.append(f"{names[tid][8:].split('/test/')[-1]}: {msg}")
        else:
            fails.append(f"{loc} {msg}")
    elif t == "testDone" and not e.get("hidden"):
        if e.get("skipped"):
            skipped += 1
        elif e["result"] == "success":
            passed += 1
        else:
            failed += 1
total = passed + failed + skipped
code = 0
if loadfail or total == 0 and not fails:
    code = 2
elif failed or issues:
    code = 1
out.append(f"analyze: {len(issues)} avisos" if issues else "analyze: 0 avisos")
out += issues[:3]
out.append(f"tests: {passed} pasados, {failed} fallados, {skipped} saltados")
extra = [f"COMPILACIÓN {x}" for x in loadfail] or ([] if total else ["no hay tests que ejecutar"])
if not loadfail and total == 0:
    pass
for l in (extra + [f"FALLO {x}" for x in fails]):
    if len(out) < 11:
        out.append(l)
hidden = len(issues[3:]) + len(extra) + len(fails) - (len(out) - 2 - min(3, len(issues)))
if hidden > 0:
    out.append(f"... +{hidden} más en el log")
out.append(f"log: {log}")
print("\n".join(out[:12]))
sys.exit(code)
PY
