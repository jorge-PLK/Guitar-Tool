#!/bin/bash
# Deja el modelo de pose de Windows en Vendor/models-win/pose/model.onnx (no versionado), de donde lo empaqueta
# FlutterApp/windows/CMakeLists.txt. Origen: Probes/P8-windows/ort-models/out/pose/model.onnx.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
src="$root/Probes/P8-windows/ort-models/out/pose/model.onnx"
dst="$root/Vendor/models-win/pose/model.onnx"
[ -f "$src" ] || { echo "falta $src (Probes/P8-windows/ort-models)"; exit 1; }
mkdir -p "$(dirname "$dst")"
if [ -f "$dst" ] && [ "$(stat -f %z "$src")" = "$(stat -f %z "$dst")" ]; then echo "ya estaba: $dst"; exit 0; fi
cp "$src" "$dst"
echo "copiado: $dst"
