#!/bin/zsh
# Give every WAV under Temp/bench a unique name built from its folder path, so that
# double-clicking in Finder never plays a different file with the same name
# (players cache by file name). Idempotent: files already prefixed are skipped.
#   Temp/bench/platero/sweep/gate-w0.30/157-187s/guitar_C.wav
#   -> Temp/bench/platero/sweep/gate-w0.30/157-187s/sweep_gate-w0.30_157-187s_guitar_C.wav
set -euo pipefail
root="${0:A:h:h}/Temp/bench"
[[ -d "$root" ]] || { echo "no $root"; exit 0; }
n=0
find "$root" -type f -name '*.wav' -print0 | while IFS= read -r -d '' f; do
  dir="${f:h}"
  rel="${dir#$root/}"           # e.g. platero/sweep/gate-w0.30/157-187s
  rel="${rel#*/}"               # drop song folder -> sweep/gate-w0.30/157-187s
  [[ "$rel" == "${dir#$root/}" ]] && rel=""   # file directly in song folder
  prefix="${rel//\//_}"
  base="${f:t}"
  [[ -z "$prefix" || "$base" == "${prefix}_"* || "$base" == CHECK_* ]] && continue
  mv -n "$f" "$dir/${prefix}_$base"
  n=$((n+1))
done
echo "renamed under $root"
