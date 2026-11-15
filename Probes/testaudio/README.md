# testaudio: audios de prueba para P4 (stems) y P6 (time-stretch)

## Origen

Multipistas en bruto de la Cambridge MT Multitrack Library (https://www.cambridge-mt.com/ms/mtk/), uso educativo y no comercial:

| Id | Artista | Titulo | BPM |
|----|---------|--------|-----|
| T1 | Ale Lak | Nosso Mundo Deixou De Existir | 125 |
| T2 | Chris Coltraine | Heather Jane | 74 |
| T3 | Robert Hammon | The Elephant | 110 |

No se redistribuyen, por eso `out/` no esta en git.

## Como conseguirlos

Descarga manual desde el navegador (el sitio bloquea clientes automaticos). Elegir la version **Full Multitrack** (WAV 24 bit / 44,1 kHz) y descomprimir en `Probes/testaudio/out/raw/T<n>/`. Opcional y generico: guitarras reamplificadas en `out/raw/T<n>/reamp/` sustituyen a los DI de guitarra en la mezcla (los DI pasan a `di/`).

## Ejecucion

```
uv run --python 3.12 Probes/testaudio/prepare.py              # T1, T2 y T3
uv run --python 3.12 Probes/testaudio/prepare.py --songs T3   # solo una cancion
```

Salidas en `out/<T>/`: `mix.wav`, `stems/<grupo>.wav` (drums, bass, guitar, vocals, piano, other; solo con contenido; `di/` solo existe si hay DI de guitarra), `guitar_parts/<pista>.wav`, `di/<pista>.wav`. Tramos de 30 s para P6 en `out/clips/` (`mix_dense`, `gtr_lead`, `gtr_rhythm`, `backing_noguitar`). `out/manifest.json` recoge asignacion, panorama, ganancias, sonoridad, SHA-256 y el inicio de cada tramo.

## Politica de mezcla

- Asignacion pista -> grupo por nombre de fichero. Los DI de guitarra no entran en la mezcla si hay pista de ampli (o reamp) de esa guitarra; si no la hay, entran (`di_fallback`).
- Panorama (potencia constante; las pistas estereo van tal cual): bombo, caja, bajo, voz principal y overheads/room en el centro; hi-hat +30 %; toms mono repartidos en +-40 %; pareja X / XDT de guitarra a L / R completas; guitarra suelta a +-30 % (alterna lado empezando por la izquierda; Amp1/Amp2 juntas en su posicion); coros a +-50 % (parejas X / XDT a L / R; sueltos alternan empezando por la derecha); synths y otros a +-40 %. En el bajo, DI y ampli se mezclan ambos (la exclusion de DI es solo para guitarras).
- Balance: cada pista se iguala en sonoridad dentro de su grupo (con offsets: KickOut -4 LU, caja inferior -10 LU, hi-hat -8, toms -6, overheads -2, room -6, coros -6) y cada grupo se lleva a un objetivo LUFS: voz -20, bateria -20, bajo -22, guitarras -23, piano -26, otros -28.
- Normalizacion final: una unica ganancia comun para que el pico de la mezcla sea -1 dBFS. Sin limitador ni compresion: `mix = suma exacta de los stems` (el script lo verifica, error < 1e-5). `guitar_parts` suman el stem `guitar`.
