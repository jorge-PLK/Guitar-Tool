#!/bin/bash
# Build + tests de ToneForge con salida resumida (los logs completos van a Temp/logs/).
#
#   Tools/test.sh                     todos los paquetes de Packages/ + build de la app
#                                     → escribe Temp/last-run.txt (lo lee .claude/hooks/commit-gate.sh)
#   Tools/test.sh <Paquete> [Filtro]  un paquete, opcionalmente con `swift test --filter <Filtro>`
#                                     → no escribe last-run.txt
#
# Salida: 0 verde, 1 tests fallidos, 2 errores de compilación o nada que probar.
# La app se compila (no se testea): la lógica y sus tests viven en los paquetes.
# Esquema de la app: TF_SCHEME (por defecto ToneForge).
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 2
mkdir -p Temp/logs

full=1
pkgs=()
filter=""
if [ $# -ge 1 ]; then
  full=0
  pkgs=("$1")
  filter="${2:-}"
  [ -f "Packages/$1/Package.swift" ] || { echo "No existe Packages/$1/Package.swift"; exit 2; }
else
  for p in Packages/*/Package.swift; do
    [ -f "$p" ] || continue
    d="${p%/Package.swift}"
    pkgs+=("${d#Packages/}")
  done
fi

summary=()
status=0   # 0 verde, 1 fallos, 2 compilación
bump() { [ "$1" -gt "$status" ] && status=$1; }

[ "$full" -eq 1 ] && echo "RUNNING $(date '+%Y-%m-%d %H:%M:%S')" > Temp/last-run.txt

# Errores de compilación (no los fallos de XCTest, que también llevan "error: -[").
compile_errors() { grep -E ': error: ' "$1" | grep -vE 'error: -\[' | sort -u | head -15; }

for pkg in "${pkgs[@]}"; do
  log="Temp/logs/$pkg.log"
  args=(test --package-path "Packages/$pkg")
  [ -n "$filter" ] && args+=(--filter "$filter")
  swift "${args[@]}" > "$log" 2>&1
  rc=$?

  xct=$(grep -E 'Executed [0-9]+ tests?' "$log" | tail -1 | sed -E 's/^[[:space:]]+//')
  st=$(grep -E 'Test run with [0-9]+ tests?' "$log" | grep -v 'with 0 tests' | tail -1 | sed -E 's/^[^T]*//')
  totals="${xct}${xct:+${st:+ · }}${st}"

  if [ "$rc" -eq 0 ]; then
    summary+=("OK    $pkg: ${totals:-sin tests}")
  elif [ -n "$totals" ]; then
    bump 1
    summary+=("FALLO $pkg: $totals")
    while IFS= read -r l; do [ -n "$l" ] && summary+=("      $l"); done < <(
      grep -E 'error: -\[|✘ Test .*(failed|recorded an issue)' "$log" | sed -E "s#^$root/##" | sort -u | head -15)
  else
    bump 2
    summary+=("COMPILACIÓN $pkg (rc $rc)")
    errs=$(compile_errors "$log" | sed -E "s#^$root/##")
    [ -z "$errs" ] && errs=$(tail -5 "$log")
    while IFS= read -r l; do [ -n "$l" ] && summary+=("      $l"); done <<< "$errs"
  fi
done

app_built=0
if [ "$full" -eq 1 ]; then
  for proj in App/*.xcodeproj; do
    [ -d "$proj" ] || continue
    log="Temp/logs/App.log"
    xcodebuild -project "$proj" -scheme "${TF_SCHEME:-ToneForge}" -destination 'platform=macOS' \
      -derivedDataPath Temp/DerivedData -quiet build > "$log" 2>&1
    rc=$?
    app_built=1
    if [ "$rc" -eq 0 ]; then
      summary+=("OK    App: build")
    else
      bump 2
      summary+=("COMPILACIÓN App (rc $rc)")
      errs=$(compile_errors "$log" | sed -E "s#^$root/##")
      [ -z "$errs" ] && errs=$(tail -5 "$log")
      while IFS= read -r l; do [ -n "$l" ] && summary+=("      $l"); done <<< "$errs"
    fi
    break
  done
fi

if [ "${#pkgs[@]}" -eq 0 ] && [ "$app_built" -eq 0 ]; then
  echo "Nada que probar: no hay Packages/*/Package.swift ni App/*.xcodeproj."
  [ "$full" -eq 1 ] && echo "DONE Empty" > Temp/last-run.txt
  exit 2
fi

case "$status" in
  0) head="DONE Passed" ;;
  1) head="DONE Failed" ;;
  *) head="DONE CompileError" ;;
esac

{
  echo "$head $(date '+%Y-%m-%d %H:%M:%S')${filter:+ (filtro: $filter)}"
  printf '%s\n' "${summary[@]}"
} | tee Temp/last-print.txt

if [ "$full" -eq 1 ]; then
  cp Temp/last-print.txt Temp/last-run.txt
fi
rm -f Temp/last-print.txt
exit "$status"
