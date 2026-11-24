#!/bin/bash
# Compila AppCoreFFI (producto dinamico de Packages/AppCore) y lo deja donde lo recoge el runner de macOS:
#   FlutterApp/build/macos/Build/Products/<Debug|Release>/toneforge.app/Contents/Frameworks/libAppCoreFFI.dylib
# (TfTextureHost.swift lo busca ahi si no se pasa --core-lib). Se copia TRAS `flutter build`, no desde una fase de Xcode:
# asi el .app de Flutter no depende de que Swift ya este compilado y la copia es explicita y re-firmada (ad hoc).
#
#   Tools/flutter/build-core.sh [debug|release]   compila y copia (la copia se omite si aun no hay .app)
#   TF_CORE_COPY_ONLY=1 Tools/flutter/build-core.sh [cfg]   solo copia (lo usa run.sh tras flutter build)
# Salida: ruta y tamano del dylib. Log: Temp/logs/build-core.log. Codigos: 0 bien, 1 fallo.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
mkdir -p Temp/logs
log="Temp/logs/build-core.log"

cfg="${1:-debug}"
case "$cfg" in
  debug) fcfg="Debug" ;;
  release) fcfg="Release" ;;
  *) echo "uso: build-core.sh [debug|release]"; exit 1 ;;
esac

if [ "${TF_CORE_COPY_ONLY:-0}" != "1" ]; then
  : > "$log"
  if ! swift build --package-path Packages/AppCore --product AppCoreFFI -c "$cfg" >> "$log" 2>&1; then
    echo "swift build fallo (rc!=0); errores:"
    grep -a ': error: ' "$log" | sort -u | head -10 || true
    echo "log: $log"
    exit 1
  fi
fi

bin="$(swift build --package-path Packages/AppCore -c "$cfg" --show-bin-path 2>>"$log")"
dylib="$bin/libAppCoreFFI.dylib"
[ -f "$dylib" ] || { echo "no existe $dylib"; exit 1; }

app="FlutterApp/build/macos/Build/Products/$fcfg/toneforge.app"
final="$dylib"
if [ -d "$app" ]; then
  mkdir -p "$app/Contents/Frameworks"
  cp -f "$dylib" "$app/Contents/Frameworks/libAppCoreFFI.dylib"
  # Copiar al bundle invalida su sello: se re-firma el dylib y el .app (ad hoc, conservando entitlements).
  codesign --force --sign - "$app/Contents/Frameworks/libAppCoreFFI.dylib" >> "$log" 2>&1
  codesign --force --sign - --preserve-metadata=entitlements,requirements,flags,runtime "$app" >> "$log" 2>&1 || {
    echo "codesign del .app fallo (ver $log)"; exit 1; }
  final="$app/Contents/Frameworks/libAppCoreFFI.dylib"
else
  echo "aviso: no hay $app (aun sin flutter build); dylib sin copiar"
fi
echo "AppCoreFFI ($cfg): $final ($(du -h "$final" | cut -f1 | tr -d ' '))"
