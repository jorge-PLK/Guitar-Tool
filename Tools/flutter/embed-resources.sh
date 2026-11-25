#!/bin/bash
# Fase de copia del Runner de macOS (Run Script en FlutterApp/macos/Runner.xcodeproj): deja en el .app de Flutter lo que
# embebia la app SwiftUI (App/project.yml) y el nucleo (AppCore) busca sin variables de entorno:
#   Contents/MacOS/{yt-dlp,deno,ffmpeg}   ExternalSources.production: carpeta del ejecutable (si no hay TF_HELPERS)
#   Contents/MacOS/tf-separate            Services.swift: junto al ejecutable (si no hay TF_SEPARATE)
#   Contents/Resources/*.zip              ModelStore(bundleResourceDirectory: Bundle.main.resourceURL)
#   Contents/Resources/alphaTab/soundfont/sonivox.sf2   TabTranscribing.swift: recursos de la app (si no hay TF_SOUNDFONT)
# Variables de Xcode: SRCROOT (FlutterApp/macos), TARGET_BUILD_DIR, CONTENTS_FOLDER_PATH, CONFIGURATION,
# EXPANDED_CODE_SIGN_IDENTITY. Incremental: solo copia (y firma) lo que cambio; Xcode firma el bundle despues.
# Fuera de Xcode: SRCROOT=FlutterApp/macos TARGET_BUILD_DIR=... CONTENTS_FOLDER_PATH=toneforge.app/Contents CONFIGURATION=Debug
set -euo pipefail

: "${SRCROOT:?falta SRCROOT (FlutterApp/macos)}"
: "${TARGET_BUILD_DIR:?falta TARGET_BUILD_DIR}"
: "${CONTENTS_FOLDER_PATH:?falta CONTENTS_FOLDER_PATH}"
CONFIGURATION="${CONFIGURATION:-Debug}"
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
[ -n "$IDENTITY" ] || IDENTITY="-"

ROOT="$(cd "$SRCROOT/../.." && pwd)"
CONTENTS="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"
mkdir -p "$MACOS" "$RES"

fail() { echo "error: $*" >&2; exit 1; }

# Copia src -> dst solo si cambio. Imprime "1" si copio. $3 = "link" intenta enlace duro (Debug, ficheros grandes).
copy_if_changed() {
  local src="$1" dst="$2" mode="${3:-copy}"
  if [ -e "$dst" ] && { [ "$src" -ef "$dst" ] || { [ ! "$src" -nt "$dst" ] && [ "$(stat -f %z "$src")" = "$(stat -f %z "$dst")" ]; }; }; then
    return 1
  fi
  rm -f "$dst"
  mkdir -p "$(dirname "$dst")"
  if [ "$mode" = link ] && ln -f "$src" "$dst" 2>/dev/null; then :; else cp -c "$src" "$dst" 2>/dev/null || cp "$src" "$dst"; fi
  return 0
}

sign_exe() {
  codesign --force --sign "$IDENTITY" --timestamp=none "$1"
}

# Ejecutables: el firmado cambia el tamano, asi que se compara con un sello (origen + identidad) fuera del bundle.
STAMPS="${TEMP_DIR:-$TARGET_BUILD_DIR}/tf-embed-stamps"
mkdir -p "$STAMPS"
embed_exe() {
  local src="$1" name="$2" stamp="$STAMPS/$2" want
  want="$(stat -f '%z %m' "$src") $IDENTITY"
  if [ -x "$MACOS/$name" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$want" ]; then return 0; fi
  rm -f "$MACOS/$name"
  cp -c "$src" "$MACOS/$name" 2>/dev/null || cp "$src" "$MACOS/$name"
  chmod +x "$MACOS/$name"
  sign_exe "$MACOS/$name"
  echo "$want" > "$stamp"
  echo "embed: $name"
}

# --- Helpers de fuentes externas ---
HELPERS="$ROOT/Vendor/helpers"
for h in yt-dlp deno ffmpeg; do
  if [ ! -x "$HELPERS/$h" ]; then
    if [ "$h" = ffmpeg ]; then s=Tools/helpers/build-ffmpeg.sh; else s=Tools/helpers/fetch.sh; fi
    fail "falta Vendor/helpers/$h; lanza $s"
  fi
done
for h in yt-dlp deno ffmpeg; do embed_exe "$HELPERS/$h" "$h"; done

# --- tf-separate (release siempre: la velocidad importa; como App/project.yml) ---
PKG="$ROOT/Packages/StemKit"
BIN="$PKG/.build/release/tf-separate"
if [ ! -x "$BIN" ] || [ "$CONFIGURATION" != Debug ]; then
  echo "embed: swift build tf-separate (release)"
  CLEAN=(/usr/bin/env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin")
  [ -z "${DEVELOPER_DIR:-}" ] || CLEAN+=(DEVELOPER_DIR="$DEVELOPER_DIR")
  "${CLEAN[@]}" swift build -c release --package-path "$PKG" --product tf-separate >&2 \
    || fail "no se pudo construir tf-separate (swift build -c release --package-path Packages/StemKit --product tf-separate)"
  BIN="$("${CLEAN[@]}" swift build -c release --package-path "$PKG" --show-bin-path)/tf-separate"
fi
[ -x "$BIN" ] || fail "falta $BIN"
embed_exe "$BIN" tf-separate

# --- Modelos embebidos (zips grandes: enlace duro en Debug si es posible) ---
MODE=copy; [ "$CONFIGURATION" = Debug ] && MODE=link
shopt -s nullglob
zips=("$ROOT"/App/Resources/Models/*.zip)
[ ${#zips[@]} -gt 0 ] || fail "no hay App/Resources/Models/*.zip"
for z in "${zips[@]}"; do
  if copy_if_changed "$z" "$RES/$(basename "$z")" "$MODE"; then echo "embed: $(basename "$z")"; fi
done

# --- Soundfont (el nucleo lo busca en Resources/alphaTab/soundfont/sonivox.sf2) ---
SF="$ROOT/App/Resources/alphaTab/soundfont/sonivox.sf2"
[ -f "$SF" ] || fail "falta App/Resources/alphaTab/soundfont/sonivox.sf2"
if copy_if_changed "$SF" "$RES/alphaTab/soundfont/sonivox.sf2"; then echo "embed: sonivox.sf2"; fi

echo "embed-resources: ok ($CONFIGURATION)"
