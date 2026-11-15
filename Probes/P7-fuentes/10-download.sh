#!/bin/zsh
# P7b: descarga el candidato elegido con tf-fetch y mide tiempos. Uso: 10-download.sh <etiqueta> <enlace> <pick>
cd "/Volumes/SSD Mac/Personales/Guitar Tool" || exit 1
BIN=Packages/SourceKit/.build/debug/tf-fetch
k=$1
mkdir -p Temp/p7b/$k
s=$SECONDS
$BIN $2 --helpers Vendor/helpers --out Temp/p7b/$k --pick $3 2>&1 | while IFS= read -r line; do
  echo "[+$((SECONDS - s))s] $line"
done > Temp/p7b/$k/descarga.txt
echo "total_s=$((SECONDS - s))" >> Temp/p7b/$k/descarga.txt
