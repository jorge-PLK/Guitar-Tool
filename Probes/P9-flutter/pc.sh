#!/bin/bash
# P9 7b: sincroniza el código al PC x64 (ssh pc), compila AppCoreFFI.dll y ejecuta el humo sin Flutter.
# Uso (desde la raíz del repo): Probes/P9-flutter/pc.sh sync|core|smoke|fetch
# Salida <= 15 líneas por paso; log completo en Temp/logs/p9-pc-<paso>.log.
# Códigos: 0 bien, 1 fallo del paso, 2 sin conexión.
# REGLA: en el PC solo se escribe dentro de PC_ROOT (Temp/p9, ignorada por git). Nada de git ni de escrituras fuera.
set -u
export LC_ALL=C  # tr/grep no deben fallar con bytes no UTF-8 de la salida de Windows
PC_HOST="${PC_HOST:-pc}"
PC_ROOT="${PC_ROOT:-/d/Personal/Guitar-Tool/Temp/p9}"
PC_ROOT_SCP="${PC_ROOT_SCP:-/D:/Personal/Guitar-Tool/Temp/p9}"  # scp/sftp no entiende /d/...
PC_ROOT_WIN="${PC_ROOT_WIN:-D:\\Personal\\Guitar-Tool\\Temp\\p9}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOGS="$ROOT/Temp/logs"
mkdir -p "$LOGS"
STEP="${1:-}"
LOG="$LOGS/p9-pc-${STEP:-none}.log"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=10 "$PC_HOST")
PS=(powershell -NoProfile -ExecutionPolicy Bypass -File)
WINDIR_REMOTE="$PC_ROOT_WIN\\src\\Probes\\P9-flutter\\win"

# Ejecuta un comando remoto; el log recibe todo. Devuelve 2 si no hay conexión.
remote() { "${SSH[@]}" "$@" >>"$LOG" 2>&1; local rc=$?; [ $rc -eq 255 ] && return 255; return $rc; }

: >"$LOG"
if ! "${SSH[@]}" 'echo ok' >/dev/null 2>&1; then echo "sin conexión con $PC_HOST"; exit 2; fi

step_sync() {
  local tar="$ROOT/Temp/p9-flutter/src.tar"
  mkdir -p "$ROOT/Temp/p9-flutter"
  # Sin builds, modelos ni medios pesados (ninguno hace falta para compilar los paquetes).
  ( cd "$ROOT" && COPYFILE_DISABLE=1 tar -cf "$tar" \
      --exclude .build --exclude build --exclude .dart_tool --exclude .fvm --exclude ephemeral --exclude .git --exclude .DS_Store \
      --exclude '*.mlpackage' --exclude '*.onnx' --exclude '*.safetensors' --exclude '*.pt' \
      --exclude '*.wav' --exclude '*.mp3' --exclude '*.flac' --exclude '*.m4a' --exclude '*.mp4' --exclude '*.mov' \
      Packages Probes/P9-flutter ) >>"$LOG" 2>&1 || { echo "fallo al empaquetar"; return 1; }
  echo "tar: $(du -h "$tar" | cut -f1)"
  remote "mkdir -p $PC_ROOT/src $PC_ROOT/out" || return 1
  scp -q -o BatchMode=yes "$tar" "$PC_HOST:$PC_ROOT_SCP/src.tar" >>"$LOG" 2>&1 || { echo "fallo scp"; return 1; }
  # Borra fuentes que ya no existen (sin tocar .build/build/.dart_tool/.fvm) y extrae encima (conserva mtimes).
  remote "cd $PC_ROOT && tar -tf src.tar | sed 's#^\./##' | grep -v '/\$' | sort > out/new.lst && \
    cd src && find Packages Probes/P9-flutter \( -name .build -o -name build -o -name .dart_tool -o -name .fvm -o -name ephemeral \) -prune -o -type f -print 2>/dev/null | sort > ../out/old.lst && \
    cd .. && comm -13 out/new.lst out/old.lst > out/gone.lst; echo \"borrados: \$(wc -l < out/gone.lst)\"; \
    (cd src && xargs -d '\n' -r rm -f < ../out/gone.lst) && tar -xf src.tar -C src && echo extraido" || { echo "fallo al extraer (ver $LOG)"; return 1; }
  tail -2 "$LOG"
}

# Ejecuta un .ps1 de win/ en segundo plano en el PC y sondea el log (no se corta por tope de herramienta).
run_bg() {
  local script="$1" tag="$2" limit="${3:-3000}"
  remote "rm -f $PC_ROOT/out/$tag.done; mkdir -p $PC_ROOT/out"
  "${SSH[@]}" "powershell -NoProfile -Command \"Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$WINDIR_REMOTE\\$script'\"" >>"$LOG" 2>&1 || { echo "no se pudo lanzar $script"; return 1; }
  local waited=0
  while [ $waited -lt "$limit" ]; do
    sleep 20; waited=$((waited + 20))
    if "${SSH[@]}" "test -f $PC_ROOT/out/$tag.done" 2>/dev/null; then
      "${SSH[@]}" "cat $PC_ROOT/out/$tag.log" >>"$LOG" 2>&1
      local rc; rc="$("${SSH[@]}" "cat $PC_ROOT/out/$tag.done" 2>/dev/null | tr -d '\r\n ')"
      [ "$rc" = "0" ] && return 0 || return 1
    fi
    [ $((waited % 120)) -eq 0 ] && echo "  ... ${waited}s: $("${SSH[@]}" "tail -c 150 $PC_ROOT/out/$tag.log 2>/dev/null | tail -1" 2>/dev/null)"
  done
  echo "tope de espera ($limit s) agotado; sigue en el PC: $PC_ROOT/out/$tag.log"
  return 1
}

step_core() {
  run_bg core.ps1 core 3000; local rc=$?
  grep -E '^TF:|^error:' "$LOG" | tail -15
  return $rc
}

step_smoke() {
  "${SSH[@]}" "powershell -NoProfile -ExecutionPolicy Bypass -File '$WINDIR_REMOTE\\smoke.ps1'" >>"$LOG" 2>&1; local rc=$?
  grep -v '^\s*$' "$LOG" | tail -15
  return $rc
}

step_fetch() {
  local dst="$ROOT/Temp/p9-flutter/pc"
  mkdir -p "$dst"
  remote "cd $PC_ROOT/out && find . \( -name '*.json' -o -name '*.log' -o -name '*.png' \) -type f" || return 1
  local n=0 f
  for f in $("${SSH[@]}" "cd $PC_ROOT/out && find . \( -name '*.json' -o -name '*.log' -o -name '*.png' \) -type f" | tr -d '\r'); do
    mkdir -p "$dst/$(dirname "$f")"
    scp -q -o BatchMode=yes "$PC_HOST:$PC_ROOT_SCP/out/$f" "$dst/$f" >>"$LOG" 2>&1 && n=$((n + 1))
  done
  echo "traidos $n ficheros a Temp/p9-flutter/pc/"
}

REL_WIN="$PC_ROOT_WIN\\src\\Probes\\P9-flutter\\app\\build\\windows\\x64\\runner\\Release"
stray() { "${SSH[@]}" "powershell -NoProfile -ExecutionPolicy Bypass -File '$WINDIR_REMOTE\\stray.ps1' $*" 2>&1 | tr -d '\r'; }

step_app() {
  local t0; t0="$("${SSH[@]}" "powershell -NoProfile -Command \"(Get-Date).AddMinutes(-1).ToString('yyyy-MM-dd HH:mm:ss')\"" | tr -d '\r')"
  { echo "=== stray ANTES ==="; stray; } >>"$LOG"
  run_bg app.ps1 app 3000; local rc=$?
  { echo "=== stray DESPUES (desde $t0) ==="; stray -Since "'$t0'"; } >>"$LOG"
  grep -E '^TF:|^error:' "$LOG" | tail -8
  echo "rutas escapadas (STRAY desde $t0):"
  awk '/=== stray DESPUES/{f=1} f && /^STRAY/ && !/\\.claude\\/' "$LOG" | head -6
  return $rc
}

# pc.sh run [--tag T] [--timeout S] -- <args de tf_probe>
step_run() {
  local tag="run1" timeout=240 noredir="" envv="" shot=0
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    case "$1" in --tag) tag="$2"; shift 2 ;; --timeout) timeout="$2"; shift 2 ;; --noredir) noredir="-NoRedirect"; shift ;; --env) envv="$2"; shift 2 ;; --shot) shot="$2"; shift 2 ;; *) shift ;; esac
  done
  [ "${1:-}" = "--" ] && shift
  local b64; b64="$(printf %s "$*" | base64 | tr -d '\n')"
  "${SSH[@]}" "mkdir -p $PC_ROOT/out/run"
  "${SSH[@]}" "powershell -NoProfile -ExecutionPolicy Bypass -File '$WINDIR_REMOTE\\run.ps1' -Tag '$tag' -ArgsB64 '$b64' -Timeout $timeout $noredir -EnvVars '$envv' -ShotAt $shot" 2>&1 | tr -d '\r' >>"$LOG"
  local rc=${PIPESTATUS[0]}
  grep -E '^TF:|^error:|^SUCCESS|ERROR' "$LOG" | tail -6
  return $rc
}

step_threads() {
  local dst="$ROOT/Temp/p9-flutter/pc" wav="$ROOT/Temp/p9-flutter/run/in.wav"
  [ -f "$wav" ] || { echo "falta $wav"; return 1; }
  mkdir -p "$dst"
  remote "mkdir -p $PC_ROOT/run $PC_ROOT/out/run" || return 1
  scp -q -o BatchMode=yes "$wav" "$PC_HOST:$PC_ROOT_SCP/run/in.wav" >>"$LOG" 2>&1 || { echo "fallo scp in.wav"; return 1; }
  local combo th sink tag rc
  for combo in via1:port via1:listener via2:port via2:listener none:port none:listener; do
    th="${combo%%:*}"; sink="${combo##*:}"; tag="p2-$th-$sink"
    remote "rm -rf $PC_ROOT/run/projects $PC_ROOT/run/support $PC_ROOT/out/run/$tag.json && mkdir -p $PC_ROOT/run/projects $PC_ROOT/run/support"
    echo "=== $tag ===" >>"$LOG"
    step_run --tag "$tag" --timeout 240 -- --probe ffi --sink "$sink" --threads "$th" \
      --core-lib "$REL_WIN\\AppCoreFFI.dll" --projects-folder "$PC_ROOT_WIN\\run\\projects" \
      --support-dir "$PC_ROOT_WIN\\run\\support" --wav "$PC_ROOT_WIN\\run\\in.wav" \
      --report "$PC_ROOT_WIN\\out\\run\\$tag.json" >/dev/null
    rc=$?
    echo "$tag rc=$rc" | tee -a "$LOG" >/dev/null
  done
  for f in $("${SSH[@]}" "cd $PC_ROOT/out/run && ls p2-*.json p2-*.log p2-*.err p2-*.code 2>/dev/null" | tr -d '\r'); do
    scp -q -o BatchMode=yes "$PC_HOST:$PC_ROOT_SCP/out/run/$f" "$dst/$f" >>"$LOG" 2>&1
  done
  python3 -I "$ROOT/Probes/P9-flutter/pc-table.py" "$dst" 2>&1 | tee -a "$LOG"
  return 0
}

# pc.sh diag [extra]: P9.7d-diag. 6 ejecuciones intercaladas via1,via2 x3 (--sink port --no-fail-fast), carga CPU previa anotada.
# `diag extra`: 2 ejecuciones de via1 con stdout/stderr SIN redirigir (separa el efecto del lanzador).
step_diag() {
  local dst="$ROOT/Temp/p9-flutter/pc" wav="$ROOT/Temp/p9-flutter/run/in.wav" mode="${1:-}"
  [ -f "$wav" ] || { echo "falta $wav"; return 1; }
  mkdir -p "$dst"
  local alive; alive="$("${SSH[@]}" 'tasklist /FI "IMAGENAME eq tf_probe.exe" /NH' 2>&1 | tr -d '\r' | grep -c tf_probe)"
  echo "tf_probe vivo antes: $alive"
  [ "$alive" = "0" ] || { echo "hay tf_probe.exe vivo: no lanzo nada"; return 1; }
  remote "mkdir -p $PC_ROOT/run $PC_ROOT/out/run" || return 1
  scp -q -o BatchMode=yes "$wav" "$PC_HOST:$PC_ROOT_SCP/run/in.wav" >>"$LOG" 2>&1 || { echo "fallo scp in.wav"; return 1; }
  local seq="via1:1 via2:1 via1:2 via2:2 via1:3 via2:3" extra="" item th n tag load rc sink="port" pfx="diag"
  [ "$mode" = "extra" ] && { seq="via1:x1 via1:x2"; extra="--noredir"; }
  # P9 7g medida 1: via 1, listener contra port, 3 ejecuciones alternadas. Tags sink-<sink>-<n>.
  [ "$mode" = "sink" ] && { seq="listener:1 port:1 listener:2 port:2 listener:3 port:3"; pfx="sink"; }
  local loadf="$dst/diag-load${mode:+-$mode}.txt"; : >"$loadf"
  for item in $seq; do
    th="${item%%:*}"; n="${item##*:}"; tag="diag-$th-$n"
    if [ "$mode" = "sink" ]; then sink="$th"; th="via1"; tag="sink-$sink-$n"; fi
    load="$("${SSH[@]}" 'wmic cpu get loadpercentage' 2>/dev/null | tr -d '\r' | grep -E '^[0-9]+' | head -1 | tr -d ' ')"
    echo "$tag $load" >>"$loadf"
    echo "=== $tag (carga previa ${load}%) ===" | tee -a "$LOG"
    rm -f "$dst/$tag.json" "$dst/$tag.code" "$dst/$tag.log" "$dst/$tag.err"
    remote "rm -rf $PC_ROOT/run/projects $PC_ROOT/run/support $PC_ROOT/out/run/$tag.json && mkdir -p $PC_ROOT/run/projects $PC_ROOT/run/support"
    step_run --tag "$tag" --timeout 240 $extra -- --probe ffi --sink "$sink" --threads "$th" --no-fail-fast \
      --core-lib "$REL_WIN\\AppCoreFFI.dll" --projects-folder "$PC_ROOT_WIN\\run\\projects" \
      --support-dir "$PC_ROOT_WIN\\run\\support" --wav "$PC_ROOT_WIN\\run\\in.wav" \
      --report "$PC_ROOT_WIN\\out\\run\\$tag.json" >/dev/null
    rc=$?
    echo "$tag rc=$rc" | tee -a "$LOG"
    for f in json code log err; do
      scp -q -o BatchMode=yes "$PC_HOST:$PC_ROOT_SCP/out/run/$tag.$f" "$dst/$tag.$f" >>"$LOG" 2>&1
    done
  done
  python3 -I "$ROOT/Probes/P9-flutter/pc-table.py" "$dst" diag "$pfx" 2>&1 | tee -a "$LOG"
  return 0
}

# pc.sh frames: P9.7f-B prueba 7 (textura externa), 60 s por combinacion, via 1, fallando rapido.
# Orden: gpu720 gpu1080 pixel720 pixel1080 bgra720 bgra1080; si gpu720 falla corre pixel720 de respaldo y para.
# Luego solid-gpu y solid-pixel (10 s, TF_P9_SOLID=1, captura a los 6 s). Informes y PNG a Temp/p9-flutter/pc/.
frames_one() { # tag mode size kind seconds [env] [shot]
  local tag="$1" mode="$2" size="$3" kind="$4" secs="$5" envv="${6:-}" shot="${7:-0}" dst="$ROOT/Temp/p9-flutter/pc"
  remote "rm -rf $PC_ROOT/run/projects $PC_ROOT/run/support $PC_ROOT/out/run/$tag.json && mkdir -p $PC_ROOT/run/projects $PC_ROOT/run/support"
  local load; load="$("${SSH[@]}" 'wmic cpu get loadpercentage' 2>/dev/null | tr -d '\r' | grep -E '^[0-9]+' | head -1 | tr -d ' ')"
  echo "$tag $load" >>"$dst/p3-load.txt"
  echo "=== $tag (carga previa ${load}%) ===" >>"$LOG"
  step_run --tag "$tag" --timeout $((secs + 60)) --env "$envv" --shot "$shot" -- --probe frames --mode "$mode" --size "$size" \
    --seconds "$secs" --threads via1 --texture-kind "$kind" --core-lib "$REL_WIN\\AppCoreFFI.dll" \
    --projects-folder "$PC_ROOT_WIN\\run\\projects" --support-dir "$PC_ROOT_WIN\\run\\support" \
    --report "$PC_ROOT_WIN\\out\\run\\$tag.json" >/dev/null
  local rc=$?
  echo "$tag rc=$rc" | tee -a "$LOG"
  local f
  for f in json code log err shot.txt png; do
    rm -f "$dst/p3-$tag.$f"
    scp -q -o BatchMode=yes "$PC_HOST:$PC_ROOT_SCP/out/run/$tag.$f" "$dst/p3-$tag.$f" >>"$LOG" 2>&1
  done
  return $rc
}

# pc.sh frames --only gpu-1080,bgra-720 (o gpu:1080,...): P9 7g medida 4. Solo esas combinaciones (tags de arriba, sin
# las -precise), sin respaldo; no vacia p3-load.txt. Informes en Temp/p9-flutter/pc/p3-<tag>.json.
step_frames_only() {
  local dst="$ROOT/Temp/p9-flutter/pc" t
  mkdir -p "$dst"
  local alive; alive="$("${SSH[@]}" 'tasklist /FI "IMAGENAME eq tf_probe.exe" /NH' 2>&1 | tr -d '\r' | grep -c tf_probe)"
  [ "$alive" = "0" ] || { echo "hay tf_probe.exe vivo: no lanzo nada"; return 1; }
  remote "mkdir -p $PC_ROOT/run $PC_ROOT/out/run" || return 1
  local list; list="$(echo "$1" | tr ':' '-' | tr ',' ' ')"
  for t in $list; do
    case "$t" in
      gpu-720)    frames_one "$t" texture 720 gpu 60 "" 30 ;;
      gpu-1080)   frames_one "$t" texture 1080 gpu 60 ;;
      pixel-720)  frames_one "$t" texture 720 pixel 60 "" 30 ;;
      pixel-1080) frames_one "$t" texture 1080 pixel 60 ;;
      bgra-720)   frames_one "$t" bgra 720 gpu 60 ;;
      bgra-1080)  frames_one "$t" bgra 1080 gpu 60 ;;
      *) echo "combinacion desconocida: $t" ;;
    esac
  done
  python3 -I "$ROOT/Probes/P9-flutter/pc-frames-table.py" "$dst" 2>&1 | tee -a "$LOG"
  return 0
}

step_frames() {
  local dst="$ROOT/Temp/p9-flutter/pc"
  if [ "${1:-}" = "--only" ]; then step_frames_only "${2:-}"; return $?; fi
  mkdir -p "$dst"; : >"$dst/p3-load.txt"
  local alive; alive="$("${SSH[@]}" 'tasklist /FI "IMAGENAME eq tf_probe.exe" /NH' 2>&1 | tr -d '\r' | grep -c tf_probe)"
  [ "$alive" = "0" ] || { echo "hay tf_probe.exe vivo: no lanzo nada"; return 1; }
  remote "mkdir -p $PC_ROOT/run $PC_ROOT/out/run" || return 1
  # frames_one tag mode size kind segundos [env] [captura_a_los_s]
  if [ "${1:-}" != "--no-fail-fast" ] && ! frames_one gpu-720 texture 720 gpu 60 "" 30; then
    echo "gpu-720 falla: corro pixel-720 de respaldo y paro"
    frames_one pixel-720 texture 720 pixel 60 "" 30
  else
    [ "${1:-}" = "--no-fail-fast" ] && frames_one gpu-720 texture 720 gpu 60 "" 30
    frames_one gpu-1080 texture 1080 gpu 60
    frames_one pixel-720 texture 720 pixel 60 "" 30
    frames_one pixel-1080 texture 1080 pixel 60
    frames_one bgra-720 bgra 720 gpu 60
    frames_one bgra-1080 bgra 1080 gpu 60
    frames_one gpu-720-precise texture 720 gpu 60 TF_P9_PRECISE=1
    frames_one pixel-720-precise texture 720 pixel 60 TF_P9_PRECISE=1
  fi
  python3 -I "$ROOT/Probes/P9-flutter/pc-frames-table.py" "$dst" 2>&1 | tee -a "$LOG"
  return 0
}

# Una ejecucion de `--probe <probe>` (via 1, port) con carga previa anotada en Temp/p9-flutter/pc/g7-load.txt.
# g7_one tag timeout probe [args extra de tf_probe...]; trae <tag>.json/.code/.log/.err a Temp/p9-flutter/pc/.
g7_one() {
  local tag="$1" timeout="$2" probe="$3"; shift 3
  local dst="$ROOT/Temp/p9-flutter/pc" wav="$ROOT/Temp/p9-flutter/run/in.wav" load f rc
  mkdir -p "$dst"
  local alive; alive="$("${SSH[@]}" 'tasklist /FI "IMAGENAME eq tf_probe.exe" /NH' 2>&1 | tr -d '\r' | grep -c tf_probe)"
  [ "$alive" = "0" ] || { echo "hay tf_probe.exe vivo: no lanzo nada"; return 1; }
  remote "mkdir -p $PC_ROOT/run $PC_ROOT/out/run" || return 1
  [ -f "$wav" ] && scp -q -o BatchMode=yes "$wav" "$PC_HOST:$PC_ROOT_SCP/run/in.wav" >>"$LOG" 2>&1
  load="$("${SSH[@]}" 'wmic cpu get loadpercentage' 2>/dev/null | tr -d '\r' | grep -E '^[0-9]+' | head -1 | tr -d ' ')"
  echo "$tag $load" >>"$dst/g7-load.txt"
  echo "=== $tag (carga previa ${load}%) ===" | tee -a "$LOG"
  rm -f "$dst/$tag".{json,code,log,err}
  remote "rm -rf $PC_ROOT/run/projects $PC_ROOT/run/support $PC_ROOT/out/run/$tag.json && mkdir -p $PC_ROOT/run/projects $PC_ROOT/run/support"
  step_run --tag "$tag" --timeout "$timeout" -- --probe "$probe" --threads via1 \
    --core-lib "$REL_WIN\\AppCoreFFI.dll" --projects-folder "$PC_ROOT_WIN\\run\\projects" \
    --support-dir "$PC_ROOT_WIN\\run\\support" --wav "$PC_ROOT_WIN\\run\\in.wav" \
    --report "$PC_ROOT_WIN\\out\\run\\$tag.json" "$@" >/dev/null
  rc=$?
  echo "$tag rc=$rc" | tee -a "$LOG"
  for f in json code log err; do
    scp -q -o BatchMode=yes "$PC_HOST:$PC_ROOT_SCP/out/run/$tag.$f" "$dst/$tag.$f" >>"$LOG" 2>&1
  done
  return $rc
}

# pc.sh soak [segundos=660] [llamadas]: P9 7g medida 2. RSS y buferes vivos cada 10 s, via 1 con puerto.
step_soak() {
  local secs="${1:-660}" calls="${2:-0}"
  g7_one soak-via1 $((secs + 300)) ffi-soak --sink port --soak-seconds "$secs" --calls "$calls"
  python3 -I "$ROOT/Probes/P9-flutter/pc-table.py" "$ROOT/Temp/p9-flutter/pc" soak "$ROOT/Temp/p9-flutter/pc/soak-via1.json" 2>&1 | tee -a "$LOG"
  return 0
}

# pc.sh mf: P9 7g medida 3. Apartamento COM del hilo de UI antes/despues de MFStartup y MFEnumDeviceSources.
step_mf() {
  g7_one mf-via1 200 ffi-mf --sink port
  local j="$ROOT/Temp/p9-flutter/pc/mf-via1.json"
  grep -A16 '"mf": {' "$j" | head -20 | tee -a "$LOG"
  grep -E '"failed"' -A3 "$j" | head -5
  return 0
}

# pc.sh webview [wv_all|wv_flutter|wv_inapp]: compila y arranca las candidatas de WebView (P9.7e). Sin argumento, las tres.
step_webview() {
  local cand="${1:-}" t0
  t0="$("${SSH[@]}" "powershell -NoProfile -Command \"(Get-Date).AddMinutes(-1).ToString('yyyy-MM-dd HH:mm:ss')\"" | tr -d '\r')"
  remote "mkdir -p $PC_ROOT/out && echo '$cand' > $PC_ROOT/out/webview.arg" || return 1
  { echo "=== stray ANTES ==="; stray; } >>"$LOG"
  run_bg webview.ps1 webview 3000; local rc=$?
  { echo "=== stray DESPUES (desde $t0) ==="; stray -Since "'$t0'"; } >>"$LOG"
  grep -E '^TF:|^error:' "$LOG" | grep -v 'TF:start' | cut -c1-230 | head -13
  echo "rutas escapadas: $(awk '/=== stray DESPUES/{f=1} f && /^STRAY/ && !/\\.claude\\/' "$LOG" | wc -l | tr -d ' ') (ver log)"
  return $rc
}

# pc.sh wvrun <wv_all|wv_flutter> <caso|all> [--tag sufijo] [--rebuild] [--keep-data]: P9 7j. Compila si falta el .exe (o --rebuild),
# lanza cada caso con ventana por la tarea interactiva (run.ps1 -ExePath), trae informe + captura + log a
# Temp/p9-flutter/pc/wv-<app>-<caso>[-sufijo].{json,png,out,err,keys.txt} y anota la carga previa en wv-load.txt.
# Casos: tab messages overlay resize-on resize-off capture fpsbar songsterr songsterr-offstage songsterr-zero keys-raw keys-flutter.
# Sin --keep-data borra el perfil de WebView (Temp\p9\run\wvdata\<app>) antes de cada caso (arranque en frio).
wv_args() { # caso -> argumentos de la app (sin --report/--user-data-dir) y segundo de captura en $WV_SHOT
  WV_SHOT=3; WV_ARGS=""
  case "$1" in
    tab|messages|overlay) WV_ARGS="--case $1 --exit-after 40"; WV_SHOT="${P9_SHOT:-2}" ;;
    resize-on) WV_ARGS="--case resize --raf-loop on --exit-after 40" ;;
    resize-off) WV_ARGS="--case resize --raf-loop off --exit-after 40" ;;
    capture) WV_ARGS="--case capture --exit-after 40"; WV_SHOT=10 ;;
    fpsbar) WV_ARGS="--case fpsbar --capture-secs 10 --exit-after 40"; WV_SHOT=6 ;;
    songsterr) WV_ARGS="--case songsterr --exit-after 40"; WV_SHOT=14 ;;
    songsterr-offstage) WV_ARGS="--case songsterr --mode offstage --exit-after 40" ;;
    songsterr-zero) WV_ARGS="--case songsterr --mode zero --exit-after 40" ;;
    keys-raw) WV_ARGS="--case keys --keys-mode raw --keys-script --keys-wait 8 --exit-after 40"; WV_SHOT=0 ;;
    keys-flutter) WV_ARGS="--case keys --keys-mode flutter --keys-script --keys-wait 8 --exit-after 40"; WV_SHOT=0 ;;
    *) return 1 ;;
  esac
}
WV_ALL_CASES="tab messages overlay resize-on resize-off capture songsterr songsterr-offstage songsterr-zero keys-raw keys-flutter"
wv_dirs() { "${SSH[@]}" "powershell -NoProfile -Command \"(Get-ChildItem 'C:\\Users\\Jorge\\AppData\\Local','C:\\Users\\Jorge\\AppData\\Roaming','C:\\Users\\Jorge\\AppData\\LocalLow' -Directory -ErrorAction SilentlyContinue).FullName\"" 2>/dev/null | tr -d '\r' | sort; }

step_wvrun() {
  local app="${1:-}" want="${2:-}"; shift 2 2>/dev/null
  local suffix="" rebuild=0 keep=0
  while [ $# -gt 0 ]; do
    case "$1" in --tag) suffix="-$2"; shift 2 ;; --rebuild) rebuild=1; shift ;; --keep-data) keep=1; shift ;; *) shift ;; esac
  done
  case "$app" in wv_all|wv_flutter) ;; *) echo "uso: pc.sh wvrun <wv_all|wv_flutter> <caso|all> [--tag s] [--rebuild] [--keep-data]"; return 1 ;; esac
  [ -n "$want" ] || { echo "falta caso (o all)"; return 1; }
  [ "$want" = "all" ] && want="$WV_ALL_CASES"
  local dst="$ROOT/Temp/p9-flutter/pc"; mkdir -p "$dst"
  local reldir="$PC_ROOT/src/Probes/P9-flutter/webview/$app/build/windows/x64/runner/Release"
  local relwin="$PC_ROOT_WIN\\src\\Probes\\P9-flutter\\webview\\$app\\build\\windows\\x64\\runner\\Release"
  local exe="$relwin\\$app.exe" outwin="$PC_ROOT_WIN\\out\\wv"
  if [ "$rebuild" = 1 ] || ! "${SSH[@]}" "test -f $reldir/$app.exe" 2>/dev/null; then
    echo "compilando $app ..."
    remote "mkdir -p $PC_ROOT/out && echo '$app:build' > $PC_ROOT/out/webview.arg" || return 1
    run_bg webview.ps1 webview 3000 || true
    grep -E "^TF:$app|^error:" "$LOG" | cut -c1-230 | tail -6
    "${SSH[@]}" "test -f $reldir/$app.exe" 2>/dev/null || { echo "no hay $app.exe tras compilar"; return 1; }
  fi
  local t0; t0="$("${SSH[@]}" "powershell -NoProfile -Command \"(Get-Date).AddMinutes(-1).ToString('yyyy-MM-dd HH:mm:ss')\"" | tr -d '\r')"
  wv_dirs >"$dst/wv-dirs-before-$app.txt"
  remote "mkdir -p $PC_ROOT/out/wv $PC_ROOT/run/wvdata"
  local c a b64 load rc f
  for c in $want; do
    wv_args "$c" || { echo "caso desconocido: $c"; continue; }
    local shot="$WV_SHOT" name="wv-$app-$c$suffix" rep="$outwin\\$app-$c$suffix.json" keysarg=""
    local repu="$PC_ROOT/out/wv/$app-$c$suffix"
    [ "${c%%-*}" = "keys" ] && keysarg="$rep.ready"
    [ "$keep" = 1 ] || remote "rm -rf $PC_ROOT/run/wvdata/$app"
    remote "rm -f $repu.json $repu.ready $repu.png $repu.out $repu.err $repu.code $repu.keys.txt $repu.shot.txt"
    load="$("${SSH[@]}" 'wmic cpu get loadpercentage' 2>/dev/null | tr -d '\r' | grep -E '^[0-9]+' | head -1 | tr -d ' ')"
    echo "$name $load" >>"$dst/wv-load.txt"
    local line="$WV_ARGS --report $rep --user-data-dir $PC_ROOT_WIN\\run\\wvdata\\$app"
    b64="$(printf %s "$line" | base64 | tr -d '\n')"
    echo "=== $name (carga previa ${load}%) ===" | tee -a "$LOG"
    "${SSH[@]}" "powershell -NoProfile -ExecutionPolicy Bypass -File '$WINDIR_REMOTE\\run.ps1' -Tag '$app-$c$suffix' -ArgsB64 '$b64' -Timeout 60 -ExePath '$exe' -RunOut '$outwin' -ShotAt $shot -Keys '$keysarg'" 2>&1 | tr -d '\r' >>"$LOG"
    rc=${PIPESTATUS[0]}
    grep 'TF:code' "$LOG" | tail -1
    rm -f "$dst/$name".{json,png,out,err,keys.txt}
    for f in json png keys.txt; do scp -q -o BatchMode=yes "$PC_HOST:$PC_ROOT_SCP/out/wv/$app-$c$suffix.$f" "$dst/$name.$f" >>"$LOG" 2>&1; done
    scp -q -o BatchMode=yes "$PC_HOST:$PC_ROOT_SCP/out/wv/$app-$c$suffix.log" "$dst/$name.out" >>"$LOG" 2>&1
    scp -q -o BatchMode=yes "$PC_HOST:$PC_ROOT_SCP/out/wv/$app-$c$suffix.err" "$dst/$name.err" >>"$LOG" 2>&1
  done
  wv_dirs >"$dst/wv-dirs-after-$app.txt"
  echo "carpetas nuevas bajo AppData (despues - antes):"; comm -13 "$dst/wv-dirs-before-$app.txt" "$dst/wv-dirs-after-$app.txt" | head -10
  { echo "=== stray (desde $t0) ==="; stray -Since "'$t0'"; echo "=== AppData modificado desde $t0 ==="; "${SSH[@]}" "find /c/Users/Jorge/AppData /c/Users/Jorge/Documents -newermt \"$t0\" -type f 2>/dev/null" | tr -d "\r" | grep -vE "D3DSCache|claude|Temp|Edge|Chrome|Google|NVIDIA|Crashpad|Packages|Microsoft|Discord|Spotify"; } >>"$LOG"
  echo "ficheros escapados: $(awk '/=== stray \(desde/{f=1} f && /^STRAY/ && !/\\.claude\\/' "$LOG" | wc -l | tr -d ' ')"
  awk '/=== stray \(desde/{f=1} f && /^STRAY/ && !/\\.claude\\/' "$LOG" | head -6
  echo "AppData/Documents modificado durante la pasada: $(awk '/=== AppData modificado/{f=1} f && /^\/c\//' "$LOG" | wc -l | tr -d ' ')"
  awk '/=== AppData modificado/{f=1} f && /^\/c\//' "$LOG" | head -6
  python3 -I "$ROOT/Probes/P9-flutter/pc-wv-table.py" "$dst" "$app" "$suffix" 2>&1 | tee -a "$LOG"
  return 0
}

# pc.sh tear [--wait 0|1] [--copy 1] (P9 7n: TF_P9_WAIT / TF_P9_COPY) [--ring 0|1|2|3|4] [--size 720|1080] [--seconds 60] [--kind gpu|pixel] [--region x,y,w,h] [--tag sufijo]: P9 7l.
# Prueba de fotogramas (via 1, TF_P9_TEAR=1) + detector de desgarro (win\tear.ps1) en la sesion interactiva (run.ps1 -Tear).
# --ring 0 = textura unica; 1 = anillo por defecto (3); 2..4 = anillo de ese tamano (TF_P9_RING). La app corre seconds+TEAR_PAD s
# y el detector mide `seconds` s tras TEAR_DELAY s. Trae a Temp/p9-flutter/pc/: tear-ring<R>-<size>[-kind][-tag].json (fotogramas),
# ...-det.json (detector), ...-det_tearN.png / ...-det_capN.png; carga previa en tear-load.txt.
TEAR_DELAY=6
TEAR_PAD=14
step_tear() {
  local ring=1 size=720 secs=60 kind=gpu region="" suffix="" wait="" copy="" extra=""
  while [ $# -gt 0 ]; do
    case "$1" in --ring) ring="$2"; shift 2 ;; --size) size="$2"; shift 2 ;; --seconds) secs="$2"; shift 2 ;; --kind) kind="$2"; shift 2 ;;
      --region) region="$2"; shift 2 ;; --wait) wait="$2"; shift 2 ;; --copy) copy="$2"; shift 2 ;; --tag) suffix="-$2"; shift 2 ;;
      --series) extra="-Series"; shift ;; *) shift ;; esac  # --series (P9 7g): el detector anade la serie de x y sus metricas al -det.json
  done
  local dst="$ROOT/Temp/p9-flutter/pc"; mkdir -p "$dst"
  local alive; alive="$("${SSH[@]}" 'tasklist /FI "IMAGENAME eq tf_probe.exe" /NH' 2>&1 | tr -d '\r' | grep -c tf_probe)"
  [ "$alive" = "0" ] || { echo "hay tf_probe.exe vivo: no lanzo nada"; return 1; }
  remote "mkdir -p $PC_ROOT/run $PC_ROOT/out/run" || return 1
  local tag="tear-ring$ring-$size"; [ "$kind" = "gpu" ] || tag="$tag-$kind"; [ -z "$wait" ] || tag="$tag-wait$wait"; [ "$copy" != "1" ] || tag="$tag-copy"; tag="$tag$suffix"
  local envv="TF_P9_TEAR=1"; [ -z "$wait" ] || envv="$envv;TF_P9_WAIT=$wait"; [ "$copy" != "1" ] || envv="$envv;TF_P9_COPY=1"; case "$ring" in 0|2|3|4) envv="$envv;TF_P9_RING=$ring" ;; esac
  local load; load="$("${SSH[@]}" 'wmic cpu get loadpercentage' 2>/dev/null | tr -d '\r' | grep -E '^[0-9]+' | head -1 | tr -d ' ')"
  echo "$tag $load" >>"$dst/tear-load.txt"
  echo "=== $tag (carga previa ${load}%) ===" | tee -a "$LOG"
  remote "rm -rf $PC_ROOT/run/projects $PC_ROOT/run/support && mkdir -p $PC_ROOT/run/projects $PC_ROOT/run/support; rm -f $PC_ROOT/out/run/$tag.* $PC_ROOT/out/run/$tag-det*"
  local b64; b64="$(printf %s "--probe frames --mode texture --size $size --seconds $((secs + TEAR_PAD)) --threads via1 --texture-kind $kind \
--core-lib $REL_WIN\\AppCoreFFI.dll --projects-folder $PC_ROOT_WIN\\run\\projects --support-dir $PC_ROOT_WIN\\run\\support \
--report $PC_ROOT_WIN\\out\\run\\$tag.json" | base64 | tr -d '\n')"
  local tr="$secs;tf_probe;$PC_ROOT_WIN\\out\\run\\$tag-det.json;$region;$TEAR_DELAY;$extra"
  "${SSH[@]}" "powershell -NoProfile -ExecutionPolicy Bypass -File '$WINDIR_REMOTE\\run.ps1' -Tag '$tag' -ArgsB64 '$b64' -Timeout $((secs + TEAR_PAD + 60)) -EnvVars '$envv' -Tear '$tr'" 2>&1 | tr -d '\r' >>"$LOG"
  local rc=${PIPESTATUS[0]}
  grep 'TF:code' "$LOG" | tail -1
  local f
  rm -f "$dst/$tag".* "$dst/$tag-det"*
  for f in json code log err tear.txt; do scp -q -o BatchMode=yes "$PC_HOST:$PC_ROOT_SCP/out/run/$tag.$f" "$dst/$tag.$f" >>"$LOG" 2>&1; done
  scp -q -o BatchMode=yes "$PC_HOST:$PC_ROOT_SCP/out/run/$tag-det.json" "$dst/$tag-det.json" >>"$LOG" 2>&1
  for f in $("${SSH[@]}" "cd $PC_ROOT/out/run && ls $tag-det_*.png 2>/dev/null" | tr -d '\r'); do
    scp -q -o BatchMode=yes "$PC_HOST:$PC_ROOT_SCP/out/run/$f" "$dst/$f" >>"$LOG" 2>&1
  done
  tr -d '\000\377\376' <"$dst/$tag.tear.txt" 2>/dev/null | tail -2 | cut -c1-200  # tear.txt sale en UTF-16
  return $rc
}

# pc.sh video [caso|all] [--rebuild] [--decoders "lista"] [--tag s]: P9 7h. Compila video\vp_fvp (fvp/mdk) en el PC si falta el .exe (o --rebuild),
# copia los videos a Temp\p9\run\video si faltan, lanza cada caso con ventana (run.ps1 -ExePath) y trae informe/captura/log a
# Temp/p9-flutter/pc/vid-fvp-<caso>[-tag].{json,png,out,err}; carga previa en vid-load.txt.
# --env "A=1;B=2" pasa variables al proceso (VP_DBG=1, VP_ATTACH=play, VP_MININT=n de la app).
# --engine native|fvp (fvp por defecto): native lanza tf_probe --probe video (tf_mfvideo.c, --texture-kind gpu, TF_P9_WAIT=1)
# del Release de app/ (pc.sh core + pc.sh app); informes vid-native-<caso>; si steady-hevc incumple no lanza nada mas.
# Casos: steady-hevc seek-hevc loop-hevc steady-h264 seek-h264 loop-h264 rot-hevc rot-h264. `all` falla rapido: si steady de un video incumple
# el umbral (pc-video-table.py verdict) se salta su seek/loop; tras el steady-hevc fallido hace UNA repeticion con --decoders FFmpeg (tag ffmpeg).
# Antes de cada lanzamiento espera a que no haya otra prueba con ventana (wv_all, wv_flutter, tf_probe) en el PC.
VID_NAMES="code-hevc.mov code-h264.mp4 take-hevc-rot90.mov take-h264-rot90.mp4"
vid_busy() { "${SSH[@]}" "tasklist" 2>/dev/null | grep -ciE 'wv_all|wv_flutter|tf_probe|vp_fvp'; }
vid_case() { # caso -> VC_CASE VC_FILE VC_SHOT
  case "$1" in
    steady-hevc) VC_CASE=steady; VC_FILE=code-hevc.mov; VC_SHOT=12 ;;
    seek-hevc) VC_CASE=seek; VC_FILE=code-hevc.mov; VC_SHOT=0 ;;
    loop-hevc) VC_CASE=loop; VC_FILE=code-hevc.mov; VC_SHOT=0 ;;
    steady-h264) VC_CASE=steady; VC_FILE=code-h264.mp4; VC_SHOT=12 ;;
    seek-h264) VC_CASE=seek; VC_FILE=code-h264.mp4; VC_SHOT=0 ;;
    loop-h264) VC_CASE=loop; VC_FILE=code-h264.mp4; VC_SHOT=0 ;;
    rot-hevc) VC_CASE=rotation; VC_FILE=take-hevc-rot90.mov; VC_SHOT=3 ;;
    rot-h264) VC_CASE=rotation; VC_FILE=take-h264-rot90.mp4; VC_SHOT=3 ;;
    *) return 1 ;;
  esac
}
vid_run() { # caso decoders suffix -> informe en $dst; devuelve 0 si el informe cumple los umbrales
  local c="$1" decs="$2" suffix="$3" dst="$ROOT/Temp/p9-flutter/pc"
  vid_case "$c" || { echo "caso desconocido: $c"; return 1; }
  local eng="${VID_ENGINE:-fvp}"
  local name="vid-$eng-$c$suffix" tag="$eng-$c$suffix" w=0
  while [ "$(vid_busy)" != "0" ] && [ $w -lt 1800 ]; do echo "  PC ocupado, espero ($w s)"; sleep 30; w=$((w + 30)); done
  [ "$(vid_busy)" = "0" ] || { echo "PC sigue ocupado: no lanzo $name"; return 1; }
  local outwin="$PC_ROOT_WIN\\out\\vid" outu="$PC_ROOT/out/vid" exe="$PC_ROOT_WIN\\src\\Probes\\P9-flutter\\video\\vp_fvp\\build\\windows\\x64\\runner\\Release\\vp_fvp.exe"
  local envv="$VID_ENV"
  if [ "$eng" = native ]; then
    exe="$REL_WIN\\tf_probe.exe"
    # TF_P9_WAIT=1 (decisión 7n, tf_d3d.c): publicar la textura solo cuando la GPU confirma la subida.
    envv="TF_P9_WAIT=1${VID_ENV:+;$VID_ENV}"
    remote "rm -rf $PC_ROOT/run/vproj $PC_ROOT/run/vsup; mkdir -p $PC_ROOT/run/vproj $PC_ROOT/run/vsup"
  fi
  remote "mkdir -p $outu; rm -f $outu/$tag.json $outu/$tag.png $outu/$tag.log $outu/$tag.err $outu/$tag.code $outu/$tag.shot.txt"
  local load; load="$("${SSH[@]}" 'wmic cpu get loadpercentage' 2>/dev/null | tr -d '\r' | grep -E '^[0-9]+' | head -1 | tr -d ' ')"
  echo "$name $load" >>"$dst/vid-load.txt"
  local line="--case $VC_CASE --file $PC_ROOT_WIN\\run\\video\\$VC_FILE --report $outwin\\$tag.json --exit-after 80"
  if [ "$eng" = native ]; then
    line="--probe video $line --core-lib $REL_WIN\\AppCoreFFI.dll --projects-folder $PC_ROOT_WIN\\run\\vproj --support-dir $PC_ROOT_WIN\\run\\vsup --texture-kind gpu"
  else
    line="$line --regime-s 10"
    [ -z "$decs" ] || line="$line --decoders $decs"
  fi
  local b64; b64="$(printf %s "$line" | base64 | tr -d '\n')"
  echo "=== $name (carga previa ${load}%) ===" | tee -a "$LOG"
  "${SSH[@]}" "powershell -NoProfile -ExecutionPolicy Bypass -File '$WINDIR_REMOTE\\run.ps1' -Tag '$tag' -ArgsB64 '$b64' -Timeout 100 -ExePath '$exe' -RunOut '$outwin' -ShotAt $VC_SHOT -EnvVars '$envv'" 2>&1 | tr -d '\r' >>"$LOG"
  grep 'TF:code' "$LOG" | tail -1
  rm -f "$dst/$name".{json,png,out,err}
  scp -q -o BatchMode=yes "$PC_HOST:$PC_ROOT_SCP/out/vid/$tag.json" "$dst/$name.json" >>"$LOG" 2>&1
  scp -q -o BatchMode=yes "$PC_HOST:$PC_ROOT_SCP/out/vid/$tag.png" "$dst/$name.png" >>"$LOG" 2>&1
  scp -q -o BatchMode=yes "$PC_HOST:$PC_ROOT_SCP/out/vid/$tag.log" "$dst/$name.out" >>"$LOG" 2>&1
  scp -q -o BatchMode=yes "$PC_HOST:$PC_ROOT_SCP/out/vid/$tag.err" "$dst/$name.err" >>"$LOG" 2>&1
  [ -f "$dst/$name.json" ] || { echo "SIN INFORME: $name"; return 1; }
  local v; v="$(python3 -I "$ROOT/Probes/P9-flutter/pc-video-table.py" verdict "$dst/$name.json")"; local rc=$?
  echo "  $name: $v" | tee -a "$LOG"
  return $rc
}

step_video() {
  local want="${1:-all}"; shift 2>/dev/null
  local suffix="" rebuild=0 decs=""; VID_ENV=""; VID_ENGINE=fvp
  while [ $# -gt 0 ]; do
    case "$1" in --tag) suffix="-$2"; shift 2 ;; --rebuild) rebuild=1; shift ;; --decoders) decs="$2"; shift 2 ;; --env) VID_ENV="$2"; shift 2 ;; --engine) VID_ENGINE="$2"; shift 2 ;; *) shift ;; esac
  done
  case "$VID_ENGINE" in fvp|native) ;; *) echo "--engine debe ser native o fvp"; return 1 ;; esac
  local dst="$ROOT/Temp/p9-flutter/pc" vsrc="$ROOT/Temp/p9-flutter/video"; mkdir -p "$dst"
  local reldir="$PC_ROOT/src/Probes/P9-flutter/video/vp_fvp/build/windows/x64/runner/Release"
  if [ "$VID_ENGINE" = native ]; then
    # tf_probe.exe y AppCoreFFI.dll los dejan `pc.sh core` + `pc.sh app`; aquí no se compila.
    reldir="$PC_ROOT/src/Probes/P9-flutter/app/build/windows/x64/runner/Release"
    "${SSH[@]}" "test -f $reldir/tf_probe.exe -a -f $reldir/AppCoreFFI.dll" 2>/dev/null || { echo "falta tf_probe.exe o AppCoreFFI.dll: pc.sh core && pc.sh app"; return 1; }
    [ "$want" = "build" ] && { echo "tf_probe.exe listo"; return 0; }
  elif [ "$rebuild" = 1 ] || ! "${SSH[@]}" "test -f $reldir/vp_fvp.exe" 2>/dev/null; then
    echo "compilando vp_fvp ..."
    run_bg video.ps1 video 3000 || true
    grep -E '^TF:(vp_fvp|ERR|flutter)|^error:' "$LOG" | cut -c1-230 | tail -10
    "${SSH[@]}" "test -f $reldir/vp_fvp.exe" 2>/dev/null || { echo "no hay vp_fvp.exe tras compilar"; return 1; }
  fi
  [ "$want" = "build" ] && { echo "vp_fvp.exe listo"; return 0; }
  local t0; t0="$("${SSH[@]}" "powershell -NoProfile -Command \"(Get-Date).AddMinutes(-1).ToString('yyyy-MM-dd HH:mm:ss')\"" | tr -d '\r')"
  remote "mkdir -p $PC_ROOT/run/video $PC_ROOT/out/vid" || return 1
  local f
  for f in $VID_NAMES; do
    "${SSH[@]}" "test -f $PC_ROOT/run/video/$f" 2>/dev/null || scp -q -o BatchMode=yes "$vsrc/$f" "$PC_HOST:$PC_ROOT_SCP/run/video/$f" >>"$LOG" 2>&1 || echo "fallo scp $f"
  done
  if [ "$want" = "all" ]; then
    local v gate=0
    for v in hevc h264; do
      if vid_run "steady-$v" "$decs" "$suffix"; then
        vid_run "seek-$v" "$decs" "$suffix"; vid_run "loop-$v" "$decs" "$suffix"
      else
        echo "steady-$v incumple: no sigo con seek/loop de $v"
        [ "$v" = hevc ] && [ -z "$decs" ] && [ "$VID_ENGINE" = fvp ] && vid_run steady-hevc FFmpeg "-ffmpeg"
        # Nativo: steady-hevc es la puerta de 7h; si incumple no se gasta turno del PC en el resto.
        [ "$VID_ENGINE" = native ] && [ "$v" = hevc ] && { echo "native: steady-hevc incumple, salto el resto"; gate=1; break; }
      fi
    done
    [ "$gate" = 1 ] || { vid_run rot-hevc "$decs" "$suffix"; vid_run rot-h264 "$decs" "$suffix"; }
  else
    vid_run "$want" "$decs" "$suffix"
  fi
  echo "ficheros escapados:"; { echo "=== stray (desde $t0) ==="; stray -Since "'$t0'"; } >>"$LOG"
  awk '/=== stray \(desde/{f=1} f && /^STRAY/ && !/\\.claude\\/' "$LOG" | head -6
  echo "n escapados: $(awk '/=== stray \(desde/{f=1} f && /^STRAY/ && !/\\.claude\\/' "$LOG" | wc -l | tr -d ' ')"
  python3 -I "$ROOT/Probes/P9-flutter/pc-video-table.py" table "$dst" "vid-$VID_ENGINE-" 2>&1 | tee -a "$LOG" | head -40
  return 0
}

# pc.sh wvfps <wv_all|wv_flutter> [--seconds 30] [--tag s]: P9 7g. fps REAL con que se pinta el WebView dentro de Flutter en Windows.
# Lanza el caso fpsbar con ventana (barra blanca que avanza por rAF) y, a la vez, win\tear.ps1 -Series sobre la zona del WebView
# (todo el area cliente menos la franja superior de Flutter, WV_TOP_LOGICAL px logicos: se escala con el DPI de la ventana, asi sirve a
# cualquier escala sin cambios). El detector muestrea a ~50-60 capturas/s: no puede ver mas posiciones distintas que eso.
# Trae a Temp/p9-flutter/pc/wvfps-<app>[-tag].{json (app), det.json (detector), png}; carga previa y escala en wvfps-load.txt.
WV_TOP_LOGICAL=44   # topBarHeight de screen.dart
WVFPS_DELAY=8       # s entre la aparicion de la ventana y el inicio del detector (la pagina tarda en estar lista)
step_wvfps() {
  local app="${1:-}"; shift 2>/dev/null
  local secs=30 suffix=""
  while [ $# -gt 0 ]; do
    case "$1" in --seconds) secs="$2"; shift 2 ;; --tag) suffix="-$2"; shift 2 ;; *) shift ;; esac
  done
  case "$app" in wv_all|wv_flutter) ;; *) echo "uso: pc.sh wvfps <wv_all|wv_flutter> [--seconds 30] [--tag s]"; return 1 ;; esac
  local dst="$ROOT/Temp/p9-flutter/pc"; mkdir -p "$dst"
  [ "$(vid_busy)" = "0" ] || { echo "hay otra prueba con ventana viva en el PC: no lanzo nada"; return 1; }
  local reldir="$PC_ROOT/src/Probes/P9-flutter/webview/$app/build/windows/x64/runner/Release"
  local relwin="$PC_ROOT_WIN\\src\\Probes\\P9-flutter\\webview\\$app\\build\\windows\\x64\\runner\\Release"
  "${SSH[@]}" "test -f $reldir/$app.exe" 2>/dev/null || { echo "falta $app.exe: pc.sh sync y pc.sh wvrun $app fpsbar --rebuild"; return 1; }
  local tag="$app-fps$suffix" name="wvfps-$app$suffix" outwin="$PC_ROOT_WIN\\out\\wv" repu="$PC_ROOT/out/wv"
  local capsecs=$((secs + WVFPS_DELAY + 20))
  remote "mkdir -p $repu $PC_ROOT/run/wvdata; rm -rf $PC_ROOT/run/wvdata/$app; rm -f $repu/$tag.* $repu/$tag-det*"
  local load; load="$("${SSH[@]}" 'wmic cpu get loadpercentage' 2>/dev/null | tr -d '\r' | grep -E '^[0-9]+' | head -1 | tr -d ' ')"
  local line="--case fpsbar --capture-secs $capsecs --exit-after $((capsecs + 25)) --report $outwin\\$tag.json --user-data-dir $PC_ROOT_WIN\\run\\wvdata\\$app"
  local b64; b64="$(printf %s "$line" | base64 | tr -d '\n')"
  local tr="$secs;$app;$outwin\\$tag.det.json;;$WVFPS_DELAY;-Series -TopLogical $WV_TOP_LOGICAL"
  echo "=== $name (carga previa ${load}%) ===" | tee -a "$LOG"
  "${SSH[@]}" "powershell -NoProfile -ExecutionPolicy Bypass -File '$WINDIR_REMOTE\\run.ps1' -Tag '$tag' -ArgsB64 '$b64' -Timeout $((capsecs + 60)) -ExePath '$relwin\\$app.exe' -RunOut '$outwin' -Tear '$tr'" 2>&1 | tr -d '\r' >>"$LOG"
  grep 'TF:code' "$LOG" | tail -1
  rm -f "$dst/$name".{json,det.json,png,tear.txt} "$dst/$name"_cap*.png
  local f
  scp -q -o BatchMode=yes "$PC_HOST:$PC_ROOT_SCP/out/wv/$tag.json" "$dst/$name.json" >>"$LOG" 2>&1
  scp -q -o BatchMode=yes "$PC_HOST:$PC_ROOT_SCP/out/wv/$tag.det.json" "$dst/$name.det.json" >>"$LOG" 2>&1
  scp -q -o BatchMode=yes "$PC_HOST:$PC_ROOT_SCP/out/wv/$tag.tear.txt" "$dst/$name.tear.txt" >>"$LOG" 2>&1
  scp -q -o BatchMode=yes "$PC_HOST:$PC_ROOT_SCP/out/wv/$tag.det_cap200.png" "$dst/$name.png" >>"$LOG" 2>&1
  local dpr; dpr="$(grep -m1 -oE '"devicePixelRatio": *[0-9.]+' "$dst/$name.json" 2>/dev/null | grep -oE '[0-9.]+$')"
  echo "$name load=${load}% dpr=${dpr:-?}" >>"$dst/wvfps-load.txt"
  tr -d '\000\377\376' <"$dst/$name.tear.txt" 2>/dev/null | tail -2 | cut -c1-200
  python3 -I "$ROOT/Probes/P9-flutter/pc-wvfps-table.py" "$dst" 2>&1 | tee -a "$LOG"
  return 0
}

case "$STEP" in
  wvfps) shift; step_wvfps "$@"; rc=$? ;;
  video) shift; step_video "$@"; rc=$? ;;
  tear) shift; step_tear "$@"; rc=$? ;;
  wvrun) shift; step_wvrun "$@"; rc=$? ;;
  soak) shift; step_soak "$@"; rc=$? ;;
  mf) shift; step_mf "$@"; rc=$? ;;
  frames) shift; step_frames "$@"; rc=$? ;;
  webview) shift; step_webview "$@"; rc=$? ;;
  app) step_app; rc=$? ;;
  run) shift; step_run "$@"; rc=$? ;;
  threads) step_threads; rc=$? ;;
  diag) shift; step_diag "$@"; rc=$? ;;
  sync) step_sync; rc=$?; ;;
  core) step_core; rc=$? ;;
  smoke) step_smoke; rc=$? ;;
  fetch) step_fetch; rc=$? ;;
  *) echo "uso: pc.sh sync|core|smoke|app|run|threads|fetch"; exit 1 ;;
esac
[ "$STEP" = "run" ] && exit "$rc"   # run devuelve el codigo del proceso (0/1/3/124)
[ "$rc" -eq 0 ] || { echo "paso $STEP: fallo (log: Temp/logs/p9-pc-$STEP.log)"; exit 1; }
exit 0
