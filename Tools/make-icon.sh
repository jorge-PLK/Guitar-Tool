#!/bin/bash
# Regenera los PNG del icono de la app a partir de App/Resources/AppIcon.svg.
# Uso: Tools/make-icon.sh
# Rasteriza con AppKit (Tools/make-icon.swift): ImageMagick pierde los degradados del SVG.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="App/Resources/AppIcon.svg"
OUT="App/Resources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$OUT"

# Se rasteriza una vez a 1024 y se reduce desde ahí con sips.
swift Tools/make-icon.swift "$SRC" "$OUT/icon_1024.png" 1024
for S in 16 32 64 128 256 512; do
  sips -z "$S" "$S" "$OUT/icon_1024.png" --out "$OUT/icon_${S}.png" >/dev/null
done
echo "Icono regenerado en $OUT"
