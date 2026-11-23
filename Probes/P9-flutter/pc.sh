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
  awk '/=== stray DESPUES/{f=1} f && /^STRAY/' "$LOG" | head -6
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
  local seq="via1:1 via2:1 via1:2 via2:2 via1:3 via2:3" extra="" item th n tag load rc
  [ "$mode" = "extra" ] && { seq="via1:x1 via1:x2"; extra="--noredir"; }
  local loadf="$dst/diag-load${mode:+-$mode}.txt"; : >"$loadf"
  for item in $seq; do
    th="${item%%:*}"; n="${item##*:}"; tag="diag-$th-$n"
    load="$("${SSH[@]}" 'wmic cpu get loadpercentage' 2>/dev/null | tr -d '\r' | grep -E '^[0-9]+' | head -1 | tr -d ' ')"
    echo "$tag $load" >>"$loadf"
    echo "=== $tag (carga previa ${load}%) ===" | tee -a "$LOG"
    rm -f "$dst/$tag.json" "$dst/$tag.code" "$dst/$tag.log" "$dst/$tag.err"
    remote "rm -rf $PC_ROOT/run/projects $PC_ROOT/run/support $PC_ROOT/out/run/$tag.json && mkdir -p $PC_ROOT/run/projects $PC_ROOT/run/support"
    step_run --tag "$tag" --timeout 240 $extra -- --probe ffi --sink port --threads "$th" --no-fail-fast \
      --core-lib "$REL_WIN\\AppCoreFFI.dll" --projects-folder "$PC_ROOT_WIN\\run\\projects" \
      --support-dir "$PC_ROOT_WIN\\run\\support" --wav "$PC_ROOT_WIN\\run\\in.wav" \
      --report "$PC_ROOT_WIN\\out\\run\\$tag.json" >/dev/null
    rc=$?
    echo "$tag rc=$rc" | tee -a "$LOG"
    for f in json code log err; do
      scp -q -o BatchMode=yes "$PC_HOST:$PC_ROOT_SCP/out/run/$tag.$f" "$dst/$tag.$f" >>"$LOG" 2>&1
    done
  done
  python3 -I "$ROOT/Probes/P9-flutter/pc-table.py" "$dst" diag 2>&1 | tee -a "$LOG"
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

step_frames() {
  local dst="$ROOT/Temp/p9-flutter/pc"
  mkdir -p "$dst"; : >"$dst/p3-load.txt"
  local alive; alive="$("${SSH[@]}" 'tasklist /FI "IMAGENAME eq tf_probe.exe" /NH' 2>&1 | tr -d '\r' | grep -c tf_probe)"
  [ "$alive" = "0" ] || { echo "hay tf_probe.exe vivo: no lanzo nada"; return 1; }
  remote "mkdir -p $PC_ROOT/run $PC_ROOT/out/run" || return 1
  # frames_one tag mode size kind segundos [env] [captura_a_los_s]
  if ! frames_one gpu-720 texture 720 gpu 60 "" 30; then
    echo "gpu-720 falla: corro pixel-720 de respaldo y paro"
    frames_one pixel-720 texture 720 pixel 60 "" 30
  else
    frames_one gpu-1080 texture 1080 gpu 60
    frames_one pixel-720 texture 720 pixel 60 "" 30
    frames_one pixel-1080 texture 1080 pixel 60
    frames_one bgra-720 bgra 720 gpu 60
    frames_one bgra-1080 bgra 1080 gpu 60
    frames_one solid-gpu texture 720 gpu 10 TF_P9_SOLID=1 6
    frames_one solid-pixel texture 720 pixel 10 TF_P9_SOLID=1 6
  fi
  python3 -I "$ROOT/Probes/P9-flutter/pc-frames-table.py" "$dst" 2>&1 | tee -a "$LOG"
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
  echo "rutas escapadas: $(awk '/=== stray DESPUES/{f=1} f && /^STRAY/' "$LOG" | wc -l | tr -d ' ') (ver log)"
  return $rc
}

case "$STEP" in
  frames) step_frames; rc=$? ;;
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
