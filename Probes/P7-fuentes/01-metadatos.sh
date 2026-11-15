#!/bin/zsh
# P7 paso 1: metadatos de Spotify sin credenciales (embed, oembed, og:).
ID=16taQAqrrfqCwbkbKFr2OH
URL="https://open.spotify.com/track/$ID"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
OUT="${0:A:h}/../../Temp/p7/meta"
mkdir -p "$OUT"
curl -sS -A "$UA" -o "$OUT/embed.html" -w "embed %{http_code} %{size_download}\n" "https://open.spotify.com/embed/track/$ID"
curl -sS -A "$UA" -o "$OUT/oembed.json" -w "oembed %{http_code} %{size_download}\n" "https://open.spotify.com/oembed?url=$URL"
curl -sS -L -A "$UA" -o "$OUT/page.html" -w "page %{http_code} %{size_download}\n" "$URL"
