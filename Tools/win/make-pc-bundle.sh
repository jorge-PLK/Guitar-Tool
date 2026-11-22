#!/bin/bash
# Construye Temp/pc-bundle.zip: lo que el pase del PC (Tools/win/eval/pass.ps1) necesita y git no versiona.
# Se extrae tal cual en la raiz del clon. Se ejecuta en el Mac con la VM (tf-win) libre.
# Contenido (rutas relativas a la raiz del clon):
#   Vendor/win/ort, Vendor/win/webview2          (del Mac)
#   Vendor/helpers-win/x64                       (yt-dlp.exe, deno.exe, ffmpeg.exe de Vendor/helpers/win-x64)
#   Vendor/models-win/{bs_roformer,pose,lead_rhythm}   (de C:\tf-models de la VM, solo lo que usa el pase)
#   Temp/qa-7c/evalB/projects                    (3 temas de prueba, sin .DS_Store)
#   PC-BUNDLE.txt                                (lista y tamanos)
set -u
root="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$root" || exit 3
H="${TF_WIN_HOST:-tf-win}"
st="Temp/pc-bundle-stage"; zip="Temp/pc-bundle.zip"
fail() { echo "FALTA: $1"; exit 3; }
for d in Vendor/win/ort Vendor/win/webview2 Vendor/helpers/win-x64 Temp/qa-7c/evalB/projects; do [ -d "$d" ] || fail "$d (en el Mac)"; done
ssh -o BatchMode=yes -o ConnectTimeout=10 "$H" "echo ok" > /dev/null 2>&1 || fail "ssh a $H no responde"
rm -rf "$st"; mkdir -p "$st/Vendor/win" "$st/Vendor/helpers-win" "$st/Vendor/models-win" "$st/Temp/qa-7c/evalB"
cp -R Vendor/win/ort Vendor/win/webview2 "$st/Vendor/win/" || fail "copia de Vendor/win"
cp -R Vendor/helpers/win-x64 "$st/Vendor/helpers-win/x64" || fail "copia de helpers"
cp -R Temp/qa-7c/evalB/projects "$st/Temp/qa-7c/evalB/projects" || fail "copia de proyectos"
find "$st" -name .DS_Store -delete
for m in bs_roformer pose lead_rhythm; do
  scp -q -r -o BatchMode=yes "$H:C:/tf-models/$m" "$st/Vendor/models-win/" || fail "C:\\tf-models\\$m en $H"
done
for f in bs_roformer/model.onnx bs_roformer/T1_mix_60-85s.wav pose/model.onnx; do [ -f "$st/Vendor/models-win/$f" ] || fail "Vendor/models-win/$f"; done
{ echo "PC-BUNDLE $(date '+%Y-%m-%d %H:%M')"; echo "Extraer en la raiz del clon."; (cd "$st" && find . -maxdepth 4 -mindepth 3 -type d | sort | while read -r d; do printf '%s  %s\n' "$(du -sh "$d" | cut -f1)" "$d"; done); } > "$st/PC-BUNDLE.txt"
rm -f "$zip"; (cd "$st" && zip -q -r "../pc-bundle.zip" .) || fail "zip"
du -h "$zip"; cat "$st/PC-BUNDLE.txt"; rm -rf "$st"
