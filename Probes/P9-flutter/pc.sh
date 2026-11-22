#!/bin/bash
# P9 7b: sincroniza el código al PC x64 (ssh pc), compila AppCoreFFI.dll y ejecuta el humo sin Flutter.
# Uso (desde la raíz del repo): Probes/P9-flutter/pc.sh sync|core|smoke|fetch
# Salida <= 15 líneas por paso; log completo en Temp/logs/p9-pc-<paso>.log.
# Códigos: 0 bien, 1 fallo del paso, 2 sin conexión.
# REGLA: en el PC solo se escribe dentro de PC_ROOT (Temp/p9, ignorada por git). Nada de git ni de escrituras fuera.
set -u
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
      --exclude .build --exclude build --exclude .dart_tool --exclude .fvm --exclude .git --exclude .DS_Store \
      --exclude '*.mlpackage' --exclude '*.onnx' --exclude '*.safetensors' --exclude '*.pt' \
      --exclude '*.wav' --exclude '*.mp3' --exclude '*.flac' --exclude '*.m4a' --exclude '*.mp4' --exclude '*.mov' \
      Packages Probes/P9-flutter ) >>"$LOG" 2>&1 || { echo "fallo al empaquetar"; return 1; }
  echo "tar: $(du -h "$tar" | cut -f1)"
  remote "mkdir -p $PC_ROOT/src $PC_ROOT/out" || return 1
  scp -q -o BatchMode=yes "$tar" "$PC_HOST:$PC_ROOT_SCP/src.tar" >>"$LOG" 2>&1 || { echo "fallo scp"; return 1; }
  # Borra fuentes que ya no existen (sin tocar .build/build/.dart_tool/.fvm) y extrae encima (conserva mtimes).
  remote "cd $PC_ROOT && tar -tf src.tar | sed 's#^\./##' | grep -v '/\$' | sort > out/new.lst && \
    cd src && find Packages Probes/P9-flutter \( -name .build -o -name build -o -name .dart_tool -o -name .fvm \) -prune -o -type f -print 2>/dev/null | sort > ../out/old.lst && \
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

case "$STEP" in
  sync) step_sync; rc=$? ;;
  core) step_core; rc=$? ;;
  smoke) step_smoke; rc=$? ;;
  fetch) step_fetch; rc=$? ;;
  *) echo "uso: pc.sh sync|core|smoke|fetch"; exit 1 ;;
esac
[ "$rc" -eq 0 ] || { echo "paso $STEP: fallo (log: Temp/logs/p9-pc-$STEP.log)"; exit 1; }
exit 0
