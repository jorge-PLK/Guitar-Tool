#!/bin/zsh
# Baja yt-dlp y Deno con las versiones de versions.env, verifica SHA-256 y los deja en Vendor/helpers/.
set -e
ROOT="${0:A:h}/../.."
source "${0:A:h}/versions.env"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
OUT="$ROOT/Vendor/helpers"
WORK="$ROOT/Temp/helpers-fetch"
rm -rf "$WORK"; mkdir -p "$OUT" "$WORK"

check() { # fichero suma_esperada nombre
  local got; got=$(shasum -a 256 "$1" | awk '{print $1}')
  if [ "$got" != "$2" ]; then echo "ERROR: SHA-256 de $3 no coincide (esperada $2, obtenida $got)" >&2; exit 1; fi
  echo "$3 SHA-256 OK"
}

curl -fsSL -A "$UA" -o "$WORK/yt-dlp_macos" "https://github.com/yt-dlp/yt-dlp/releases/download/$YTDLP_VERSION/yt-dlp_macos"
check "$WORK/yt-dlp_macos" "$YTDLP_SHA256" "yt-dlp $YTDLP_VERSION"
cp -f "$WORK/yt-dlp_macos" "$OUT/yt-dlp"

curl -fsSL -A "$UA" -o "$WORK/deno.zip" "https://github.com/denoland/deno/releases/download/v$DENO_VERSION/deno-aarch64-apple-darwin.zip"
check "$WORK/deno.zip" "$DENO_SHA256" "deno $DENO_VERSION"
mkdir -p "$WORK/deno"
unzip -q -o "$WORK/deno.zip" -d "$WORK/deno"
cp -f "$WORK/deno/deno" "$OUT/deno"

chmod +x "$OUT/yt-dlp" "$OUT/deno"
xattr -c "$OUT/yt-dlp" "$OUT/deno" 2>/dev/null || true
rm -rf "$WORK"
echo "Listo: $OUT"
