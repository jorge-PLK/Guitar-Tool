#!/bin/zsh
# Baja de la release del repo los modelos que no van en git, verifica SHA-256 y los deja en
# App/Resources/Models/. Usa gh (el repo es privado): en local, la sesión de `gh auth login`;
# en GitHub Actions, GH_TOKEN=${{ github.token }}. Si el fichero ya está y la suma cuadra, no baja nada.
set -e
ROOT="${0:A:h}/../.."
source "${0:A:h}/versions.env"
OUT="$ROOT/App/Resources/Models"
mkdir -p "$OUT"

sum() { shasum -a 256 "$1" | awk '{print $1}'; }

fetch() { # fichero suma_esperada
  local dst="$OUT/$1"
  if [ -f "$dst" ] && [ "$(sum "$dst")" = "$2" ]; then echo "$1 ya está (SHA-256 OK)"; return; fi
  gh release download "$MODELS_RELEASE" -R "$MODELS_REPO" -p "$1" -D "$OUT" --clobber
  local got; got=$(sum "$dst")
  if [ "$got" != "$2" ]; then rm -f "$dst"; echo "ERROR: SHA-256 de $1 no coincide (esperada $2, obtenida $got)" >&2; exit 1; fi
  echo "$1 SHA-256 OK"
}

fetch "$LEADRHYTHM_FILE" "$LEADRHYTHM_SHA256"
echo "Listo: $OUT"
