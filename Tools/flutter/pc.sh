#!/bin/bash
# Pasa la rama fase-7f al PC x64 por ssh: clon propio, compila AppCoreFFI y la app Windows, ejecuta tests y trae capturas.
#   Tools/flutter/pc.sh [pasos]      pasos: sync core app test fetch (por defecto, todos en ese orden)
#   Tools/flutter/pc.sh models       tests con modelo ONNX real, CPU y DirectML (no forma parte del orden por defecto)
#   Tools/flutter/pc.sh app fetch --shot "<args de la app>"   ademas lanza la app en el escritorio de Jorge y trae las capturas
#   Tools/flutter/pc.sh selftest     paso que falla a proposito (comprueba que el codigo de salida llega: debe dar 1)
# Los scripts remotos son Tools/flutter/pc/*.ps1: se suben por scp a <P9>\pc1 y se ejecutan con powershell -File (sin
# cadenas entre comillas que bash expanda). El codigo de salida de cada .ps1 es el del paso.
# En el PC todo vive bajo D:\Personal\Guitar-Tool\Temp\p9 (regla de Jorge): scripts en pc1\, clon de la rama en f7\ (git clone
# propio; el checkout de la 7c, D:\Personal\Guitar-Tool, no se toca), Flutter 3.50.1 y caches de P9. La app nunca usa carpetas
# reales: --projects-folder y --support-dir van a f7\Temp\flutter\shot-* del PC y se recrean vacias en cada --shot.
# Salida resumida; log completo en Temp/logs/flutter-pc.log. Codigos: 0 bien, 1 fallo de un paso, 2 sin conexion.
# Turno compartido: pcq acquire al empezar y pcq release al acabar (trap), tambien si falla.
set -uo pipefail
export LC_ALL=C
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
mkdir -p Temp/logs Temp/flutter/pc
log="Temp/logs/flutter-pc.log"
: > "$log"

PC_HOST="${PC_HOST:-pc}"
PC_BRANCH="${PC_BRANCH:-fase-7f}"
PC_P9_WIN="${PC_P9_WIN:-D:/Personal/Guitar-Tool/Temp/p9}"   # rutas con / : valen para powershell -File y scp
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=10 "$PC_HOST")

steps=(); shot_args=""; models_args=""
while [ $# -gt 0 ]; do
  case "$1" in
    sync|core|app|test|fetch|selftest|models) steps+=("$1"); shift ;;
    --shot) shot_args="${2:-}"; shift 2 ;;
    --provider) models_args+=" -Provider ${2:-both}"; shift 2 ;;
    --only) models_args+=" -Only ${2:-}"; shift 2 ;;
    --timeout) models_args+=" -TimeoutSec ${2:-1500}"; shift 2 ;;
    *) echo "uso: pc.sh [sync|core|app|test|fetch|models ...] [--shot \"<args de la app>\"] [--provider cpu|dml|both] [--only <test>] [--timeout <s>]"; exit 1 ;;
  esac
done
[ "${#steps[@]}" -eq 0 ] && steps=(sync core app test fetch)

if ! "${SSH[@]}" 'echo ok' >/dev/null 2>&1; then echo "sin conexion con $PC_HOST"; exit 2; fi

held=0
cleanup() { [ "$held" = 1 ] && pcq release >>"$log" 2>&1; held=0; }
trap cleanup EXIT
trap 'exit 130' INT TERM
eta=30; for s in "${steps[@]}"; do [ "$s" = models ] && eta=120; done
pcq acquire "flutter pc.sh ${steps[*]}" --eta "$eta" --wait >>"$log" 2>&1 || { echo "pcq acquire fallo (ver $log)"; exit 2; }
held=1

fail() { echo "paso $1: fallo (log: $log)"; tail -8 "$log"; exit 1; }

# Sube los .ps1 (sin esto el PC no tiene los scripts de la rama aun sin commit).
"${SSH[@]}" "mkdir -p /d/Personal/Guitar-Tool/Temp/p9/pc1" >>"$log" 2>&1 || fail upload
scp -q -o BatchMode=yes Tools/flutter/pc/*.ps1 "$PC_HOST:$PC_P9_WIN/pc1/" >>"$log" 2>&1 || fail upload

# rps <script.ps1> [args]: ejecuta el script en el PC; salida al log (sin CR) y las lineas TF: a $last; devuelve su codigo.
last="$(mktemp)"
trap 'rm -f "$last"; cleanup' EXIT
rps() {
  local script="$1"; shift
  echo "=== $script $*" >>"$log"
  "${SSH[@]}" "powershell -NoProfile -ExecutionPolicy Bypass -File $PC_P9_WIN/pc1/$script $*" 2>&1 | tr -d '\r' | tee -a "$log" | grep '^TF:' > "$last"
  return "${PIPESTATUS[0]}"
}
summary() { sed 's/^TF:/  /' "$last"; }

step_sync() { rps sync.ps1 -Branch "$PC_BRANCH" || return 1; echo "sync:"; summary; pose_model || return 1; }
# Modelo de pose en el clon f7 (Vendor/models-win/pose/model.onnx, no versionado): lo empaqueta el CMake de la app.
pose_model() {
  local src=Probes/P8-windows/ort-models/out/pose/model.onnx rc
  [ -f "$src" ] || { echo "pose: falta $src en el Mac (la app saldra sin Seguir la guitarra)"; return 0; }
  upload_fixture "$src" "$PC_P9_WIN/f7/Vendor/models-win/pose/model.onnx"; rc=$?
  [ "$rc" = 1 ] && return 1
  [ "$rc" = 0 ] && echo "pose: modelo subido a f7/Vendor/models-win/pose" || echo "pose: modelo ya estaba en f7"
  return 0
}
step_core() { rps core.ps1 || return 1; echo "core:"; grep -v '^TF:swift' "$last" | sed 's/^TF:/  /'; }
step_app() {
  rps app.ps1 || return 1
  echo "app:"; summary
  if [ -n "$shot_args" ]; then
    local b64; b64="$(printf '%s' "$shot_args" | base64 | tr -d '\n')"
    rps shot.ps1 -ArgsB64 "'$b64'" || { summary; return 1; }
    echo "app --shot:"; summary
  fi
}
step_test() { rps test.ps1 || return 1; echo "test:"; summary; }
# models: tests con inferencia real (TF_MODEL_TESTS=1) sobre el clon f7, CPU y DirectML, de uno en uno (PC-3).
#   pc.sh models [--provider cpu|dml|both] [--only <subcadena del test>] [--timeout <s por test>]
# Fixtures de audio T1-T3/Platero que los tests pesados leen del repo y no estan versionados (Probes/**/out, ~/Music): se suben
# por scp al clon f7 del PC (Platero a Vendor/models-win/platero), solo si falta o el tamano difiere (~2 GB la primera vez).
upload_fixture() {   # upload_fixture <ruta local> <destino Windows con />; devuelve 0 si lo subio, 3 si ya estaba
  local src="$1" dst="$2" size rsize
  size="$(stat -f %z "$src")"
  rsize="$("${SSH[@]}" "stat -c %s '/d/${dst#D:/}' 2>/dev/null" </dev/null | tr -d '\r')"
  [ "$rsize" = "$size" ] && return 3
  "${SSH[@]}" "mkdir -p \"\$(dirname '/d/${dst#D:/}')\"" </dev/null >>"$log" 2>&1
  scp -q -o BatchMode=yes "$src" "$PC_HOST:$dst" </dev/null >>"$log" 2>&1 || { echo "scp fallo: $src"; return 1; }
  return 0
}
models_fixtures() {
  local f rc n=0 up=0 list x k
  local mus="$HOME/Music/ToneForge/El roce de tu cuerpo - Platero Y Tu/stems/guitar.wav"
  local p4=Probes/P4-modelos t=Probes/testaudio/out s=Probes/P4-modelos/bs_roformer_sw/out/conv/coremlpub_cpu_gpu
  list="$(
    for x in T1 T2 T3; do echo "$t/$x/mix.wav"; for k in bass guitar other piano; do echo "$s/$x/$k.wav"; done; done
    echo "$s/T1/drums.wav"
    ls "$t"/T1/guitar_parts/*.wav "$p4"/adtof/out/act/torch/T?.npy "$p4"/adtof/out/hits/torch/T1/*.txt \
       "$p4"/btc/out/lab/*/T?_stems.lab "$p4"/beat_this/out/beats/coreml_comm/*.txt
  )"
  while IFS= read -r f; do
    [ -f "$f" ] || { echo "falta en el Mac: $f"; return 1; }
    n=$((n + 1)); upload_fixture "$f" "$PC_P9_WIN/f7/$f"; rc=$?
    [ "$rc" = 0 ] && up=$((up + 1)); [ "$rc" = 1 ] && return 1
  done <<< "$list"
  n=$((n + 1)); upload_fixture "$mus" "D:/Personal/Guitar-Tool/Vendor/models-win/platero/guitar.wav"; rc=$?
  [ "$rc" = 0 ] && up=$((up + 1)); [ "$rc" = 1 ] && return 1
  echo "fixtures: $n ficheros, $up subidos"
}
# Los .swift de Packages/ modificados y sin commit se copian al clon f7 (sync solo trae lo commiteado); el siguiente sync los pisa.
models_overlay() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    scp -q -o BatchMode=yes "$f" "$PC_HOST:$PC_P9_WIN/f7/$f" </dev/null >>"$log" 2>&1 || { echo "scp fallo: $f"; return 1; }
  done < <(git diff --name-only HEAD -- 'Packages/*.swift')
}
step_models() { models_overlay || return 1; models_fixtures || return 1; rps models.ps1 $models_args || { summary; return 1; }; echo "models:"; summary; }
step_selftest() { rps selftest.ps1 -Code "${PC_SELFTEST_CODE:-1}" || return 1; }
step_fetch() {
  local n=0 f
  for f in desktop.png app-snapshot.png; do
    scp -q -o BatchMode=yes "$PC_HOST:$PC_P9_WIN/f7/Temp/flutter/$f" "Temp/flutter/pc/$f" >>"$log" 2>&1 && n=$((n + 1))
  done
  echo "fetch: $n capturas en Temp/flutter/pc/"
  [ "$n" -gt 0 ]
}

for s in "${steps[@]}"; do
  "step_$s" || fail "$s"
done
echo "pc.sh: ${steps[*]} correcto"
