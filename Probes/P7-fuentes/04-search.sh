#!/bin/zsh
# P7 paso 3: búsqueda de candidatos (ytsearch5 y YouTube Music), sin descarga.
ROOT="${0:A:h}/../../Temp/p7"
Y="$ROOT/bin/yt-dlp_macos"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
Q="Marea La luna me sabe a poco"
mkdir -p "$ROOT/meta"
echo "== ytsearch5 (sin deno)"
time "$Y" --user-agent "$UA" --flat-playlist -J "ytsearch5:$Q" > "$ROOT/meta/search_yt.json" 2> "$ROOT/meta/search_yt.err"
tail -5 "$ROOT/meta/search_yt.err"
echo "== YouTube Music"
time "$Y" --user-agent "$UA" --flat-playlist -J "https://music.youtube.com/search?q=${Q// /+}" > "$ROOT/meta/search_ytm.json" 2> "$ROOT/meta/search_ytm.err"
tail -5 "$ROOT/meta/search_ytm.err"
