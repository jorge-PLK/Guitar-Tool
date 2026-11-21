#!/bin/zsh
# Baja los helpers con las versiones de versions.env, verifica SHA-256 y los deja en Vendor/helpers/.
#   Tools/helpers/fetch.sh                       Mac: yt-dlp y Deno (ffmpeg lo compila build-ffmpeg.sh) en Vendor/helpers/
#   Tools/helpers/fetch.sh --platform win-arm64  Windows ARM64: yt-dlp, Deno y ffmpeg en Vendor/helpers/win-arm64/
#   Tools/helpers/fetch.sh --platform win-x64    Windows x64: igual, en Vendor/helpers/win-x64/
#   --dry-run  imprime las URL y las sumas esperadas sin descargar nada
set -e
ROOT="${0:A:h}/../.."
source "${0:A:h}/versions.env"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
PLATFORM=mac
DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --platform) PLATFORM="${2:-}"; shift ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
  esac
  shift
done
case "$PLATFORM" in mac|win-arm64|win-x64) ;; *) echo "--platform debe ser mac, win-arm64 o win-x64" >&2; exit 2 ;; esac

WORK="$ROOT/Temp/helpers-fetch"

check() { # fichero suma_esperada nombre
  local got; got=$(shasum -a 256 "$1" | awk '{print $1}')
  if [ "$got" != "$2" ]; then echo "ERROR: SHA-256 de $3 no coincide (esperada $2, obtenida $got)" >&2; exit 1; fi
  echo "$3 SHA-256 OK"
}

get() { # url destino suma nombre
  if [ "$DRY" -eq 1 ]; then echo "$4: $1 (SHA-256 $3)"; return; fi
  curl -fsSL -A "$UA" -o "$2" "$1"
  check "$2" "$3" "$4"
}

if [ "$DRY" -eq 0 ]; then rm -rf "$WORK"; mkdir -p "$WORK"; fi

if [ "$PLATFORM" = mac ]; then
  OUT="$ROOT/Vendor/helpers"
  [ "$DRY" -eq 0 ] && mkdir -p "$OUT"
  get "https://github.com/yt-dlp/yt-dlp/releases/download/$YTDLP_VERSION/yt-dlp_macos" "$WORK/yt-dlp_macos" "$YTDLP_SHA256" "yt-dlp $YTDLP_VERSION"
  get "https://github.com/denoland/deno/releases/download/v$DENO_VERSION/deno-aarch64-apple-darwin.zip" "$WORK/deno.zip" "$DENO_SHA256" "deno $DENO_VERSION"
  [ "$DRY" -eq 1 ] && exit 0
  cp -f "$WORK/yt-dlp_macos" "$OUT/yt-dlp"
  mkdir -p "$WORK/deno"
  unzip -q -o "$WORK/deno.zip" -d "$WORK/deno"
  cp -f "$WORK/deno/deno" "$OUT/deno"
  chmod +x "$OUT/yt-dlp" "$OUT/deno"
  xattr -c "$OUT/yt-dlp" "$OUT/deno" 2>/dev/null || true
  rm -rf "$WORK"
  echo "Listo: $OUT"
  exit 0
fi

# Windows
if [ "$PLATFORM" = win-arm64 ]; then
  YTDLP_FILE=yt-dlp_arm64.exe; YTDLP_SUM="$YTDLP_WIN_ARM64_SHA256"
  DENO_TRIPLE=aarch64-pc-windows-msvc; DENO_SUM="$DENO_WIN_ARM64_SHA256"
  FF_ARCH=winarm64; FF_SUM="$FFMPEG_WIN_ARM64_SHA256"
else
  YTDLP_FILE=yt-dlp.exe; YTDLP_SUM="$YTDLP_WIN_X64_SHA256"
  DENO_TRIPLE=x86_64-pc-windows-msvc; DENO_SUM="$DENO_WIN_X64_SHA256"
  FF_ARCH=win64; FF_SUM="$FFMPEG_WIN_X64_SHA256"
fi
FF_NAME="ffmpeg-$FFMPEG_WIN_BUILD-$FF_ARCH-lgpl-9.0"
OUT="$ROOT/Vendor/helpers/$PLATFORM"
[ "$DRY" -eq 0 ] && mkdir -p "$OUT"
get "https://github.com/yt-dlp/yt-dlp/releases/download/$YTDLP_VERSION/$YTDLP_FILE" "$WORK/$YTDLP_FILE" "$YTDLP_SUM" "yt-dlp $YTDLP_VERSION ($YTDLP_FILE)"
get "https://github.com/denoland/deno/releases/download/v$DENO_VERSION/deno-$DENO_TRIPLE.zip" "$WORK/deno.zip" "$DENO_SUM" "deno $DENO_VERSION ($DENO_TRIPLE)"
get "https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/download/$FFMPEG_WIN_TAG/$FF_NAME.zip" "$WORK/ffmpeg.zip" "$FF_SUM" "ffmpeg $FFMPEG_WIN_BUILD ($FF_ARCH lgpl)"
[ "$DRY" -eq 1 ] && exit 0
cp -f "$WORK/$YTDLP_FILE" "$OUT/yt-dlp.exe"
unzip -q -o -j "$WORK/deno.zip" deno.exe -d "$OUT"
unzip -q -o -j "$WORK/ffmpeg.zip" "$FF_NAME/bin/ffmpeg.exe" "$FF_NAME/LICENSE.txt" -d "$OUT"
mv -f "$OUT/LICENSE.txt" "$OUT/ffmpeg-LICENSE.txt"
echo "ffmpeg $FFMPEG_WIN_BUILD (BtbN $FFMPEG_WIN_TAG, LGPL): https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/tag/$FFMPEG_WIN_TAG" > "$OUT/ffmpeg-SOURCE.txt"
rm -rf "$WORK"
echo "Listo: $OUT"
