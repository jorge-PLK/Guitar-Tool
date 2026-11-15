#!/bin/zsh
# P7 paso 2: descarga yt-dlp y deno (aarch64) a Temp/p7/bin y verifica SHA-256.
set -e
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
BIN="${0:A:h}/../../Temp/p7/bin"
mkdir -p "$BIN"; cd "$BIN"

# yt-dlp (macOS universal standalone)
Y=https://github.com/yt-dlp/yt-dlp/releases/latest/download
curl -sSL -A "$UA" -o yt-dlp_macos "$Y/yt-dlp_macos"
curl -sSL -A "$UA" -o SHA2-256SUMS "$Y/SHA2-256SUMS"
want=$(grep -E ' \*?yt-dlp_macos$' SHA2-256SUMS | awk '{print $1}')
got=$(shasum -a 256 yt-dlp_macos | awk '{print $1}')
echo "yt-dlp want=$want got=$got"; [ "$want" = "$got" ] && echo YTDLP_SHA_OK
chmod +x yt-dlp_macos

# deno
D=https://github.com/denoland/deno/releases/latest/download
curl -sSL -A "$UA" -o deno.zip "$D/deno-aarch64-apple-darwin.zip"
curl -sSL -A "$UA" -o deno.zip.sha256sum "$D/deno-aarch64-apple-darwin.zip.sha256sum" || true
cat deno.zip.sha256sum | head -3
got=$(shasum -a 256 deno.zip | awk '{print $1}')
echo "deno got=$got"
