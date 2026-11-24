#!/bin/bash
# Compila AppCoreFFI + la app de macOS y la lanza sin robar foco (`open -g -n`).
#   Tools/flutter/run.sh [--release] [--mock] [-- args de la app]
# Args de la app: --projects-folder, --support-dir, --screen, --project, --snapshot <png>, --snapshot-delay, --locale, --window ...
# Nunca usa la carpeta real de proyectos: sin --projects-folder/--support-dir usa Temp/flutter/ref-projects y Temp/flutter/support.
# Con --snapshot espera al PNG (tope 60 s) y sale 0 si existe, 1 si no. Sin --snapshot sale tras lanzar.
# Log: Temp/logs/run.log (build).
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
mkdir -p Temp/logs
log="Temp/logs/run.log"
: > "$log"

cfg="debug"; fcfg="Debug"; mock=0; app_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --release) cfg="release"; fcfg="Release"; shift ;;
    --mock) mock=1; shift ;;
    --) shift; app_args=("$@"); break ;;
    *) echo "argumento desconocido: $1 (los de la app van tras --)"; exit 1 ;;
  esac
done

has() { local a; for a in ${app_args[@]+"${app_args[@]}"}; do [ "$a" = "$1" ] && return 0; done; return 1; }
val() { local i; for ((i = 0; i < ${#app_args[@]}; i++)); do
  [ "${app_args[$i]}" = "$1" ] && { echo "${app_args[$((i + 1))]:-}"; return 0; }; done; return 1; }

if ! has --projects-folder; then
  mkdir -p Temp/flutter/ref-projects
  app_args+=(--projects-folder "$root/Temp/flutter/ref-projects")
  echo "aviso: sin --projects-folder, uso Temp/flutter/ref-projects"
fi
if ! has --support-dir; then
  mkdir -p Temp/flutter/support
  app_args+=(--support-dir "$root/Temp/flutter/support")
  echo "aviso: sin --support-dir, uso Temp/flutter/support"
fi
[ "$mock" = 1 ] && ! has --mock && app_args+=(--mock)

snap=""
if has --snapshot; then
  snap="$(val --snapshot)"
  case "$snap" in /*) ;; *) snap="$root/$snap" ;; esac
  # Sustituye el valor relativo por la ruta absoluta (la app arranca con otro cwd).
  for ((i = 0; i < ${#app_args[@]}; i++)); do
    [ "${app_args[$i]}" = "--snapshot" ] && app_args[$((i + 1))]="$snap"
  done
  mkdir -p "$(dirname "$snap")"
  rm -f "$snap"
fi

echo "core ($cfg) ..."
Tools/flutter/build-core.sh "$cfg" | tee -a "$log" | tail -3
echo "flutter build macos --$cfg ..."
if ! (cd FlutterApp && fvm flutter build macos "--$cfg" >> "$root/$log" 2>&1); then
  echo "flutter build fallo:"; grep -a -E 'error|Error' "$log" | head -10 || true
  echo "log: $log"; exit 1
fi
TF_CORE_COPY_ONLY=1 Tools/flutter/build-core.sh "$cfg" | tail -1

app="$root/FlutterApp/build/macos/Build/Products/$fcfg/toneforge.app"
[ -d "$app" ] || { echo "no existe $app"; exit 1; }
echo "lanzando $app"
open -g -n "$app" --args "${app_args[@]}"

if [ -n "$snap" ]; then
  waited=0
  while [ ! -s "$snap" ] && [ "$waited" -lt 60 ]; do sleep 1; waited=$((waited + 1)); done
  sleep 1
  if [ -s "$snap" ]; then echo "captura: $snap (${waited}s)"; exit 0; fi
  echo "sin captura tras 60 s: $snap"
  pkill -f "$fcfg/toneforge.app/Contents/MacOS/toneforge" 2>/dev/null || true
  exit 1
fi
