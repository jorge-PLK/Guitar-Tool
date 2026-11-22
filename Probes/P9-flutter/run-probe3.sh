#!/bin/bash
# P9 prueba 3 (fotogramas): textura externa vs BGRA por FFI, macOS.
# Uso: run-probe3.sh [texture|bgra] [720|1080] [segundos=60]   una ejecución
#      run-probe3.sh all [segundos=60]                          las 4 en serie (falla rápido)
#      SKIP_BUILD=1 ...                                         no recompila
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
P9="$ROOT/Probes/P9-flutter"
RUN="$ROOT/Temp/p9-flutter/run"
OUT="$ROOT/Temp/p9-flutter"
LOGS="$ROOT/Temp/logs"
APP="$P9/app/build/macos/Build/Products/Release/tf_probe.app"
DYLIB="$P9/AppCoreFFI/.build/release/libAppCoreFFI.dylib"
mkdir -p "$LOGS" "$OUT" "$RUN/projects" "$RUN/support"

build() {
  [ "${SKIP_BUILD:-0}" = "1" ] && return 0
  swift build --package-path "$P9/AppCoreFFI" -c release >"$LOGS/p9-p3-swift.log" 2>&1 || { echo "swift build falló: $LOGS/p9-p3-swift.log"; exit 1; }
  (cd "$P9/app" && fvm flutter build macos --release >"$LOGS/p9-p3-flutter.log" 2>&1) || { echo "flutter build falló: $LOGS/p9-p3-flutter.log"; exit 1; }
}

summary() { # informe ps
python3 -I - "$1" "$2" <<'EOF'
import json, sys
r = json.load(open(sys.argv[1]))
ps = []
try:
    for l in open(sys.argv[2]):
        p = l.split()
        if len(p) == 2: ps.append((float(p[0]), int(p[1]) // 1024))
except OSError:
    pass
c = r.get("counts", {}); ft = r.get("frameTiming", {}); cpu = r.get("cpu", {}); rss = r.get("rssMb", {})
b = r.get("bgra"); g = lambda d, k: (d or {}).get(k)
tag = "%s %sp" % (r.get("mode"), r.get("size"))
print("%s | prod %s pres %s desc %s hueco %s | CPU %s%% (ps %s%%) | umbral: %s" % (tag, c.get("produced"), c.get("presented"), c.get("discarded"), c.get("maxSeqGap"), cpu.get("percentOfCoreWindow"), round(sum(x[0] for x in ps) / len(ps), 1) if ps else "-", "PASA" if not r.get("failed") else r.get("failed")))
print("  build p99/max %s/%s raster p99/max %s/%s | >16.7ms %s de %s | RSS %s/%s/%s MB | vigilante %s ms" % (g(ft.get("buildMs"), "p99"), g(ft.get("buildMs"), "max"), g(ft.get("rasterMs"), "p99"), g(ft.get("rasterMs"), "max"), ft.get("over16_7ms"), ft.get("frames"), rss.get("5s"), rss.get("30s"), rss.get("60s"), r.get("watchdogMaxMs")))
print("  generador %s us/fot%s" % (r.get("generatorCostUs"), (" | copia p50/p99 %s/%s ms, decode p50/p99 %s/%s ms" % (g(b["copyMs"], "median"), g(b["copyMs"], "p99"), g(b["decodeMs"], "median"), g(b["decodeMs"], "p99"))) if b else ""))
sys.exit(1 if r.get("failed") else 0)
EOF
}

run_one() { # modo tamaño segundos -> 0 pasa, 1 umbral, 2 sin informe, 3 error
  local mode="$1" size="$2" secs="$3"
  local report="$OUT/p3-$mode-$size.json" ps="$OUT/p3-$mode-$size.ps"
  rm -f "$report" "$ps"
  rm -rf "$RUN/support" && mkdir -p "$RUN/support"
  (
    for _ in $(seq 1 40); do pgrep -f 'MacOS/tf_probe' >/dev/null && break; sleep 0.5; done
    PID=$(pgrep -f 'MacOS/tf_probe' | head -1)
    while [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; do
      ps -o %cpu=,rss= -p "$PID" >>"$ps"
      sleep 5
    done
  ) &
  local sampler=$!
  open -g -W -n "$APP" --args --probe frames --mode "$mode" --size "$size" --seconds "$secs" \
    --core-lib "$DYLIB" --projects-folder "$RUN/projects" --support-dir "$RUN/support" --report "$report"
  wait "$sampler" 2>/dev/null
  if [ ! -f "$report" ]; then echo "SIN INFORME: $mode $size"; return 2; fi
  summary "$report" "$ps"
}

left() { local l; l=$(pgrep -fl 'MacOS/tf_probe' | head -3); [ -n "$l" ] && echo "procesos restantes: $l"; }

A1="${1:-all}"
if [ "$A1" = "all" ]; then
  SECS="${2:-60}"
  build
  run_one texture 720 "$SECS"; rc=$?
  if [ $rc -ne 0 ]; then
    echo "texture 720 no pasa (rc=$rc): se para; dato de respaldo bgra 720"
    SKIP_BUILD=1 run_one bgra 720 "$SECS"; left; exit 1
  fi
  run_one texture 1080 "$SECS"; r2=$?
  run_one bgra 720 "$SECS"; r3=$?
  run_one bgra 1080 "$SECS"; r4=$?
  left
  [ $((r2 + r3 + r4)) -eq 0 ] && exit 0 || exit 1
else
  build
  run_one "$A1" "${2:-720}" "${3:-60}"; rc=$?
  left; exit $rc
fi
