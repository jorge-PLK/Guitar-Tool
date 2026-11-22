#!/bin/bash
# P9 prueba 4 (WebView en el Mac). Uso: run-probe4.sh <wv_all|wv_flutter> <tab|messages|overlay|resize|songsterr|occluded|all>
#   all = tab (si falla se para) + messages, overlay, resize, songsterr, occluded visible y oculta. `keys` NO entra en all (lo ejecuta Jorge en primer plano).
#   SKIP_BUILD=1 no recompila.   Informes y capturas: Temp/p9-flutter/p4-<cand>-<caso>.{json,png}
set -u
CAND="${1:?candidata: wv_all|wv_flutter}"
CASE="${2:-all}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="$ROOT/Probes/P9-flutter/webview/$CAND"
OUT="$ROOT/Temp/p9-flutter"
LOGS="$ROOT/Temp/logs"
BUILT="$DIR/build/macos/Build/Products/Release/$CAND.app"
# La app se lanza desde /private/tmp (no desde /Volumes: evita el diálogo TCC de volumen extraíble).
TMPD="/private/tmp/p9p4"
APP="$TMPD/$CAND.app"
TOUT="$TMPD/out"
WINID="$ROOT/Temp/flutter-probe/tools/winid"
mkdir -p "$OUT" "$LOGS" "$TOUT"

build() {
  if [ "${SKIP_BUILD:-0}" != "1" ]; then
    (cd "$DIR" && fvm flutter build macos --release >"$LOGS/p9-p4-$CAND.log" 2>&1) || { echo "flutter build falló: $LOGS/p9-p4-$CAND.log"; exit 1; }
  fi
  rm -rf "$APP"
  ditto "$BUILT" "$APP" || { echo "ditto falló"; exit 1; }
}

# publish <nombre>: copia informe y capturas de /private/tmp/p9p4/out a Temp/p9-flutter
publish() {
  for ext in json png; do
    [ -f "$TOUT/p4-$CAND-$1.$ext" ] && cp "$TOUT/p4-$CAND-$1.$ext" "$OUT/"
  done
  [ -f "$TOUT/p4-$CAND-$1-internal.png" ] && cp "$TOUT/p4-$CAND-$1-internal.png" "$OUT/"
}

summary() { # informe
python3 -I - "$1" <<'EOF'
import json, sys
r = json.load(open(sys.argv[1]))
keys = ["case", "ok", "failure", "timedOut", "timeToReadyMs", "scoreLoadToRenderedMs", "bravuraLoaded", "serving", "rafFps", "ticksPerSecond", "samplesReceived", "allInnerMatch", "alphaTabRerenderedEveryStep", "badMessages", "eventCounts"]
print("  " + " | ".join("%s=%s" % (k, r[k]) for k in keys if k in r))
for k in ("resources", "roundTrip", "burstJsToDart", "burstDartToJs", "jsErrors", "webErrors"):
    if k in r and r[k] not in ([], None): print("  %s: %s" % (k, json.dumps(r[k])[:600]))
sys.exit(0 if r.get("ok") else 1)
EOF
}

# run_one <caso> <nombre-salida> <exit-after> [args extra de la app] ; HIDE=1 oculta el proceso a los 4 s; SHOT=0 sin captura
run_one() {
  local c="$1" name="$2" secs="$3"; shift 3
  local report="$TOUT/p4-$CAND-$name.json" png="$TOUT/p4-$CAND-$name.png" snap="$TOUT/p4-$CAND-$name-internal.png"
  rm -f "$report" "$png" "$snap"
  open -g -n "$APP" --args --case "$c" --report "$report" --snapshot "$snap" --exit-after "$secs" "$@"
  if [ "${HIDE:-0}" = "1" ]; then
    sleep 4
    osascript -e "tell application \"System Events\" to set visible of (first process whose name is \"$CAND\") to false" >/dev/null 2>&1
  fi
  local i=0
  while [ ! -f "$report" ] && [ $i -lt $(( (secs + 20) * 2 )) ]; do sleep 0.5; i=$((i + 1)); done
  if [ -f "$report" ] && [ "${HIDE:-0}" != "1" ] && [ "${SHOT:-1}" = "1" ]; then
    local id; id=$("$WINID" "$CAND" 2>/dev/null | head -1)
    [ -n "$id" ] && screencapture -x -l "$id" "$png"
  fi
  pkill -f "MacOS/$CAND" 2>/dev/null
  sleep 1
  publish "$name"
  if [ ! -f "$report" ]; then echo "[$name] SIN INFORME"; return 2; fi
  echo "[$name]"
  summary "$report"
}

# keys: manual de Jorge, en primer plano (único caso con open -n sin -g)
run_keys() {
  local report="$TOUT/p4-$CAND-keys.json"
  rm -f "$report"
  open -n "$APP" --args --case keys --report "$report" --snapshot "$TOUT/p4-$CAND-keys-internal.png" --exit-after 60
  local i=0
  while [ ! -f "$report" ] && [ $i -lt 160 ]; do sleep 0.5; i=$((i + 1)); done
  pkill -f "MacOS/$CAND" 2>/dev/null
  sleep 1
  publish keys
  if [ ! -f "$report" ]; then echo "[keys] SIN INFORME"; return 2; fi
  echo "[keys]"
  summary "$report"
}

secs_for() { case "$1" in messages) echo 90;; occluded) echo 45;; *) echo 40;; esac; }

one() {
  case "$1" in
    occluded)
      run_one occluded occluded-visible 45 --occluded-delay 0; local a=$?
      HIDE=1 run_one occluded occluded-hidden 50 --occluded-delay 8; local b=$?
      return $((a + b)) ;;
    keys) run_keys ;;
    songsterr-hidden)
      local modes="offstage zero"; [ "$CAND" = "wv_all" ] && modes="$modes offscreen"; local rc=0
      for m in $modes; do run_one songsterr "songsterr-$m" 40 --mode "$m"; rc=$((rc + $?)); done
      return $rc ;;
    *) run_one "$1" "$1" "$(secs_for "$1")" ;;
  esac
}

build
if [ "$CASE" = "all" ]; then
  one tab; rc=$?
  [ $rc -ne 0 ] && { echo "tab no pasa: se para $CAND"; exit 1; }
  fail=0
  for c in messages overlay resize songsterr occluded; do one "$c" || fail=1; done
  exit $fail
else
  one "$CASE"; exit $?
fi
