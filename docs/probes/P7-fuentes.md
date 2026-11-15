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

## Decisión

- P7 superada con un tema. Desbloquea la fase nueva «Fase 2b · Fuentes externas» (ADR-008).
- Opus → WAV con ffmpeg: conserva agudos hasta ~20 kHz frente a ~16 kHz del AAC, y eso pesa en la huella de tono. M4A queda descartado aunque se abra directo con AVFoundation.
- Metadatos de Spotify por la página embed; el audio, siempre de YouTube.
- Plan B si yt-dlp o YouTube fallan: captura del audio del sistema en tiempo real (1x). No se ha probado.

## Sin comprobar

- Más de un tema.
- Vídeos con restricción de edad o de región.
- Temas sin subida oficial.
- Estabilidad en el tiempo frente a cambios de YouTube.
- Juicio de oído: es de Jorge. Ficheros en `Temp/p7/out/best-deno/audio.wav` y `Temp/p7/out/m4a-deno/audio.m4a`.

## Cómo repetirla

1. Poner `yt-dlp_macos`, Deno y ffmpeg en `Temp/p7/` con `03-helpers.sh` (verifica los SHA-256).
2. Leer los metadatos con `01-metadatos.sh` y `02-parse-meta.py`.
3. Buscar candidatos con `04-search.sh` y descargar con `06-download.sh`.
4. Medir formato y duración con `07-probe.sh`, y el corte en agudos con `08-cutoff.py`.
