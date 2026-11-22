#!/bin/bash
# P9 prueba 2: FFI e hilos (lado Dart). Uso: run-probe2.sh [listener|port] [ffi|ffi-study]
set -u
SINK="${1:-listener}"
PROBE="${2:-ffi}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
P9="$ROOT/Probes/P9-flutter"
RUN="$ROOT/Temp/p9-flutter/run"
LOGS="$ROOT/Temp/logs"
APP="$P9/app/build/macos/Build/Products/Release/tf_probe.app"
DYLIB="$P9/AppCoreFFI/.build/release/libAppCoreFFI.dylib"
mkdir -p "$LOGS" "$ROOT/Temp/p9-flutter" "$RUN/projects" "$RUN/support"

swift build --package-path "$P9/AppCoreFFI" -c release >"$LOGS/p9-p2-swift.log" 2>&1 || { echo "swift build falló: $LOGS/p9-p2-swift.log"; exit 1; }
(cd "$P9/app" && fvm flutter build macos --release >"$LOGS/p9-p2-flutter.log" 2>&1) || { echo "flutter build falló: $LOGS/p9-p2-flutter.log"; exit 1; }

if [ "$PROBE" = "ffi-study" ]; then PF="$RUN/projects-study"; else PF="$RUN/projects"; fi
# Soporte siempre vacío (sin Models/) y proyectos limpios entre ejecuciones.
rm -rf "$RUN/support" && mkdir -p "$RUN/support"
[ "$PROBE" = "ffi" ] && rm -rf "$RUN/projects" && mkdir -p "$RUN/projects"

N=1
while [ -e "$ROOT/Temp/p9-flutter/p2-$SINK-$PROBE-$N.json" ]; do N=$((N+1)); done
REPORT="$ROOT/Temp/p9-flutter/p2-$SINK-$PROBE-$N.json"

START=$(date +%s)
open -g -W -n "$APP" --args --probe "$PROBE" --sink "$SINK" --core-lib "$DYLIB" \
  --projects-folder "$PF" --support-dir "$RUN/support" --wav "$RUN/in.wav" --report "$REPORT"
END=$(date +%s)

sleep 1
LEFT=$(pgrep -fl 'tf_probe|AppCoreFFI' | head -5)
if [ -z "$LEFT" ]; then echo "procesos restantes: ninguno"; else echo "procesos restantes: $LEFT"; fi
echo "informe: $REPORT ($((END-START)) s)"
if [ ! -f "$REPORT" ]; then echo "SIN INFORME"; exit 2; fi
python3 -I - "$REPORT" <<'EOF'
import json, sys
r = json.load(open(sys.argv[1]))
g = lambda *k: __import__('functools').reduce(lambda d, x: d.get(x) if isinstance(d, dict) else None, k, r)
print("pthread_main_np:", r.get("a_pthread_main_np"), "| smoke:", r.get("b_smoke"))
c = r.get("c_roundtrip") or {}
print("rt 4000 ms:", c.get("first4000_ms"), "errores:", c.get("errors"))
print("rss:", c.get("rssMb"), "live:", c.get("liveBuffers"))
print("ui:", r.get("d_uiBlock"))
e = r.get("e_nativeToDart") or {}
for k in ("free_60hz", "busy_60hz", "burst_5000"):
    if k in e:
        v = e[k]
        print(k, "lat us:", v["latencyUs"], "lost:", v["lost"], "ooo:", v["outOfOrder"], v.get("jitterRmsVs16_67Ms"), v.get("usPerMessage"))
print("decode:", r.get("f_decode"))
print("bg:", (r.get("g_background") or {}).get("sequence"))
print("shutdown:", r.get("h_shutdown"))
for k in ("STOPPED_threshold", "exception", "study_open"):
    if k in r: print(k, str(r[k])[:300])
EOF
