#!/bin/bash
# Compila, instala y arranca un paquete SwiftPM en la VM de Windows (Fase 7c, mini-spec del paso 3).
#
#   Tools/win/build.sh [--package <ruta en el repo>] [--product <nombre>] [--arch arm64|x64|both]
#                      [--gui] [--no-run] [--clean] [--stop]
#
# Por defecto: paquete Tools/win/smoke, producto tf-smoke, las dos arquitecturas, arranque en consola.
# Salida resumida (una linea por etapa); el log completo va a Temp/logs/win-<fecha>.log.
# Con --gui el arranque es en la sesion interactiva de tf y trae salida y captura a Temp/win/.
# Codigos: 0 bien, 1 falla el programa, 2 falla la compilacion, 3 VM o ssh inaccesibles.
set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root" || exit 3

VM="ToneForge-Win11"
HOST="tf-win"
BOOT_TIMEOUT=240        # segundos esperando a que responda ssh tras arrancar la VM
GUI_WAIT=8              # segundos que el programa se queda abierto en --gui
REMOTE_ROOT='C:\tf'
REMOTE_SCRIPTS='C:\tf\Tools\win\remote'

package="Tools/win/smoke"
product="tf-smoke"
arch="both"
gui=0
run=1
clean=0
stop=0
while [ $# -gt 0 ]; do
  case "$1" in
    --package) package="${2:-}"; shift ;;
    --product) product="${2:-}"; shift ;;
    --arch)    arch="${2:-}"; shift ;;
    --gui)     gui=1 ;;
    --no-run)  run=0 ;;
    --clean)   clean=1 ;;
    --stop)    stop=1 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $1"; exit 3 ;;
  esac
  shift
done
case "$arch" in arm64|x64|both) ;; *) echo "--arch debe ser arm64, x64 o both"; exit 3 ;; esac
package="${package#"$root"/}"   # ruta absoluta dentro del repo -> relativa
package="${package%/}"

mkdir -p Temp/logs Temp/win
log="Temp/logs/win-$(date '+%Y%m%d-%H%M%S').log"
: > "$log"

SSH=(ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 "$HOST")
PS="powershell -NoProfile -ExecutionPolicy Bypass -File"

# Ejecuta en la VM, anade la salida al log y la deja en $out (sin CR). Devuelve el codigo remoto.
out=""
rcmd() {
  out="$("${SSH[@]}" "$@" 2>&1)"
  local rc=$?
  out="$(printf '%s' "$out" | tr -d '\r' | sed -E $'s/\x1b\\[[0-9;]*m//g')"
  { echo "### $*"; echo "$out"; echo "### rc=$rc"; } >> "$log"
  return $rc
}

# Imprime las lineas con el prefijo dado (sin el prefijo "TF:").
tf_lines() { printf '%s\n' "$out" | grep -E '^TF:' | sed -E 's/^TF://'; }

finish() {
  if [ "$stop" -eq 1 ]; then
    utmctl stop "$VM" >> "$log" 2>&1 && echo "VM    apagada"
  fi
  exit "$1"
}

# --- VM ---------------------------------------------------------------------------------------
t0=$SECONDS
ssh_up() { "${SSH[@]}" 'echo ok' 2>/dev/null | grep -q ok; }
if ssh_up; then
  echo "VM    ya encendida, ssh responde"
else
  command -v utmctl > /dev/null || { echo "VM    utmctl no esta en el PATH y ssh no responde"; exit 3; }
  st="$(utmctl status "$VM" 2>&1)"
  echo "$st" >> "$log"
  case "$st" in
    *started*) ;;
    *) utmctl start "$VM" >> "$log" 2>&1 || { echo "VM    utmctl start fallo (ver $log)"; exit 3; } ;;
  esac
  until ssh_up; do
    if [ $((SECONDS - t0)) -ge "$BOOT_TIMEOUT" ]; then
      echo "VM    ssh $HOST no responde tras ${BOOT_TIMEOUT}s (ver $log)"
      exit 3
    fi
    sleep 3
  done
  echo "VM    arrancada, ssh responde ($((SECONDS - t0)) s)"
fi

# --- Ficheros ---------------------------------------------------------------------------------
t0=$SECONDS
if [ "$clean" -eq 1 ]; then
  rcmd "if (Test-Path $REMOTE_ROOT) { Remove-Item -Recurse -Force $REMOTE_ROOT }; if (Test-Path C:\\ToneForge) { Remove-Item -Recurse -Force C:\\ToneForge }" \
    || { echo "FICHEROS no se pudo limpiar C:\\tf: $out"; exit 3; }
  echo "LIMPIO C:\\tf y C:\\ToneForge borrados"
fi
list="$(mktemp -t tfwin-list)"
tarf="$(mktemp -t tfwin-tar)"
trap 'rm -f "$list" "$tarf"' EXIT
git ls-files -co --exclude-standard | while IFS= read -r f; do [ -e "$f" ] && [ ! -d "$f" ] && printf '%s\n' "$f"; done > "$list"
n="$(wc -l < "$list" | tr -d ' ')"
COPYFILE_DISABLE=1 tar --no-xattrs -cf "$tarf" -T "$list" >> "$log" 2>&1 || { echo "FICHEROS tar fallo (ver $log)"; exit 3; }
size="$(du -h "$tarf" | cut -f1)"
scp -q -o BatchMode=yes "$tarf" "$HOST:C:/tf-src.tar" >> "$log" 2>&1 || { echo "FICHEROS scp fallo (ver $log)"; exit 3; }
rcmd "New-Item -ItemType Directory -Force $REMOTE_ROOT | Out-Null; tar -xf C:\\tf-src.tar -C $REMOTE_ROOT; exit \$LASTEXITCODE" \
  || { echo "FICHEROS extraccion fallo: $(printf '%s' "$out" | tail -3)"; exit 3; }
echo "FICHEROS $n ficheros ($size) en C:\\tf ($((SECONDS - t0)) s)"

# --- Compilacion ------------------------------------------------------------------------------
rcmd "$PS $REMOTE_SCRIPTS\\build.ps1 -Package $package -Arch $arch"
rc=$?
tf_lines | while read -r kind a status secs; do
  [ "$kind" = "BUILD" ] && echo "BUILD $a $status (${secs} s)"
done
if [ "$rc" -ne 0 ]; then
  errs="$(printf '%s\n' "$out" | grep -E 'error:' | sed -E 's/^ *\[[a-z0-9]+\] //' | sort -u | cut -c1-220 | head -15)"
  [ -z "$errs" ] && errs="$(printf '%s\n' "$out" | tail -8)"
  printf '%s\n' "$errs" | sed 's/^/      /'
  echo "Log completo: $log"
  finish 2
fi

# --- Instalacion ------------------------------------------------------------------------------
rcmd "$PS $REMOTE_SCRIPTS\\install.ps1 -Package $package -Product $product -Arch $arch"
rc=$?
tf_lines | grep '^PE ' | while read -r _ a mach st rest; do echo "PE    $a $mach $st $rest"; done
if [ "$rc" -ne 0 ]; then echo "Log completo: $log"; finish 2; fi

# --- Arranque ---------------------------------------------------------------------------------
if [ "$run" -eq 0 ]; then
  echo "RUN   omitido (--no-run)"
  finish 0
fi

status=0
if [ "$gui" -eq 1 ]; then
  rcmd "$PS $REMOTE_SCRIPTS\\gui.ps1 -Product $product -Arch $arch -Wait $GUI_WAIT"
  rc=$?
  if [ "$rc" -eq 3 ]; then
    echo "GUI   el usuario tf no tiene sesion grafica iniciada en la VM."
    echo "      Inicia sesion en la ventana de UTM (usuario tf) y repite."
    finish 3
  fi
  tf_lines | grep '^GUI ' | sed -E 's/^GUI /GUI   /'
  printf '%s\n' "$out" | grep -E '^  \[' | sed 's/^/      /'
  for a in $( [ "$arch" = both ] && echo "arm64 x64" || echo "$arch" ); do
    scp -q -o BatchMode=yes "$HOST:C:/ToneForge/gui-$a.png" "Temp/win/gui-$a.png" >> "$log" 2>&1 \
      && echo "      captura: Temp/win/gui-$a.png"
    scp -q -o BatchMode=yes "$HOST:C:/ToneForge/gui-$a.txt" "Temp/win/gui-$a.txt" >> "$log" 2>&1
  done
  [ "$rc" -ne 0 ] && status=1
else
  rcmd "$PS $REMOTE_SCRIPTS\\run.ps1 -Product $product -Arch $arch"
  rc=$?
  tf_lines | grep '^RUN ' | while read -r _ a code; do echo "RUN   $a codigo $code"; done
  printf '%s\n' "$out" | grep -E '^  \[' | sed 's/^/      /'
  [ "$rc" -ne 0 ] && status=1
fi
[ "$status" -ne 0 ] && echo "Log completo: $log"
finish "$status"
