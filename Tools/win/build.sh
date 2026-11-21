#!/bin/bash
# Compila, instala y arranca un paquete SwiftPM en la VM de Windows, o le pasa sus tests (Fase 7c).
#
#   Tools/win/build.sh [--package <ruta en el repo>] [--product <nombre>] [--arch x64|arm64|both]
#                      [--gui] [--gui-args "<args del programa>"] [--no-run] [--clean] [--stop] [--release]
#   Tools/win/build.sh --test [--filter <X>] [--package <ruta>] [--arch x64|arm64|both] [--clean] [--stop] [--release]
#
# Por defecto: paquete Tools/win/smoke, producto tf-smoke, solo x64 (decision: Windows es solo x64;
#   arm64 y both siguen aceptandose pero no son puerta), arranque en consola.
# --test: swift test del paquete en la VM (x64 emulada; ARM64 nativo con --arch), sin instalar ni arrancar.
#   Una linea por arquitectura (pasados, fallados, saltados, segundos), los saltados agrupados por su
#   mensaje de XCTSkip (etiquetas "[paso 7] <pieza>"), fallos con fichero:linea y errores de compilacion.
# --release: SOLO para medir tiempos (las puertas siguen en debug, el valor por defecto). Con --test pasa
#   -Config release a test.ps1 (swift test -c release -Xswiftc -enable-testing) y la linea sale como
#   "TEST  x64 release OK ...". La compilacion normal ya es release (Get-SwiftArgs), asi que solo cambia la
#   etiqueta ("BUILD x64 release OK ...") y los topes por defecto: TF_VM_TIMEOUT 1500, TF_VM_BUILD_TIMEOUT 1800.
# --gui-args: con --gui, argumentos que recibe el programa (sustituyen al "--wait N" del smoke), p. ej. para ToneForge:
#   --package WinApp --product ToneForge --gui --gui-args "--projects-folder C:\tf-qa\projects --snapshot C:\ToneForge\snap.png"
#   --gui-env "A=B;C=D": variables de entorno para el programa (p. ej. "TF_MODELS_DIR=C:\tf-models").
#   Con --snapshot-hold <s> en --gui-args la app mantiene la ventana abierta s segundos tras guardar el PNG y la
#   captura de escritorio (Temp/win/gui-x64.png) se hace entonces, con la ventana visible.
#   Si trae --snapshot <ruta>, se borra antes de arrancar y se trae a Temp/win/<nombre>; el programa puede tardar hasta
#   75 s (despues se mata y el codigo es 124). stderr del programa vuelve en Temp/win/gui-<arch>.err.
#   WinApp: install.ps1 copia WinApp/Web como Web\ junto al .exe; las cabeceras y el loader de WebView2 salen de
#   Vendor/win/webview2 (Tools/win/fetch-webview2.sh) y se copian a C:\tf-webview2 cuando cambia su VERSION.
# Salida resumida (una linea por etapa); el log completo va a Temp/logs/win-<fecha>.log
#   (win-test-<fecha>.log con --test). Con --gui el arranque es en la sesion interactiva de tf y trae
#   salida y captura a Temp/win/.
# Codigos: 0 bien, 1 falla el programa (o hay tests fallados o TIMEOUT en tests), 2 falla la compilacion
#   (o nada que probar, o TIMEOUT al compilar), 3 VM o ssh inaccesibles (o cerrojo ocupado mas alla del
#   tope, o el ssh de test/compilacion no volvio).
# Topes de tiempo (segundos, 0 = sin tope; estado TIMEOUT con el ultimo test arrancado, se mata el arbol):
#   TF_VM_TIMEOUT (600) total por arquitectura en --test; TF_VM_IDLE (0, apagado) sin salida nueva del test;
#   TF_VM_BUILD_TIMEOUT (900) total por arquitectura al compilar. Respaldo en el Mac: si el ssh no vuelve
#   en tope remoto + 120 s se mata, se intenta matar swift/xctest de la VM por otro ssh y sale con 3.
# Cerrojo de la VM: toma Temp/win/vm.lock (mkdir) y lo suelta al salir, aunque falle o se interrumpa;
#   si esta ocupado espera cada 15 s hasta TF_VM_LOCK_WAIT segundos (por defecto 1200) y sale con 3.
#   TF_VM_LOCKED=1: lo tiene el llamante (mkdir a mano); no toma ni suelta el cerrojo.
# TF_VM_ENV (solo --test, opcional): variables TF_* para el swift test de la VM, "TF_A=1;TF_B=C:\x".
#   Ej.: TF_VM_ENV='TF_MODEL_TESTS=1;TF_MODELS_DIR=C:\tf-models' (tests con modelo real, de uno en uno).
set -u
export LC_ALL=C   # la salida de la VM puede traer bytes no UTF-8: tr/sed/grep fallan con "Illegal byte sequence"

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
arch="x64"
gui=0
gui_args=""
gui_env=""
run=1
clean=0
stop=0
test=0
release=0
filter=""
while [ $# -gt 0 ]; do
  case "$1" in
    --package) package="${2:-}"; shift ;;
    --product) product="${2:-}"; shift ;;
    --arch)    arch="${2:-}"; shift ;;
    --gui)     gui=1 ;;
    --gui-args) gui_args="${2:-}"; shift ;;
    --gui-env)  gui_env="${2:-}"; shift ;;
    --no-run)  run=0 ;;
    --clean)   clean=1 ;;
    --stop)    stop=1 ;;
    --test)    test=1 ;;
    --release) release=1 ;;
    --filter)  filter="${2:-}"; shift ;;
    -h|--help) sed -n '2,41p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $1"; exit 3 ;;
  esac
  shift
done
case "$arch" in arm64|x64|both) ;; *) echo "--arch debe ser arm64, x64 o both"; exit 3 ;; esac
[ -n "$filter" ] && [ "$test" -eq 0 ] && { echo "--filter solo se usa con --test"; exit 3; }
[ -n "$gui_args" ] && [ "$gui" -eq 0 ] && { echo "--gui-args solo se usa con --gui"; exit 3; }
[ -n "$gui_env" ] && [ "$gui" -eq 0 ] && { echo "--gui-env solo se usa con --gui"; exit 3; }
package="${package#"$root"/}"   # ruta absoluta dentro del repo -> relativa
package="${package%/}"

mkdir -p Temp/logs Temp/win
log="Temp/logs/win-$([ "$test" -eq 1 ] && echo 'test-')$(date '+%Y%m%d-%H%M%S').log"
: > "$log"

# --- Cerrojo de la VM (un solo usuario a la vez: C:\tf es unico) ------------------------------------
LOCK="Temp/win/vm.lock"
LOCK_POLL=15
LOCK_WAIT="${TF_VM_LOCK_WAIT:-1200}"
have_lock=0
T_TOTAL="${TF_VM_TIMEOUT:-$([ "$release" -eq 1 ] && echo 1500 || echo 600)}"
T_IDLE="${TF_VM_IDLE:-0}"   # 0: swift-test en Windows no reenvia la salida del runner hasta el final
T_BUILD="${TF_VM_BUILD_TIMEOUT:-$([ "$release" -eq 1 ] && echo 1800 || echo 900)}"
rtag=""; [ "$release" -eq 1 ] && rtag=" release"
cfg=""; [ "$release" -eq 1 ] && cfg=" -Config release"
BACKUP_MARGIN=120
list=""
tarf=""
cleanup() {
  [ -n "$list" ] && rm -f "$list"
  [ -n "$tarf" ] && rm -f "$tarf"
  if [ "$have_lock" -eq 1 ]; then
    rm -f "$LOCK/owner"
    rmdir "$LOCK" 2> /dev/null
    have_lock=0
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [ "${TF_VM_LOCKED:-0}" != "1" ]; then
  waited=0
  until mkdir "$LOCK" 2> /dev/null; do
    holder="$(cat "$LOCK/owner" 2> /dev/null)"
    if [ "$waited" -ge "$LOCK_WAIT" ]; then
      echo "VM    cerrojo $LOCK ocupado tras ${LOCK_WAIT}s: ${holder:-quien lo tiene no dejo owner}"
      echo "      Si ya no hay nadie usando la VM, borralo: rm -f $LOCK/owner; rmdir $LOCK"
      exit 3
    fi
    [ "$waited" -eq 0 ] && echo "VM    ocupada (${holder:-sin owner}); espero hasta ${LOCK_WAIT}s"
    sleep "$LOCK_POLL" &
    wait $!
    waited=$((waited + LOCK_POLL))
  done
  have_lock=1
  echo "pid $$ | $0 $* | $(date '+%Y-%m-%d %H:%M:%S')" > "$LOCK/owner"
  [ "$waited" -gt 0 ] && echo "VM    cerrojo obtenido tras ${waited}s"
fi

SSH=(ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 "$HOST")
PS="powershell -NoProfile -ExecutionPolicy Bypass -File"

# Ejecuta en la VM, anade la salida al log y la deja en $out (sin CR). Devuelve el codigo remoto.
out=""
RCMD_LIMIT=0   # segundos de respaldo para la siguiente rcmd (0 = sin tope); lo pone el llamante
RCMD_HUNG=0
rcmd() {
  local tmp rc pid waited=0
  RCMD_HUNG=0
  tmp="$(mktemp -t tfwin-out)"
  "${SSH[@]}" "$@" > "$tmp" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2> /dev/null; do
    if [ "$RCMD_LIMIT" -gt 0 ] && [ "$waited" -ge "$RCMD_LIMIT" ]; then
      kill "$pid" 2> /dev/null; sleep 1; kill -9 "$pid" 2> /dev/null
      RCMD_HUNG=1
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid" 2> /dev/null
  rc=$?
  [ "$RCMD_HUNG" -eq 1 ] && rc=255
  out="$(cat "$tmp")"
  rm -f "$tmp"
  RCMD_LIMIT=0
  out="$(printf '%s' "$out" | tr -d '\r' | sed -E $'s/\x1b\\[[0-9;]*m//g')"
  { echo "### $*"; echo "$out"; echo "### rc=$rc"; } >> "$log"
  return $rc
}

# Tras un ssh colgado: por un ssh nuevo (con tope de 40 s) mata los procesos swift/xctest de la VM.
vm_kill_swift() {
  local pid w=0
  "${SSH[@]}" 'Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match "^(swift|swift-test|swift-build|swift-frontend|swiftc|swiftpm-testing-helper|xctest|clang|lld-link)$" -or $_.ProcessName -like "*xctest*" } | Stop-Process -Force' >> "$log" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2> /dev/null && [ "$w" -lt 40 ]; do sleep 1; w=$((w + 1)); done
  kill "$pid" 2> /dev/null
  wait "$pid" 2> /dev/null
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
git ls-files -co --exclude-standard | while IFS= read -r f; do [ -e "$f" ] && [ ! -d "$f" ] && printf '%s\n' "$f"; done > "$list"
n="$(wc -l < "$list" | tr -d ' ')"
COPYFILE_DISABLE=1 tar --no-xattrs -cf "$tarf" -T "$list" >> "$log" 2>&1 || { echo "FICHEROS tar fallo (ver $log)"; exit 3; }
size="$(du -h "$tarf" | cut -f1)"
scp -q -o BatchMode=yes "$tarf" "$HOST:C:/tf-src.tar" >> "$log" 2>&1 || { echo "FICHEROS scp fallo (ver $log)"; exit 3; }
rcmd "New-Item -ItemType Directory -Force $REMOTE_ROOT | Out-Null; tar -xf C:\\tf-src.tar -C $REMOTE_ROOT; exit \$LASTEXITCODE" \
  || { echo "FICHEROS extraccion fallo: $(printf '%s' "$out" | tail -3)"; exit 3; }
echo "FICHEROS $n ficheros ($size) en C:\\tf ($((SECONDS - t0)) s)"

# --- ONNX Runtime (carpeta persistente C:\tf-ort, fuera de git) ---------------------------------------
# Se rellena desde Vendor/win/ort (Tools/win/fetch-ort.sh) solo cuando su VERSION no coincide con la de la VM.
if [ -f Vendor/win/ort/VERSION ]; then
  want="$(cat Vendor/win/ort/VERSION)"
  rcmd "if (Test-Path C:\\tf-ort\\VERSION) { (Get-Content C:\\tf-ort\\VERSION) } else { 'ninguna' }"
  if [ "$out" != "$want" ]; then
    t0=$SECONDS
    rcmd "if (Test-Path C:\\tf-ort) { Remove-Item -Recurse -Force C:\\tf-ort }; New-Item -ItemType Directory -Force C:\\tf-ort | Out-Null" \
      || { echo "ORT   no se pudo preparar C:\\tf-ort: $out"; exit 3; }
    scp -q -r -o BatchMode=yes Vendor/win/ort/arm64 Vendor/win/ort/x64 "$HOST:C:/tf-ort/" >> "$log" 2>&1 \
      && scp -q -o BatchMode=yes Vendor/win/ort/VERSION "$HOST:C:/tf-ort/VERSION" >> "$log" 2>&1 \
      || { echo "ORT   scp a C:\\tf-ort fallo (ver $log)"; exit 3; }
    echo "ORT   $want copiado a C:\\tf-ort ($((SECONDS - t0)) s)"
  fi
fi

# --- WebView2 (carpeta persistente C:\tf-webview2, fuera de git; solo para paquetes WinApp*) ---------------
# Se rellena desde Vendor/win/webview2 (Tools/win/fetch-webview2.sh) solo cuando su VERSION no coincide con la de la VM.
case "$package" in
  WinApp*)
    if [ ! -f Vendor/win/webview2/VERSION ]; then
      echo "WEBV2 falta Vendor/win/webview2: ejecuta Tools/win/fetch-webview2.sh"
      exit 3
    fi
    want="$(cat Vendor/win/webview2/VERSION)"
    rcmd "if (Test-Path C:\\tf-webview2\\VERSION) { (Get-Content C:\\tf-webview2\\VERSION) } else { 'ninguna' }"
    if [ "$out" != "$want" ]; then
      t0=$SECONDS
      rcmd "if (Test-Path C:\\tf-webview2) { Remove-Item -Recurse -Force C:\\tf-webview2 }; New-Item -ItemType Directory -Force C:\\tf-webview2 | Out-Null" \
        || { echo "WEBV2 no se pudo preparar C:\\tf-webview2: $out"; exit 3; }
      scp -q -r -o BatchMode=yes Vendor/win/webview2/include Vendor/win/webview2/x64 "$HOST:C:/tf-webview2/" >> "$log" 2>&1 \
        && scp -q -o BatchMode=yes Vendor/win/webview2/VERSION "$HOST:C:/tf-webview2/VERSION" >> "$log" 2>&1 \
        || { echo "WEBV2 scp a C:\\tf-webview2 fallo (ver $log)"; exit 3; }
      echo "WEBV2 $want copiado a C:\\tf-webview2 ($((SECONDS - t0)) s)"
    fi
    ;;
esac

# --- Tests (--test) ---------------------------------------------------------------------------
if [ "$test" -eq 1 ]; then
  fa=""
  [ -n "$filter" ] && fa=" -Filter '${filter//\'/\'\'}'"
  [ -n "${TF_VM_ENV:-}" ] && fa="$fa -SetEnv '${TF_VM_ENV//\'/\'\'}'"
  narch=1; [ "$arch" = both ] && narch=2
  RCMD_LIMIT=0
  [ "$T_TOTAL" -gt 0 ] && RCMD_LIMIT=$((T_TOTAL * narch + BACKUP_MARGIN))
  rcmd "$PS $REMOTE_SCRIPTS\\test.ps1 -Package $package -Arch $arch$fa -TimeoutSec $T_TOTAL -IdleSec $T_IDLE$cfg"
  rc=$?
  if [ "$RCMD_HUNG" -eq 1 ]; then
    echo "TEST  el ssh no volvio en ${RCMD_LIMIT}s: lo mato e intento matar swift/xctest en la VM"
    vm_kill_swift
    echo "Log completo: $log"
    finish 3
  fi
  if [ "$rc" -eq 255 ] || ! printf '%s\n' "$out" | grep -q '^TF:TEST '; then
    echo "TEST  la VM no devolvio resultado (rc $rc): $(printf '%s' "$out" | tail -3)"
    echo "Log completo: $log"
    finish 3
  fi
  tstatus=0
  tbump() { [ "$1" -gt "$tstatus" ] && tstatus=$1; }
  total_run=0
  while read -r a state secs trc; do
    lines="$(printf '%s\n' "$out" | grep -F "  [$a] " | sed -E "s/^  \[$a\] //" | sed -E 's#C:\\tf\\##' | tr '\\' '/')"
    # Totales: XCTest ("Executed N tests, with S tests skipped and F failures") + swift-testing.
    xct="$(printf '%s\n' "$lines" | grep -E 'Executed [0-9]+ tests?' | tail -1)"
    xn="$(printf '%s\n' "$xct" | sed -nE 's/.*Executed ([0-9]+) tests?.*/\1/p')"
    xs="$(printf '%s\n' "$xct" | sed -nE 's/.*with ([0-9]+) tests? skipped.*/\1/p')"
    stn="$(printf '%s\n' "$lines" | grep -E 'Test run with [0-9]+ tests?' | tail -1 | sed -nE 's/.*Test run with ([0-9]+) tests?.*/\1/p')"
    skips="$(printf '%s\n' "$lines" | grep -E 'Test skipped' | sed -E 's/.*Test skipped( - )?//')"
    nskip=0
    [ -n "$skips" ] && nskip="$(printf '%s\n' "$skips" | wc -l | tr -d ' ')"
    [ "${xs:-0}" -gt "$nskip" ] && nskip="$xs"
    nfail="$(printf '%s\n' "$lines" | grep -cE "Test Case '.*' failed|Test .* failed after" )"
    ntot=$(( ${xn:-0} + ${stn:-0} ))
    npass=$(( ntot - nskip - nfail ))
    [ "$npass" -lt 0 ] && npass=0
    total_run=$((total_run + ntot))
    case "$state" in
      OK)      echo "TEST  $a$rtag OK ${npass} pasados, ${nfail} fallados, ${nskip} saltados (${secs} s)" ;;
      TIMEOUT) tbump 1
               tl="$(printf '%s\n' "$out" | grep -E "^TF:TIMEOUT $a " | head -1 | sed -E 's/^TF:TIMEOUT [^ ]+ //')"
               treason="${tl%% *}"; trest="${tl#* }"; tleft="${trest%% *}"; tlast="${tl#* :: }"
               echo "TEST  $a$rtag TIMEOUT ${npass} pasados, ${nfail} fallados, ${nskip} saltados parciales (${secs} s) (ultimo test: ${tlast}; motivo: ${treason}${tleft:+; procesos vivos tras matar: $tleft})" ;;
      FALLO)   tbump 1; echo "TEST  $a$rtag FALLO ${npass} pasados, ${nfail} fallados, ${nskip} saltados (${secs} s)" ;;
      *)       tbump 2; echo "TEST  $a COMPILACION no se pudo compilar o ejecutar (${secs} s, rc ${trc})" ;;
    esac
    if [ -n "$skips" ]; then
      printf '%s\n' "$skips" | sort | uniq -c | sed -E 's/^ *([0-9]+) (.*)$/      saltado x\1: \2/'
    fi
    if [ "$state" = "FALLO" ]; then
      fl="$(printf '%s\n' "$lines" | grep -E ':[0-9]+: error: |recorded an issue' | grep -vE ':[0-9]+:[0-9]+: error: ' | sort -u | cut -c1-240 | head -15)"
      [ -z "$fl" ] && fl="$(printf '%s\n' "$lines" | tail -5 | cut -c1-240)"
      printf '%s\n' "$fl" | sed 's/^/      /'
    elif [ "$state" = "COMPILA" ]; then
      ce="$(printf '%s\n' "$lines" | grep -E ':[0-9]+:[0-9]+: error: |^error: ' | sort -u | cut -c1-240 | head -15)"
      [ -z "$ce" ] && ce="$(printf '%s\n' "$lines" | tail -6 | cut -c1-240)"
      printf '%s\n' "$ce" | sed 's/^/      /'
    fi
  done < <(printf '%s\n' "$out" | grep -E '^TF:TEST ' | sed -E 's/^TF:TEST //')
  if [ "$tstatus" -eq 0 ] && [ "$total_run" -eq 0 ]; then
    echo "TEST  nada que probar: ninguna prueba se ejecuto${filter:+ (filtro: $filter)}"
    tstatus=2
  fi
  [ "$tstatus" -ne 0 ] && echo "Log completo: $log"
  finish "$tstatus"
fi

# --- Compilacion ------------------------------------------------------------------------------
narch=1; [ "$arch" = both ] && narch=2
RCMD_LIMIT=0
[ "$T_BUILD" -gt 0 ] && RCMD_LIMIT=$((T_BUILD * narch + BACKUP_MARGIN))
rcmd "$PS $REMOTE_SCRIPTS\\build.ps1 -Package $package -Arch $arch -TimeoutSec $T_BUILD"
rc=$?
if [ "$RCMD_HUNG" -eq 1 ]; then
  echo "BUILD el ssh no volvio en ${RCMD_LIMIT}s: lo mato e intento matar swift/xctest en la VM"
  vm_kill_swift
  echo "Log completo: $log"
  finish 3
fi
tf_lines | while read -r kind a status secs; do
  [ "$kind" = "BUILD" ] && echo "BUILD $a$rtag $status (${secs} s)"
done
if [ "$rc" -ne 0 ]; then
  errs="$(printf '%s\n' "$out" | grep -E 'error:' | sed -E 's/^ *\[[a-z0-9]+\] //' | sort -u | cut -c1-220 | head -15)"
  [ -z "$errs" ] && errs="$(printf '%s\n' "$out" | tail -8)"
  printf '%s\n' "$errs" | sed 's/^/      /'
  tf_lines | grep '^TIMEOUT ' | while read -r _ a reason left _; do
    echo "BUILD $a TIMEOUT motivo: $reason; procesos vivos tras matar: $left"
  done
  echo "Log completo: $log"
  finish 2
fi

# --- Helpers de la app ------------------------------------------------------------------------
# ToneForge lanza ejecutables hermanos (tf-separate, de StemKit) que viven en otros paquetes: se compilan
# aqui e install.ps1 los copia junto al .exe (su tabla $helpers manda sobre que se copia). Sin esto cada
# instalacion vaciaba C:\ToneForge\<arch> y dejaba la app sin separador.
helper_pkgs=""
[ "$product" = "ToneForge" ] && helper_pkgs="Packages/StemKit"
for hp in $helper_pkgs; do
  rcmd "$PS $REMOTE_SCRIPTS\\build.ps1 -Package $hp -Arch $arch -TimeoutSec $T_BUILD"
  rc=$?
  if [ "$RCMD_HUNG" -eq 1 ]; then
    echo "BUILD $hp: el ssh no volvio en ${RCMD_LIMIT}s: lo mato e intento matar swift/xctest en la VM"
    vm_kill_swift
    echo "Log completo: $log"
    finish 3
  fi
  tf_lines | while read -r kind a status secs; do
    [ "$kind" = "BUILD" ] && echo "BUILD $a$rtag $status (${secs} s) [$hp]"
  done
  if [ "$rc" -ne 0 ]; then
    errs="$(printf '%s\n' "$out" | grep -E 'error:' | sed -E 's/^ *\[[a-z0-9]+\] //' | sort -u | cut -c1-220 | head -15)"
    [ -z "$errs" ] && errs="$(printf '%s\n' "$out" | tail -8)"
    printf '%s\n' "$errs" | sed 's/^/      /'
    echo "Log completo: $log"
    finish 2
  fi
done

# --- Instalacion ------------------------------------------------------------------------------
rcmd "$PS $REMOTE_SCRIPTS\\install.ps1 -Package $package -Product $product -Arch $arch"
rc=$?
tf_lines | grep '^PE ' | while read -r _ a mach st rest; do echo "PE    $a $mach $st $rest"; done
tf_lines | grep '^HELPER ' | while read -r _ a name st; do echo "HELPER $a $name $st"; done
if [ "$rc" -ne 0 ]; then echo "Log completo: $log"; finish 2; fi

# --- Arranque ---------------------------------------------------------------------------------
if [ "$run" -eq 0 ]; then
  echo "RUN   omitido (--no-run)"
  finish 0
fi

status=0
if [ "$gui" -eq 1 ]; then
  ga=""
  snap_remote=""
  if [ -n "$gui_args" ]; then
    ga=" -ArgsB64 $(printf '%s' "$gui_args" | base64 | tr -d '\n')"
    snap_remote="$(printf '%s\n' "$gui_args" | sed -nE 's/.*--snapshot[ =]+"?([^" ]+)"?.*/\1/p')"
    if [ -n "$snap_remote" ]; then
      rcmd "Remove-Item -Force -ErrorAction SilentlyContinue '${snap_remote//\'/\'\'}'"
    fi
  fi
  if [ -n "$gui_env" ]; then
    ga="$ga -EnvB64 $(printf '%s' "$gui_env" | base64 | tr -d '\n')"
  fi
  rcmd "$PS $REMOTE_SCRIPTS\\gui.ps1 -Product $product -Arch $arch -Wait $GUI_WAIT$ga"
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
    if scp -q -o BatchMode=yes "$HOST:C:/ToneForge/toneforge-$a.log" "Temp/win/toneforge.log" >> "$log" 2>&1; then
      echo "      log de la app: Temp/win/toneforge.log (ultimas lineas)"
      tail -4 Temp/win/toneforge.log | tr -d '\r' | cut -c1-200 | sed 's/^/        /'
    fi
    if scp -q -o BatchMode=yes "$HOST:C:/ToneForge/gui-$a.err" "Temp/win/gui-$a.err" >> "$log" 2>&1 && [ -s "Temp/win/gui-$a.err" ]; then
      echo "      stderr (Temp/win/gui-$a.err):"
      tail -8 "Temp/win/gui-$a.err" | tr -d '\r' | cut -c1-240 | sed 's/^/        /'
    fi
  done
  if [ -n "$snap_remote" ]; then
    snap_name="$(basename "${snap_remote//\\//}")"
    scp -q -o BatchMode=yes "$HOST:${snap_remote//\\//}" "Temp/win/$snap_name" >> "$log" 2>&1 \
      && echo "      snapshot: Temp/win/$snap_name" \
      || { echo "      snapshot: no se genero $snap_remote"; status=1; }
  fi
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
