#!/bin/zsh
# P7 paso 4: descarga sin recodificar. Uso: 06-download.sh <etiqueta> <formato> <js-runtimes|none>
ROOT="${0:A:h}/../../Temp/p7"
Y="$ROOT/bin/yt-dlp_macos"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
VID=4CJwzwOIPAY
LABEL="$1"; FMT="$2"; RT="$3"
OUT="$ROOT/out/$LABEL"; mkdir -p "$OUT"
args=(--user-agent "$UA" -v -f "$FMT" -o "$OUT/audio.%(ext)s" --no-playlist)
if [ "$RT" = none ]; then args+=(--no-js-runtimes); else args+=(--js-runtimes "$RT"); fi
start=$SECONDS
"$Y" "${args[@]}" "https://www.youtube.com/watch?v=$VID" > "$OUT/log.txt" 2>&1
echo "$LABEL rc=$? tiempo=$((SECONDS-start))s"
grep -E 'WARNING|ERROR|player client|PO Token|Sign in|JS runtime|n challenge|Downloading [0-9]+ format|Destination' "$OUT/log.txt" | cut -c1-260 | head -20
ls -la "$OUT" | grep audio
