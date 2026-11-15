#!/bin/zsh
# P7b: listas y álbumes de Spotify por la página embed (solo metadatos). Salida en Temp/p7b/listas/
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
ROOT="${0:A:h}/../.."
OUT="$ROOT/Temp/p7b/listas"
mkdir -p "$OUT"
PLAYLIST=37i9dQZF1DWUNNEvaozpW5
# Álbum: el del tema 7 (Narco) si el embed de tema lo trae; si no, el EP de Narco indicado.
ALBUM=${1:-2Ly1vNk9Det1V3uc4pVU4o}
curl -sS -A "$UA" -o "$OUT/playlist.html" -w "playlist %{http_code} %{size_download}\n" "https://open.spotify.com/embed/playlist/$PLAYLIST"
curl -sS -A "$UA" -o "$OUT/album.html" -w "album %{http_code} %{size_download}\n" "https://open.spotify.com/embed/album/$ALBUM"
curl -sS -A "$UA" -o "$OUT/track7.html" -w "track7 %{http_code} %{size_download}\n" "https://open.spotify.com/embed/track/3t5885yZCdcbWoimoWIp3z"
/usr/bin/python3 -I "${0:A:h}/13-parse-listas.py" "$OUT"
