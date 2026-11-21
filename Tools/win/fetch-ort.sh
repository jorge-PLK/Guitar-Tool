#!/bin/bash
# Baja ONNX Runtime 1.32.0 y DirectML para Windows (Fase 7c, paso 7.0) y los extrae a Vendor/win/ort/<arm64|x64>/
# (Vendor/ no se versiona). Verifica el SHA-256 de cada .nupkg contra el fijado aqui.
#
#   Tools/win/fetch-ort.sh
#
# Resultado por arquitectura: onnxruntime.lib, onnxruntime.dll, onnxruntime_providers_shared.dll,
# DirectML.dll, y las licencias en Vendor/win/ort/. Vendor/win/ort/VERSION lo usa Tools/win/build.sh para
# saber si la carpeta persistente de la VM (C:\tf-ort) esta al dia. Idempotente.
set -eu

ORT_VERSION="1.32.0"
ORT_SHA256="a9150bc2992cbbb6722070da9910e1ffa989a8bfc67bdd5bb8e745ca755641db"
DML_VERSION="1.15.4"   # ultima estable de Microsoft.AI.DirectML en NuGet (19/11/2026)
DML_SHA256="4e7cb7ddce8cf837a7a75dc029209b520ca0101470fcdf275c1f49736a3615b9"

root="$(cd "$(dirname "$0")/../.." && pwd)"
dest="$root/Vendor/win/ort"
cache="$dest/.cache"
mkdir -p "$cache"

fetch() { # id version sha
  local id="$1" ver="$2" sha="$3" file="$cache/$1.$2.nupkg"
  if [ ! -f "$file" ] || [ "$(shasum -a 256 "$file" | cut -d' ' -f1)" != "$sha" ]; then
    echo "bajando $id $ver"
    curl -fL --retry 3 -o "$file" "https://api.nuget.org/v3-flatcontainer/$(echo "$id" | tr 'A-Z' 'a-z')/$ver/$(echo "$id" | tr 'A-Z' 'a-z').$ver.nupkg"
  fi
  local got
  got="$(shasum -a 256 "$file" | cut -d' ' -f1)"
  [ "$got" = "$sha" ] || { echo "SHA-256 de $id $ver no coincide: $got (esperado $sha)"; rm -f "$file"; exit 1; }
}

fetch Microsoft.ML.OnnxRuntime "$ORT_VERSION" "$ORT_SHA256"
fetch Microsoft.AI.DirectML "$DML_VERSION" "$DML_SHA256"

ort="$cache/Microsoft.ML.OnnxRuntime.$ORT_VERSION.nupkg"
dml="$cache/Microsoft.AI.DirectML.$DML_VERSION.nupkg"
for pair in "arm64:arm64:arm64-win" "x64:x64:x64-win"; do
  IFS=: read -r a rid dmldir <<< "$pair"
  out="$dest/$a"
  mkdir -p "$out"
  unzip -q -o -j "$ort" "runtimes/win-$rid/native/onnxruntime.lib" "runtimes/win-$rid/native/onnxruntime.dll" \
    "runtimes/win-$rid/native/onnxruntime_providers_shared.dll" -d "$out"
  unzip -q -o -j "$dml" "bin/$dmldir/DirectML.dll" -d "$out"
done
unzip -q -o -j "$ort" LICENSE ThirdPartyNotices.txt -d "$cache/lic-ort"
unzip -q -o -j "$dml" LICENSE.txt ThirdPartyNotices.txt -d "$cache/lic-dml"
cp "$cache/lic-ort/LICENSE" "$dest/LICENSE-onnxruntime.txt"
cp "$cache/lic-ort/ThirdPartyNotices.txt" "$dest/ThirdPartyNotices-onnxruntime.txt"
cp "$cache/lic-dml/LICENSE.txt" "$dest/LICENSE-directml.txt"
cp "$cache/lic-dml/ThirdPartyNotices.txt" "$dest/ThirdPartyNotices-directml.txt"
echo "onnxruntime $ORT_VERSION / directml $DML_VERSION" > "$dest/VERSION"
echo "OK  Vendor/win/ort/{arm64,x64}: $(ls "$dest/arm64" | tr '\n' ' ')"
