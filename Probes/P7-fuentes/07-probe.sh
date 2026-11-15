#!/bin/zsh
# P7 paso 4/5: ffprobe, afinfo y conversión a WAV 44,1 kHz de cada descarga.
ROOT="${0:A:h}/../../Temp/p7/out"
FF=/opt/homebrew/bin
for d in best-deno m4a-deno; do
  f=$(ls "$ROOT/$d"/audio.* | grep -v log)
  echo "=== $d $f"
  $FF/ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,bit_rate,sample_rate,channels:format=duration,bit_rate,format_name -of default=nw=1 "$f"
  echo "-- afinfo"
  afinfo "$f" 2>&1 | head -12
  s=$SECONDS
  /usr/bin/time -p $FF/ffmpeg -v error -y -i "$f" -ar 44100 -ac 2 -c:a pcm_s16le "$ROOT/$d/audio.wav" 2>&1 | grep real
  ls -la "$ROOT/$d/audio.wav" | awk '{print $5, $9}'
done
echo "=== sha equal webm?"; shasum "$ROOT"/best-*/audio.webm | awk '{print $1}' | uniq -c
