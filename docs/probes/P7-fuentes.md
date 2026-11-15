# P7 · Fuentes externas

Fecha: 2026-11-15 · Fase 0 (prueba añadida después de la Etapa 1) · Rama `fase-2`

## Objetivo

Comprobar si se puede llegar desde un enlace de Spotify a un fichero de audio local, sin credenciales de Spotify y con yt-dlp. Criterio aprobado: el tema queda como fichero que la app pueda importar, sin pasos manuales fuera de elegir candidato.

## Montaje

- Scripts en `Probes/P7-fuentes/`: `01-metadatos.sh`, `02-parse-meta.py`, `03-helpers.sh`, `04-search.sh`, `06-download.sh`, `07-probe.sh`, `08-cutoff.py`.
- Binarios y audio en `Temp/p7/` (no versionado).
- Tema de prueba: track de Spotify `16taQAqrrfqCwbkbKFr2OH`. Es un solo tema.
- Contexto previo (revisión de repos): spotDL y similares sacan el audio de YouTube, no de Spotify, y todos envuelven yt-dlp + ffmpeg. Se descarta embeber spotDL: arrastra Python y ha tenido dos roturas recientes por dependencias. yt-dlp depreca YouTube sin runtime JS externo desde la 2025.11.12.

## Resultados

Superada con un tema: de enlace a fichero listo en 18-24 s.

### Metadatos de Spotify sin credenciales

- `https://open.spotify.com/embed/track/<id>`: el JSON `__NEXT_DATA__` da título, artistas, duración (267 186 ms), carátula en 3 tamaños, fecha y preview de 30 s. No trae ISRC.
- oEmbed: solo título y miniatura de 300 px. Insuficiente.
- Etiquetas `og:` y `music:` de la página: solo `og:site_name`. Falla.

### Helpers

- yt-dlp 2026.10.26 (`yt-dlp_macos`): 36 MB.
- Deno 2.9.8 `aarch64-apple-darwin`: 78 MB descomprimido (zip de 37 MB).
- SHA-256 verificado contra las sumas de cada release.
- Sin cuarentena; solo el atributo `com.apple.provenance`.

### Búsqueda

`ytsearch5:` con artista + título tarda ~8,8 s. Candidatos, con la duración de Spotify en 267,2 s:

| Vídeo | Qué es | Duración | Diferencia |
|---|---|---|---|
| `4CJwzwOIPAY` | Canal del artista | 268 s | +0,8 s |
| `NMfnLpdwuKA` | | 266 s | −1,2 s |
| `dihPzwpa7_o` | Vídeo con letra | 264 s | −3,2 s |
| `YyjXZ7PsccU` | Directo/medley | 498 s | +230,8 s |
| `pEVoccjl8zo` | Concierto | 159 s | −108,2 s |

Elegido `4CJwzwOIPAY`. La búsqueda en YouTube Music funciona con yt-dlp pero no mejora: resultados mezclados, sin duración ni canal.

### Descarga sin recodificar

| Formato | Tamaño | Muestreo | Canales | Tasa | Duración | Diferencia con Spotify | Apertura |
|---|---|---|---|---|---|---|---|
| Opus/WebM (251) | 4,38 MB | 48 kHz | 2 | ~131 kbps | 267,20 s | +0,015 s | `afinfo` no lo abre (`AudioFileOpenURL failed`); ffmpeg → WAV en 0,52 s |
| M4A/AAC (140) | 4,32 MB | 44,1 kHz | 2 | 128 kbps | 267,186 s | 0 | `afinfo` lo abre directo; a WAV en 0,15 s |

### Corte en agudos

Primera caída de 60 dB respecto al pico y energía por encima de 16 kHz:

| Formato | Corte | Energía > 16 kHz |
|---|---|---|
| Opus | 20,2 kHz | 0,21 % |
| AAC | 15,9 kHz | 0,00003 % |

### Runtime JS

- Sin Deno: descarga en 9-10 s con solo el cliente `visionos` y el aviso `WARNING: [youtube] No supported JavaScript runtime could be found... some formats may be missing`. Para este tema no faltó ningún formato.
- Con Deno: 15 s, clientes `tv samsung` + `visionos`, y descarga el player JS.
- Con `node` como runtime: igual que con Deno (15 s).
- En ningún caso hubo avisos de PO token, «Sign in to confirm» ni límite de velocidad.

## Prueba ampliada (15/11/2026)

Se repitió con siete temas reales de rock español, con `tf-fetch` (ejecutable de desarrollo de `Packages/SourceKit`) y los helpers de `Vendor/helpers/` (yt-dlp 2026.10.26 + Deno). Los scripts nuevos son `09-list.sh`, `10-download.sh`, `11-age.sh`, `12-listas.sh` y `13-parse-listas.py`. Las salidas por tema están en `Temp/p7b/tN/` y el detalle completo en `Temp/p7b/resultados.md` (no versionado).

El criterio de «correcto» fue canal oficial o Topic, o título sin directo, live, cover o karaoke, y diferencia de duración con Spotify de 3 s como máximo. Es decir, se juzgó por canal, título y duración; no se ha escuchado ningún resultado.

| Tema | Caso observado | Primero correcto | Correcto entre los cinco | Códec | Tiempo total |
|---|---|---|---|---|---|
| 1 Extremoduro · Pedrá | con subida oficial, tema largo (1768,1 s) | sí | sí | Opus | 37 s |
| 2 Barricada · No hay tregua | único cercano es un directo; el Topic está a +65,6 s | dudoso | dudoso | sin descarga | 10 s (solo búsqueda) |
| 3 Fito y Fitipaldis · Soldadito marinero | videoclip oficial a −14,1 s; el cercano es un vídeo con letra de terceros | sí (terceros) | sí | Opus | 34 s |
| 4 Los Suaves · Dolores se llamaba Lola | Topic con otra versión (+41,4 y +43,4 s); sin cercanos | no | no | sin descarga | 11 s (solo búsqueda) |
| 5 Leño · Maneras de vivir | con subida oficial (Topic, 2.º) | sí | sí | Opus | 34 s |
| 6 Non Servium · A.C.A.B. | subida del artista (canal «NSA», deducido por el título, no verificado) | sí | sí | Opus | 40 s (fallo 403) + 33 s (reintento) |
| 7 Narco · Mi madre es una yonki | con subida oficial (Topic, +0,0 s) | sí | sí | Opus | 28 s |

**Aciertan el candidato correcto 5 de 7** (temas 1, 3, 5, 6 y 7). El tema 2 es dudoso y no cuenta: la duración de Spotify (178,4 s) coincide con el «Doble Directo '89» oficial, no con el Topic (244 s), así que el enlace puede ser el directo o el Topic otra edición. El tema 4 falla: ningún candidato queda a menos de 36,4 s, y los dos Topic parecen otra edición, aunque no se puede afirmar sin oír. Ninguna descarga cayó a M4A. Los cinco descargados dieron WAV de 48 kHz, 2 canales y 24 bit, con duración a menos de 1,8 s de la de Spotify; el más alejado es el tema 5 (253,06 s frente a 251,3 s, 1,76 s). Los tiempos incluyen una segunda búsqueda de ~9-10 s porque cada ejecución con `--pick` repite la búsqueda; `tf-fetch` no separa descarga y conversión.

### Umbral de 3 s

- Correctos: diferencia máxima 2,7 s (tema 5, vídeo de terceros). Entre los descargados, 1,7 s (tema 5, Topic).
- Incorrectos: mínima 4,1 s (tema 1, el vídeo «letra», que puede ser la misma grabación) y 5,4 s (tema 2). El hueco entre 2,7 s y 4,1 s separa bien las versiones distintas.
- No separa directo de estudio: en el tema 2 el directo oficial está a −0,4 s y es el único «cercano». El umbral no basta; hay que mirar también el título («directo», «live») y el canal.
- Matiz del tema 4: los Topic a +41 s son subida oficial y podrían ser la grabación de estudio; el umbral los marca como no coincidentes.

### Restricción de edad

Probada sin cookies ni cuenta, con `yt-dlp --flat-playlist -J "ytsearch5:<consulta>"` y después `yt-dlp -J --no-playlist` por resultado. Un vídeo de los dos temas probados la tiene: `Yb4tG4Zg7Rs`, «ACAB feat. EVARISTO (Video oficial)», del tema 6. El mensaje literal de yt-dlp empieza así:

    ERROR: [youtube] Yb4tG4Zg7Rs: Sign in to confirm your age. This video may be inappropriate for some users. Use --cookies-from-browser or --cookies for the authentication.

En los dos temas quedaba un candidato de estudio sin restricción: `CNbSZjGNdVY` (NSA, 296 s) en el tema 6, y en el tema 7 los cinco resultados respondieron con `age_limit` 0. El vídeo restringido es otra versión (con Evaristo), así que no bloqueó el flujo. `tf-fetch` lo traduciría a `.ageRestricted` por el texto «Sign in to confirm your age»; está comprobado en `classify`, no ejecutado con ese vídeo. Se detecta, pero no se ha saltado.

### Listas y álbumes de Spotify

Por la página embed (`embed/playlist/<id>` y `embed/album/<id>`), solo metadatos, con `12-listas.sh` y `13-parse-listas.py`; salida en `Temp/p7b/listas/`. Ambas respondieron HTTP 200 con `__NEXT_DATA__`, y los temas están en `props.pageProps.state.data.entity.trackList`.

- Campos por tema: `uri` (`spotify:track:<id>`), `uid`, `title`, `subtitle` (artistas en un texto), `duration` (ms), `isExplicit`, `isNineteenPlus`, `contentRatings`, `isPlayable`, `playabilityReason`, `audioPreview` y `entityType`. Hay identificador y duración, que es lo necesario para comparar candidatos. No hay carátula por tema.
- Lista de prueba («Rock Español», editorial `37i9dQZF1DWUNNEvaozpW5`): 100 temas, sin total declarado ni paginación.
- Álbum de prueba («Mi Madre es una Yonki», Narco, `2Ly1vNk9Det1V3uc4pVU4o`): 4 temas, sin total declarado; parece completo. La duración del primero (280 986 ms) coincide con la del embed de tema.
- El embed de tema no trae el álbum, solo el artista, así que se usó directamente el id del EP.

### Incidencias

- Tema 6, descarga con `--pick 1`: falló a los 40 s con `HTTP Error 403: Forbidden`, que `tf-fetch` devolvió como `extractorBroken`. Con yt-dlp a mano (`-f 251`) el mismo vídeo bajó bien (4,35 MiB), y el reintento con `tf-fetch` funcionó sin cambios (33 s). Es un 403 transitorio de YouTube, no un fallo del código; el fallo de clasificación está en `YtDlpClient.classify` (`Packages/SourceKit/Sources/SourceKit/YtDlpClient.swift`, que no se ha tocado).
- En la prueba manual del tema 6, yt-dlp añadió «Sleeping 5.00 seconds as required by the site».

### Casos pedidos que no quedaron cubiertos

- **Tema sin subida oficial**: no se probó. En los siete temas hay canal del artista o Topic entre los cinco candidatos.
- **Directo dominante claro**: no se probó. Solo el tema 2 se acerca, y es dudoso. El tema 4 se esperaba así y no lo fue: solo el quinto candidato es directo.

La condición de paso de la Fase 2b pedía ambos casos; queda sin cumplir esa parte.

## Decisión

- P7 superada con un tema. Desbloquea la fase nueva «Fase 2b · Fuentes externas» (ADR-008).
- Opus → WAV con ffmpeg: conserva agudos hasta ~20 kHz frente a ~16 kHz del AAC, y eso pesa en la huella de tono. M4A queda descartado aunque se abra directo con AVFoundation.
- Metadatos de Spotify por la página embed; el audio, siempre de YouTube.
- Plan B si yt-dlp o YouTube fallan: captura del audio del sistema en tiempo real (1x). No se ha probado.
- A raíz de la prueba ampliada: si un vídeo no ofrece Opus, se cae a M4A.
- Los candidatos se marcan como «directo» por el título, y se prefiere estudio salvo que el enlace de Spotify sea un directo.
- Un reintento ante HTTP 403 en la descarga.
- Listas y álbumes de Spotify, por el embed, dentro de la Fase 2b.
- Reintento con cookies para la restricción de edad: aplazado.

## Sin comprobar

- Temas sin subida oficial.
- Vídeos con restricción de región. La de edad se detecta, pero no se ha saltado.
- Límite de YouTube ante muchas descargas seguidas.
- Si Spotify corta las listas en 100 temas (la de prueba trajo justo 100, sin total declarado).
- Estabilidad en el tiempo frente a cambios de YouTube.
- Juicio de oído: es de Jorge. Pendiente sobre los cinco WAV de `Temp/p7b/` (`t1`, `t3`, `t5`, `t6b`, `t7`). Opus frente a M4A ya está resuelto: Jorge dio por bueno Opus el 15/11/2026.

## Cómo repetirla

1. Poner `yt-dlp_macos`, Deno y ffmpeg en `Temp/p7/` con `03-helpers.sh` (verifica los SHA-256).
2. Leer los metadatos con `01-metadatos.sh` y `02-parse-meta.py`.
3. Buscar candidatos con `04-search.sh` y descargar con `06-download.sh`.
4. Medir formato y duración con `07-probe.sh`, y el corte en agudos con `08-cutoff.py`.
5. Prueba ampliada: sin `--pick`, `tf-fetch` lista los candidatos; con `--pick N` descarga y convierte:
   `swift run --package-path Packages/SourceKit tf-fetch <enlace> --helpers Vendor/helpers --out Temp/p7b`
6. Scripts 09 a 13 (necesitan `swift build` de `tf-fetch` y `Vendor/helpers/`):
   - `09-list.sh`: lanza `tf-fetch` sin `--pick` sobre cinco temas de Spotify fijos (`t1` a `t5`, escritos en el script) y guarda los candidatos y el tiempo de búsqueda en `Temp/p7b/<tN>/lista.txt`.
   - `10-download.sh <etiqueta> <enlace> <pick>`: descarga con `tf-fetch --pick`, marca cada línea de salida con los segundos transcurridos y anota el total en `Temp/p7b/<etiqueta>/descarga.txt`.
   - `11-age.sh <etiqueta> "<consulta>"`: busca cinco vídeos con yt-dlp, pide `-J` de cada uno sin cookies y resume en `Temp/p7b/age/<etiqueta>/resumen.txt` el código de salida, `age_limit`, título, canal, duración y los primeros avisos o errores. No usa `tf-fetch`.
   - `12-listas.sh [id-de-álbum]`: baja con `curl` el embed de una lista (`37i9dQZF1DWUNNEvaozpW5`), de un álbum (por defecto el EP de Narco) y del tema 7, y llama a `13-parse-listas.py`.
   - `13-parse-listas.py <carpeta>`: no solo extrae `trackList`: localiza `__NEXT_DATA__`, guarda un `*_next.json` por embed e imprime un resumen (campos de `entity`, ruta y claves de la lista de temas, primeros y último, y si hay total declarado).
