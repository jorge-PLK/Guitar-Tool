#!/bin/zsh
# P7b: lista candidatos de varios temas con tf-fetch (usa la red). Salida en Temp/p7b/<etiqueta>/lista.txt
cd "/Volumes/SSD Mac/Personales/Guitar Tool" || exit 1
BIN=Packages/SourceKit/.build/debug/tf-fetch
typeset -A T
T=(
  t1 https://open.spotify.com/track/4h40ugBk8xtnFGd79AYW8l
  t2 https://open.spotify.com/track/73pG8K7n0bQs2j3m4C21Aw
  t3 https://open.spotify.com/track/7hNAo0GVGEz9z0cetuhKb3
  t4 https://open.spotify.com/track/0x3AlqLLIRL3pRMhmmdcdq
  t5 https://open.spotify.com/track/6zc7lU9FWugn6zRg0yoBwO
)
for k in t1 t2 t3 t4 t5; do
  mkdir -p Temp/p7b/$k
  s=$SECONDS
  $BIN ${T[$k]} --helpers Vendor/helpers --out Temp/p7b/$k > Temp/p7b/$k/lista.txt 2>&1
  echo "tiempo_busqueda_s=$((SECONDS - s))" >> Temp/p7b/$k/lista.txt
done
