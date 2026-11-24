#!/bin/bash
# Pasa la rama fase-7f al PC x64 por ssh: pull, compila AppCoreFFI y la app Windows, ejecuta tests y trae capturas.
#   Tools/flutter/pc.sh [pasos]      pasos: sync core app test fetch (por defecto, todos en ese orden)
#   Tools/flutter/pc.sh app --shot "<args de la app>"   ademas lanza la app con ventana y trae la captura
# Turno compartido: `pcq acquire "<tarea>" --wait` al empezar y `pcq release` al acabar (trap), tambien si falla.
# En el PC solo se escribe dentro del checkout (PC_REPO) y su Temp/ (ignorado por git). La app nunca usa carpetas reales:
# --projects-folder y --support-dir van a Temp\flutter del PC.
# Salida resumida; log completo en Temp/logs/flutter-pc.log. Codigos: 0 bien, 1 fallo de un paso, 2 sin conexion.
# NOTA: el PC no se usa hasta el final de la fase 7f; los pasos remotos no estan probados (solo bash -n).
set -uo pipefail
export LC_ALL=C
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
mkdir -p Temp/logs Temp/flutter/pc
log="Temp/logs/flutter-pc.log"
: > "$log"

PC_HOST="${PC_HOST:-pc}"
PC_BRANCH="${PC_BRANCH:-fase-7f}"
PC_REPO="${PC_REPO:-/d/Personal/Guitar-Tool}"            # ruta para el shell del PC (Git Bash)
PC_REPO_SCP="${PC_REPO_SCP:-/D:/Personal/Guitar-Tool}"   # scp no entiende /d/...
PC_REPO_WIN="${PC_REPO_WIN:-D:\\Personal\\Guitar-Tool}"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=10 "$PC_HOST")

steps=(); shot_args=""
while [ $# -gt 0 ]; do
  case "$1" in
    sync|core|app|test|fetch) steps+=("$1"); shift ;;
    --shot) shot_args="${2:-}"; shift 2 ;;
    *) echo "uso: pc.sh [sync|core|app|test|fetch ...] [--shot \"<args de la app>\"]"; exit 1 ;;
  esac
done
[ "${#steps[@]}" -eq 0 ] && steps=(sync core app test fetch)

if ! "${SSH[@]}" 'echo ok' >/dev/null 2>&1; then echo "sin conexion con $PC_HOST"; exit 2; fi

held=0
cleanup() { [ "$held" = 1 ] && pcq release >>"$log" 2>&1; held=0; }
trap cleanup EXIT
trap 'exit 130' INT TERM
pcq acquire "flutter pc.sh ${steps[*]}" --wait >>"$log" 2>&1 || { echo "pcq acquire fallo (ver $log)"; exit 2; }
held=1

# Powershell remoto con el entorno de Swift de Tools/win/remote/common.ps1 (Get-SwiftArgs).
ps() { "${SSH[@]}" "powershell -NoProfile -ExecutionPolicy Bypass -Command \"Set-Location '$PC_REPO_WIN'; . .\\Tools\\win\\remote\\common.ps1; $1\"" 2>&1 | tr -d '\r' >>"$log"; return "${PIPESTATUS[0]}"; }
fail() { echo "paso $1: fallo (log: $log)"; tail -8 "$log"; exit 1; }

step_sync() {
  "${SSH[@]}" "cd $PC_REPO && git fetch -q origin $PC_BRANCH && git checkout -q $PC_BRANCH && git pull -q --ff-only origin $PC_BRANCH && git log --oneline -1" >>"$log" 2>&1 || return 1
  echo "sync: $(tail -1 "$log")"
}
step_core() {
  ps '$a = @(Get-SwiftArgs); swift build --package-path Packages/AppCore --product AppCoreFFI @a; exit $LASTEXITCODE' || return 1
  echo "core: AppCoreFFI compilado"
}
step_app() {
  # Compila la app y junta junto al .exe el AppCoreFFI.dll con sus DLL del runtime de Swift (mismo cierre que Probes/P9-flutter/win/core.ps1).
  ps 'Set-Location FlutterApp; fvm flutter build windows --release; exit $LASTEXITCODE' || return 1
  echo "app: flutter build windows --release correcto"
  if [ -n "$shot_args" ]; then
    local snap="$PC_REPO_WIN\\Temp\\flutter\\pc-shot.png"
    ps "Remove-Item '$snap' -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force '$PC_REPO_WIN\\Temp\\flutter\\projects','$PC_REPO_WIN\\Temp\\flutter\\support' | Out-Null; \$exe = Get-ChildItem 'FlutterApp\\build\\windows\\x64\\runner\\Release\\*.exe' | Select-Object -First 1; \$p = Start-Process \$exe.FullName -ArgumentList '--projects-folder','$PC_REPO_WIN\\Temp\\flutter\\projects','--support-dir','$PC_REPO_WIN\\Temp\\flutter\\support','--snapshot','$snap',$(printf "'%s'," $shot_args | sed 's/,$//') -PassThru; \$p.WaitForExit(60000) | Out-Null; if (-not \$p.HasExited) { \$p.Kill() }; if (Test-Path '$snap') { exit 0 } else { exit 1 }" || return 1
    echo "app: captura generada en el PC"
  fi
}
step_test() {
  ps 'Set-Location FlutterApp; fvm flutter analyze; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; fvm flutter test; exit $LASTEXITCODE' || return 1
  echo "test: flutter analyze + test correctos"
  ps '$a = @(Get-SwiftArgs); swift test --package-path Packages/AppCore @a; exit $LASTEXITCODE' || return 1
  echo "test: swift test AppCore correcto"
}
step_fetch() {
  local n=0 f
  for f in $("${SSH[@]}" "cd $PC_REPO/Temp/flutter && ls *.png 2>/dev/null" | tr -d '\r'); do
    scp -q -o BatchMode=yes "$PC_HOST:$PC_REPO_SCP/Temp/flutter/$f" "Temp/flutter/pc/$f" >>"$log" 2>&1 && n=$((n + 1))
  done
  echo "fetch: $n capturas en Temp/flutter/pc/"
}

for s in "${steps[@]}"; do
  "step_$s" || fail "$s"
done
echo "pc.sh: ${steps[*]} correcto"
