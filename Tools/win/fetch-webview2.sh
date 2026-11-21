#!/bin/bash
# Baja Microsoft.Web.WebView2 1.0.4314.35 (Fase 7c, paso 8, parte 8.0) y deja cabeceras y el loader ESTATICO x64
# en Vendor/win/webview2/ (Vendor/ no se versiona). Verifica el SHA-256 del .nupkg contra el fijado aqui.
#
#   Tools/win/fetch-webview2.sh
#
# Resultado: Vendor/win/webview2/include/{WebView2.h,WebView2EnvironmentOptions.h}, x64/WebView2LoaderStatic.lib,
# licencias y VERSION. Tools/win/build.sh copia la carpeta a C:\tf-webview2 de la VM cuando VERSION cambia;
# WinApp/Package.swift busca ahi cabeceras y lib. Idempotente.
set -eu

WV_VERSION="1.0.4314.35"
WV_SHA256="90778deb1b77e36292828b4b5833c9255c27533f40e0ddd55891ae718944edc4"

root="$(cd "$(dirname "$0")/../.." && pwd)"
dest="$root/Vendor/win/webview2"
cache="$dest/.cache"
mkdir -p "$cache"
file="$cache/Microsoft.Web.WebView2.$WV_VERSION.nupkg"

if [ ! -f "$file" ] || [ "$(shasum -a 256 "$file" | cut -d' ' -f1)" != "$WV_SHA256" ]; then
  echo "bajando Microsoft.Web.WebView2 $WV_VERSION"
  curl -fL --retry 3 -o "$file" "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/$WV_VERSION/microsoft.web.webview2.$WV_VERSION.nupkg"
fi
got="$(shasum -a 256 "$file" | cut -d' ' -f1)"
[ "$got" = "$WV_SHA256" ] || { echo "SHA-256 de WebView2 $WV_VERSION no coincide: $got (esperado $WV_SHA256)"; rm -f "$file"; exit 1; }

mkdir -p "$dest/include" "$dest/x64"
unzip -q -o -j "$file" build/native/include/WebView2.h build/native/include/WebView2EnvironmentOptions.h -d "$dest/include"
unzip -q -o -j "$file" build/native/x64/WebView2LoaderStatic.lib -d "$dest/x64"
unzip -q -o -j "$file" LICENSE.txt -d "$cache/lic" && cp "$cache/lic/LICENSE.txt" "$dest/LICENSE-webview2.txt"
unzip -q -o -j "$file" NOTICE.txt -d "$cache/lic" && cp "$cache/lic/NOTICE.txt" "$dest/NOTICE-webview2.txt"
echo "webview2 $WV_VERSION" > "$dest/VERSION"
echo "OK  Vendor/win/webview2: $(ls "$dest/include" "$dest/x64" | tr '\n' ' ')"
