#!/bin/bash
# P9.5a prueba 5 (vídeo de tomas con reloj externo), macOS.
# Uso: run-probe5.sh fvp <steady|seek|loop|cpu|rotation|start-pts|all> [fichero]   (fichero: nombre dentro de Temp/p9-flutter/video)
#      run-probe5.sh native ...   (segunda candidata: sin implementar)
#      SKIP_BUILD=1 ...           no recompila;  REGIME_S=10 duración de cada régimen
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/Temp/p9-flutter"
VID="$OUT/video"
LOGS="$ROOT/Temp/logs"
WINID="$ROOT/Temp/flutter-probe/tools/winid"
CAND="${1:-fvp}"
CASE="${2:-all}"
ONLY="${3:-}"
mkdir -p "$LOGS" "$OUT"

if [ "$CAND" = native ]; then
  # Candidata nativa (AVPlayer en AppCoreFFI + Texture en tf_probe --probe video).
  P9="$ROOT/Probes/P9-flutter"; RUN="$OUT/run"
  NAPP="$P9/app/build/macos/Build/Products/Release/tf_probe.app"
  DYLIB="$P9/AppCoreFFI/.build/release/libAppCoreFFI.dylib"
  mkdir -p "$RUN/projects"
  if [ "${SKIP_BUILD:-0}" != "1" ]; then
    swift build --package-path "$P9/AppCoreFFI" -c release >"$LOGS/p9-p5-native-swift.log" 2>&1 || { echo "swift build falló: $LOGS/p9-p5-native-swift.log"; exit 1; }
    (cd "$P9/app" && fvm flutter build macos --release >"$LOGS/p9-p5-native.log" 2>&1) || { echo "flutter build falló: $LOGS/p9-p5-native.log"; exit 1; }
  fi
  nsummary() {
python3 -I - "$1" <<'PY'
import json, sys
r = json.load(open(sys.argv[1])); res = r.get("result") or {}; c = r.get("case")
cpu = (r.get("cpu") or {}).get("percentOfCore"); rss = r.get("rssMb") or {}
print("%s %s | CPU %s%% RSS %s/%s MB vigilante %s ms | %s" % (c, (r.get("file") or "").split("/")[-1], cpu, rss.get("5s"), rss.get("end"), r.get("watchdogMaxMs"), "PASA" if not r.get("failed") else r.get("failed")))
if r.get("exception"): print("  EXC:", r["exception"][:300])
if c == "steady":
    for k, v in res.items():
        if k.startswith("rate_"): e = v["e_ms"]; print("  %s e med/p95/p99/min/max %s/%s/%s/%s/%s fuera %s%% rep %s salt %s atrás %s ent/s %s" % (k, e["median"], e["p95"], e["p99"], e["min"], e["max"], v["outOfTolPct"], v["repeated"], v["skipped"], v["backSteps"], v["deliveriesPerSec"]))
elif c == "seek":
    print("  saltos (stay/first ms): " + " ".join("%s->%s/%s" % (j["target"], j["stayOkMs"], j["firstOkMs"]) for j in res.get("jumps", [])))
elif c == "loop":
    print("  vueltas (stay/first ms): " + " ".join("%s/%s" % (j["stayOkMs"], j["firstOkMs"]) for j in res.get("recovery", [])))
    v = res.get("inLoop", {}); print("  en bucle e_ms %s fuera %s%%" % (v.get("e_ms"), v.get("outOfTolPct")))
else:
    print("  info", json.dumps(r.get("info")), "primera entrega ms", res.get("firstDeliveryMsAfterClock"))
sys.exit(1 if r.get("failed") else 0)
PY
  }
  nrun() { # caso fichero captura_s
    local kase="$1" file="$2" shot="$3" base="${2%.*}"
    local report="$OUT/p5-native-$kase-$base.json" png="$OUT/p5-native-$kase-$base.png"
    rm -f "$report" "$png"; rm -rf "$RUN/support" && mkdir -p "$RUN/support"
    if [ "$shot" != 0 ]; then
      ( for _ in $(seq 1 40); do pgrep -f 'MacOS/tf_probe' >/dev/null && break; sleep 0.5; done
        sleep "$shot"; screencapture -x -l "$("$WINID" tf_probe)" "$png" 2>/dev/null ) &
    fi
    open -g -n -W "$NAPP" --args --probe video --case "$kase" --file "$VID/$file" --core-lib "$DYLIB" \
      --projects-folder "$RUN/projects" --support-dir "$RUN/support" --report "$report" --exit-after 80
    wait 2>/dev/null
    if [ ! -f "$report" ]; then echo "SIN INFORME: $kase $file"; return 2; fi
    nsummary "$report"
  }
  if [ "$CASE" = all ]; then
    for f in code-hevc.mov code-h264.mp4; do
      s=0; [ "$f" = code-hevc.mov ] && s=12
      nrun steady "$f" $s; nrun seek "$f" 0; nrun loop "$f" 0
    done
    nrun rotation take-hevc-rot90.mov 3; nrun rotation take-h264-rot90.mp4 3
    nrun start-pts take-hevc.mov 0
  else
    f="${ONLY:-code-hevc.mov}"; s=0; [ "$CASE" = steady ] && s=12; [ "$CASE" = rotation ] && s=3
    nrun "$CASE" "$f" $s
  fi
  l=$(pgrep -fl 'MacOS/tf_probe' | head -3); [ -n "$l" ] && echo "procesos restantes: $l"
  exit 0
fi

case "$CAND" in
  fvp) DIR="$ROOT/Probes/P9-flutter/video/vp_fvp"; BIN=vp_fvp ;;
  native) echo "candidata native: sin implementar"; exit 3 ;;
  *) echo "candidata desconocida: $CAND"; exit 3 ;;
esac
APP="$DIR/build/macos/Build/Products/Release/$BIN.app"
LOG="$LOGS/p9-p5-$CAND.log"

build() {
  [ "${SKIP_BUILD:-0}" = "1" ] && return 0
  (cd "$DIR" && fvm flutter build macos --release >"$LOG" 2>&1) || { echo "build falló: grep -n error $LOG | head -20"; grep -n error "$LOG" | head -20; exit 1; }
}

summary() { # informe ps
python3 -I - "$1" "$2" <<'PY'
import json, sys
r = json.load(open(sys.argv[1])); res = r.get("result") or {}
ps = []
try:
    for l in open(sys.argv[2]):
        p = l.split()
        if len(p) == 2: ps.append((float(p[0]), int(p[1]) // 1024))
except OSError:
    pass
c = r.get("case"); o = r.get("open") or {}
head = "%s %s | tex %s rot %s codec %s | sync %.0f Hz otroHilo %s | ps CPU %s%% RSS %s MB" % (c, r["file"].split("/")[-1], o.get("textureSize"), o.get("rotation"), o.get("codec"), (r.get("syncStats") or {}).get("hz", 0), (r.get("syncStats") or {}).get("otherThreadCalls"), round(sum(x[0] for x in ps) / len(ps), 1) if ps else "-", max([x[1] for x in ps]) if ps else "-")
print(head)
if r.get("error"): print("  ERROR:", r["error"], r.get("stack", [])[:3])
if c == "steady":
    for k, v in res.items():
        if k.startswith("rate_"): print("  %s e_ms med/p95/p99/min/max %s/%s/%s/%s/%s fuera %s%% saltados %s atrás %s dwellLargo %s inválidas %s" % (k, v["e_ms"]["median"], v["e_ms"]["p95"], v["e_ms"]["p99"], v["e_ms"]["min"], v["e_ms"]["max"], v["outOfTolPct"], v["skipped"], v["backSteps"], v["longDwell"], v["invalid"]))
elif c == "seek":
    print("  saltos (stay/first ms): " + " ".join("%s->%s/%s" % (j["target"], j["stayOkMs"], j["firstOkMs"]) for j in res.get("jumps", [])))
elif c == "loop":
    print("  vueltas (stay/first ms): " + " ".join("%s/%s" % (j["stayOkMs"], j["firstOkMs"]) for j in res.get("recovery", [])))
    v = res.get("inLoop", {}); print("  en bucle e_ms %s fuera %s%%" % (v.get("e_ms"), v.get("outOfTolPct")))
elif c == "cpu": print("  CPU %s%% de un núcleo, RSS %.0f MB (getrusage)" % (res.get("cpuPercentOfCore"), res.get("rssMb", 0)))
else: print("  ", json.dumps(res)[:400])
print("  mdkLog:", "; ".join(r.get("mdkLog", [])[:4])[:300])
PY
}

run_one() { # caso fichero espera_captura
  local kase="$1" file="$2" shot="$3"
  local base="${file%.*}"
  local report="$OUT/p5-$CAND-$kase-$base.json" ps="$OUT/p5-$CAND-$kase-$base.ps" png="$OUT/p5-$CAND-$kase-$base.png"
  local maxs=70; [ "$kase" != steady ] && maxs=45
  rm -f "$report" "$ps" "$png"
  open -g -n "$APP" --args --case "$kase" --file "$VID/$file" --report "$report" --exit-after "$maxs" --regime-s "${REGIME_S:-10}"
  local pid="" i
  for i in $(seq 1 40); do pid=$(pgrep -f "MacOS/$BIN" | head -1); [ -n "$pid" ] && break; sleep 0.5; done
  local t=0 shotdone=0
  while [ ! -f "$report" ] && [ $t -lt $((maxs * 2 + 20)) ]; do
    [ -n "$pid" ] && ps -o %cpu=,rss= -p "$pid" >>"$ps" 2>/dev/null
    if [ "$shot" != 0 ] && [ $shotdone = 0 ] && [ $t -ge $shot ]; then
      screencapture -x -l "$("$WINID" "$BIN")" "$png" 2>/dev/null; shotdone=1
    fi
    sleep 1; t=$((t + 1))
  done
  sleep 1
  pkill -f "MacOS/$BIN" 2>/dev/null
  if [ ! -f "$report" ]; then echo "SIN INFORME: $kase $file"; return 2; fi
  summary "$report" "$ps"
}

build
if [ "$CASE" = all ]; then
  for f in code-hevc.mov code-h264.mp4; do
    run_one steady "$f" 12
    run_one seek "$f" 0
    run_one loop "$f" 0
  done
  run_one cpu code-hevc.mov 0
  run_one rotation take-hevc-rot90.mov 3
  run_one rotation take-h264-rot90.mp4 3
  run_one start-pts take-hevc.mov 0
else
  f="${ONLY:-code-hevc.mov}"
  sh=0; [ "$CASE" = steady ] && sh=12; [ "$CASE" = rotation ] && sh=3
  run_one "$CASE" "$f" "$sh"
fi
l=$(pgrep -fl "MacOS/$BIN" | head -3); [ -n "$l" ] && echo "procesos restantes: $l"
exit 0
