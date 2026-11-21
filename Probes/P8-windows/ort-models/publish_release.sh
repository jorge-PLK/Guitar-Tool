#!/bin/bash
# Publicaría la release models-win-v1 con los ONNX de Windows. NO SE HA EJECUTADO (decisión de Jorge,
# 19/11/2026: antes quiere mejoras globales). Sin --yes solo enseña lo que haría.
#
#   Probes/P8-windows/ort-models/publish_release.sh [--yes]
#
# Lee out/release_files.txt (lo escribe ops.py: nombre, bytes, sha256, origen), copia cada modelo a
# out/release/<nombre>.onnx, escribe out/release/SHA256SUMS y crea la release como borrador con gh.
# Licencias: BS-RoFormer SW y Lead/Rhythm sin licencia clara (uso personal, no redistribuir en público:
# la release debe ser privada o quedarse fuera); BTC pesos no comerciales; ADTOF CC BY-NC-SA 4.0;
# Beat This! MIT; Basic Pitch Apache-2.0; MoveNet Apache-2.0.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
list="$here/out/release_files.txt"
stage="$here/out/release"
[ -f "$list" ] || { echo "falta $list (ejecuta ops.py)"; exit 2; }
mkdir -p "$stage"
: > "$stage/SHA256SUMS"
tail -n +2 "$list" | while IFS=$'\t' read -r name bytes sha src; do
  cp -f "$src" "$stage/$name"
  printf '%s  %s\n' "$sha" "$name" >> "$stage/SHA256SUMS"
  echo "$name $bytes $sha"
done
cmd=(gh release create models-win-v1 --draft --title "Modelos ONNX para Windows v1"
     --notes-file "$stage/SHA256SUMS" "$stage"/*.onnx "$stage/SHA256SUMS")
if [ "${1:-}" = "--yes" ]; then
  "${cmd[@]}"
else
  echo "no publicado; se ejecutaría: ${cmd[*]}"
fi
