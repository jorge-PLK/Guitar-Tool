#!/bin/zsh
# Compila un ffmpeg mínimo (WebM/Opus y M4A/AAC -> WAV pcm_s24le, LGPL) para arm64 y lo deja en Vendor/helpers/ffmpeg.
set -e
ROOT="${0:A:h}/../.."
source "${0:A:h}/versions.env"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
OUT="$ROOT/Vendor/helpers"
WORK="$ROOT/Temp/helpers-ffmpeg"
TARBALL="ffmpeg-$FFMPEG_VERSION.tar.xz"
rm -rf "$WORK"; mkdir -p "$OUT" "$WORK"

curl -fsSL -A "$UA" -o "$WORK/$TARBALL" "https://ffmpeg.org/releases/$TARBALL"
got=$(shasum -a 256 "$WORK/$TARBALL" | awk '{print $1}')
if [ "$got" != "$FFMPEG_SHA256" ]; then
  echo "ERROR: SHA-256 de $TARBALL no coincide (esperada $FFMPEG_SHA256, obtenida $got)" >&2; exit 1
fi
echo "$TARBALL SHA-256 OK"

tar -xf "$WORK/$TARBALL" -C "$WORK"
cd "$WORK/ffmpeg-$FFMPEG_VERSION"
# aresample (swresample) lo exige ffmpeg para convertir el formato de muestra (float del decodificador -> s32 del PCM);
# aformat/anull/abuffer/abuffersink son el mínimo del grafo de filtros.
./configure \
  --arch=arm64 --cc="clang -arch arm64" --enable-cross-compile --target-os=darwin \
  --disable-everything --disable-autodetect --disable-doc --disable-ffplay --disable-ffprobe \
  --disable-network --disable-debug --disable-asm \
  --enable-small \
  --enable-protocol=file \
  --enable-demuxer=matroska,mov \
  --enable-parser=opus,aac \
  --enable-decoder=opus,aac \
  --enable-encoder=pcm_s24le \
  --enable-muxer=wav \
  --enable-filter=aresample,aformat,anull,abuffer,abuffersink \
  --extra-cflags="-mmacosx-version-min=15.0" --extra-ldflags="-mmacosx-version-min=15.0"
make -j"$(sysctl -n hw.ncpu)" ffmpeg
cp -f ffmpeg "$OUT/ffmpeg"
strip -x "$OUT/ffmpeg"
chmod +x "$OUT/ffmpeg"
cd "$ROOT"
rm -rf "$WORK"
echo "Listo: $OUT/ffmpeg"
"$OUT/ffmpeg" -version | head -3
