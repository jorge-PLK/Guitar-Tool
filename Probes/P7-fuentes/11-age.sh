#!/bin/zsh
# P7b: restricción de edad. Uso: 11-age.sh <etiqueta> "<consulta>". Sin cookies. Salida en Temp/p7b/age/<etiqueta>/
cd "/Volumes/SSD Mac/Personales/Guitar Tool" || exit 1
Y=Vendor/helpers/yt-dlp
D=Temp/p7b/age/$1
mkdir -p $D
$Y --flat-playlist -J "ytsearch5:$2" > $D/search.json 2> $D/search.err
grep -o '"url": "https://www.youtube.com/watch?v=[^"]*"' $D/search.json | sed 's/"url": "//; s/"$//' > $D/urls.txt
n=0
while read -r u; do
  n=$((n+1))
  $Y -J --no-playlist --js-runtimes deno:Vendor/helpers/deno "$u" > $D/$n.json 2> $D/$n.err
  rc=$?
  age=$(grep -o '"age_limit": [0-9]*' $D/$n.json | head -1)
  title=$(grep -o '"title": "[^"]*"' $D/$n.json | head -1)
  chan=$(grep -o '"channel": "[^"]*"' $D/$n.json | head -1)
  dur=$(grep -o '"duration": [0-9.]*' $D/$n.json | head -1)
  echo "$n | $u | rc=$rc | $age | $title | $chan | $dur | $(grep -E '^(ERROR|WARNING)' $D/$n.err | head -3 | tr '\n' '~')" >> $D/resumen.txt
done < $D/urls.txt
