#!/bin/bash
# P6: Apple TimePitch (overlap 8 y 32) frente a Rubber Band R2/R3 en tiempo real.
# Uso: Probes/P6-timepitch/run.sh [--synth] <clip.wav>...
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$DIR/out"

if ! command -v rubberband >/dev/null 2>&1; then
    echo "Falta rubberband: brew install rubberband" >&2
    exit 1
fi
if ! command -v uv >/dev/null 2>&1; then
    echo "Falta uv" >&2
    exit 1
fi

(cd "$DIR/AppleRender" && swift build -c release 2>&1 | tail -20 > "$DIR/out/build.log")
tail -3 "$DIR/out/build.log"

# Rutas de los clips a absolutas antes de lanzar Python
ARGS=()
for a in "$@"; do
    if [ "$a" = "--synth" ]; then ARGS+=("$a"); else ARGS+=("$(cd "$(dirname "$a")" && pwd)/$(basename "$a")"); fi
done

uv run --python 3.12 "$DIR/p6.py" ${ARGS[@]+"${ARGS[@]}"}
