# Fuentes externas (mini-spec de la Fase 2b)

Importar un tema pegando un enlace de YouTube o de Spotify. Decisión y alternativas en ADR-008; números en `docs/probes/P7-fuentes.md`. Jorge dio por bueno Opus de oído el 15/11/2026, así que D2 queda firme. Estado: implementada y cerrada el 15/11/2026 (ADR-011).

## Recorrido

1. **Enlace.** Se admiten `youtube.com/watch?v=`, `youtu.be/`, `music.youtube.com/watch?v=`, `open.spotify.com/track/<id>` (con o sin prefijo `intl-xx`) y `spotify:track:<id>`. Listas y álbumes: ver «Listas». Episodios y cualquier otra cosa se rechazan con mensaje.
2. **Metadatos.**
   - Spotify: `GET https://open.spotify.com/embed/track/<id>` y lectura del JSON `__NEXT_DATA__`: título, artistas, duración y carátula (la mayor de las tres). Sin credenciales ni API.
   - YouTube: `yt-dlp -J --no-playlist <url>`: `track` y `artist` si vienen, y si no `title` y `channel`; duración y miniatura.
3. **Candidatos (solo Spotify).** `ytsearch5:<artista> <título>` con `--flat-playlist -J`. Se enseñan los cinco, ordenados por diferencia absoluta de duración con Spotify, cada uno con título, canal, duración y diferencia con signo. Los que quedan a 3 s o menos llevan la marca «cercano» (en P7 los tres correctos estaban entre 0,8 y 3,2 s; el umbral se revisa con la prueba ampliada). La prueba ampliada confirmó el umbral para versiones distintas (correcto más lejano a 2,7 s, incorrecto más cercano a 4,1 s) pero no para directos: un directo oficial quedó a −0,4 s. Por eso los candidatos cuyo título dice «directo», «en directo», «en vivo», «live» o «concierto» llevan además la marca «directo». Regla de Jorge (15/11/2026): se prefiere siempre la versión de estudio, salvo que el enlace pegado sea el de un directo. Si el título del tema en Spotify no dice que es un directo, los candidatos «directo» se enseñan al final de la lista, por detrás de los de estudio aunque su diferencia sea menor, y nunca se proponen en las listas. Si el título de Spotify sí lo dice (mismas palabras), es al revés: los «directo» van primero y son los únicos que se proponen. Ninguno viene preseleccionado: elige siempre Jorge. Con un enlace de YouTube no hay candidatos, solo una confirmación con título, canal y duración.
4. **Descarga.** `yt-dlp -f "bestaudio[acodec=opus]" --no-playlist --js-runtimes deno:<ruta>`, sin recodificar. Si el vídeo no ofrece Opus, se cae a M4A/AAC (`bestaudio[ext=m4a]`) y la hoja lo avisa («Sin Opus: descargado en M4A, agudos hasta ~16 kHz»); el códec queda en `origin.codec`. Decidido por Jorge el 15/11/2026; matiza ADR-008 D2, donde Opus sigue siendo la primera opción.
5. **Conversión.** `ffmpeg -i audio.<webm|m4a> -c:a pcm_s24le audio.wav`, a la frecuencia del original (48 kHz en Opus, 44,1 kHz en M4A) y sin remuestrear. El fichero descargado se borra.
6. **Importación.** El WAV entra por `Library.importSong`, igual que un fichero: queda como `source/original.wav` y de ahí sale `audio/song.wav` a la frecuencia de trabajo. A partir de aquí el tema es uno más de la biblioteca, listo para separar.

Título y artista se pueden corregir en la hoja antes de importar. La descarga y la conversión ocurren en una carpeta temporal que se borra al terminar, al fallar o al cancelar.

## Interfaz

Pantalla Biblioteca (boceto `Main`): el botón «Importar tema» pasa a ser un menú con «Desde fichero…» (lo de hoy) y «Desde enlace…». El segundo abre una hoja con estos estados:

| Estado | Qué se ve |
|---|---|
| Vacío | Campo para pegar el enlace y botón «Continuar» |
| Resolviendo | «Leyendo metadatos…» y, con Spotify, «Buscando en YouTube…» (unos 9 s); se puede cancelar |
| Candidatos | Carátula, título y artista editables; lista de candidatos con la diferencia de duración y la marca «cercano»; enlace para abrir cada uno en el navegador; campo para pegar a mano un enlace de YouTube si ninguno convence |
| Descargando | Barra de progreso con la etapa en curso: descargando (porcentaje de yt-dlp), convirtiendo, importando; botón «Cancelar» |
| Error | Mensaje de la tabla de errores y su acción |

Al terminar la hoja se cierra y el tema aparece en la tabla como «Importado».

Ajustes, apartado «Biblioteca y equipo», bloque nuevo «Fuentes externas»: versión de yt-dlp en uso (embebida o actualizada), de Deno y de ffmpeg; botón «Actualizar yt-dlp» y «Volver a la embebida».

## Errores

| Caso | Cómo se detecta | Qué ve el usuario |
|---|---|---|
| Sin red | Error de URLSession, o yt-dlp con fallo de resolución o conexión | «Sin conexión» y «Reintentar» |
| Enlace no admitido | El análisis del enlace | Qué enlaces se admiten |
| Metadatos de Spotify ilegibles | Falta `__NEXT_DATA__` o no trae título y duración | Aviso, y campo para pegar un enlace de YouTube |
| Restricción de edad | yt-dlp: «Sign in to confirm your age» | «Vídeo con restricción de edad: no se puede descargar sin cuenta»; vuelve a los candidatos. No se usan cookies ni cuentas. Si en el uso real molesta, se añade después un reintento opcional con la sesión del navegador (`--cookies-from-browser`), apagado por defecto (aplazado por Jorge el 15/11/2026) |
| Restricción de región, vídeo privado o retirado | yt-dlp: «not available in your country», «Private video», «Video unavailable» | Motivo, y vuelve a los candidatos |
| Ningún candidato cercano, o búsqueda vacía | Ninguna diferencia de 3 s o menos | Se enseñan igual, con aviso, y el campo para pegar un enlace de YouTube. No se bloquea |
| Sin formato Opus | La lista de formatos de los metadatos no trae Opus | No es un error: se descarga M4A y se avisa en la hoja |
| Sin Opus ni M4A | yt-dlp: «Requested format is not available» | «Este vídeo no ofrece audio descargable»; vuelve a los candidatos |
| yt-dlp roto | Errores de extractor («Unable to extract», fallo de firma o de `nsig`) o salida distinta de 0 sin clasificar. Un HTTP 403 en la descarga se reintenta una vez antes de darlo por roto: en la prueba ampliada apareció uno transitorio | «yt-dlp puede estar desactualizado (versión X)» y «Actualizar y reintentar». Si ya es la última: aviso de que YouTube ha cambiado y de que queda importar el fichero a mano |
| Tema repetido | Nada más leer el enlace, antes de buscar: el identificador de Spotify o el del vídeo ya está en la biblioteca. Al elegir candidato: su `videoID` ya está. Al importar: coincide el SHA-256 | Enlace de un tema: «Ya está en la biblioteca» con título y artista y el botón «Abrir», que cierra la hoja y abre el tema; no se busca ni se descarga. Candidato ya importado: marcado «En la biblioteca» y no elegible. En listas y álbumes: fila «En la biblioteca», sin casilla. Límite: un tema importado desde un fichero, o desde otro vídeo distinto, no se reconoce hasta que coincide el vídeo o el SHA-256 |
| Posible repetido (aviso suave, pedido por Jorge el 15/11/2026) | Ningún identificador coincide, pero hay un tema en la biblioteca con el mismo título y artista una vez normalizados (sin mayúsculas, acentos ni signos; el artista vale si uno contiene al otro, para «Leiva, Robe» frente a «Leiva»). Sin artista en alguno de los dos no hay aviso | No bloquea. Enlace de un tema: franja «Puede que ya lo tengas: título · artista» con «Abrir», y se puede seguir. Listas y álbumes: la fila lleva la marca «Puede que ya lo tengas», conserva su casilla y «Marcar todos» no la marca |
| Fallo de ffmpeg o disco lleno | Salida distinta de 0 | Mensaje con las últimas líneas del error |

Tiempos límite: 15 s para los metadatos, 30 s para la búsqueda y 60 s de descarga sin avance. Cancelar manda SIGTERM y luego SIGKILL, como `SeparationRunner`.

## Datos

`Song` gana un campo opcional `origin` (`SongOrigin`): `kind` (`youtube` o `spotify`), `url` (el enlace pegado), `videoID`, `channel`, `spotifyID`, `album`, `artwork` (ruta relativa, `source/cover.jpg`), `codec`, `ytDlpVersion` e `importedAt`. Es aditivo y opcional: `schemaVersion` sigue en 2 y los proyectos actuales se leen sin migración. El índice de SwiftData no cambia (ya guarda título y artista). `Library.importSong` admite metadatos opcionales (título, artista, origen y fichero de carátula) para no deducir el título del nombre del fichero, y comprueba el duplicado por `videoID`.

## Código

Paquete nuevo **`SourceKit`** (se añade a la lista de `docs/plan.md`, como pasó con ModelKit). No depende de Store: la app hace de puente.

| Pieza | Qué hace |
|---|---|
| `SourceLink` | Analiza el enlace pegado |
| `SpotifyMetadataFetching` → `SpotifyEmbedClient` | Metadatos del embed sobre un `HTTPFetching` inyectable |
| `ProcessRunning` | Lanza un helper, entrega salida y progreso y cancela. Implementación real con `Process` y versión simulada con respuestas grabadas |
| `YtDlpClient` | `info`, `search` y `download` sobre `ProcessRunning`; clasifica el error a partir de stderr (`SourceError`) |
| `CandidateRanker` | Orden por diferencia de duración y marca «cercano» |
| `AudioTranscoder` | ffmpeg → WAV |
| `HelperLocator` | Rutas de los tres helpers; para yt-dlp elige la versión más nueva entre la del bundle y la de Application Support |
| `YtDlpUpdater` | Baja `yt-dlp_macos` y `SHA2-256SUMS` de la última release, verifica y lo instala |
| `SourceImporter` | Orquesta el recorrido y publica el estado para la hoja |
| `tf-fetch` | Ejecutable de desarrollo, no se embebe: hace el recorrido real desde la terminal |

Tests de la puerta, sin red ni helpers: enlaces válidos y rechazados; HTML del embed grabado en P7; JSON de búsqueda grabado; orden y umbral de candidatos; un stderr grabado por cada clase de error; recorrido completo de `SourceImporter` con `ProcessRunning` y `HTTPFetching` simulados; cancelación; elección de versión en `HelperLocator`; SHA incorrecto en `YtDlpUpdater`. En Store: ida y vuelta de `origin`, proyecto v2 sin `origin`, duplicado por `videoID` e importación con metadatos.

La descarga real se comprueba aparte, y con el mismo comando se hace la prueba ampliada:

```
swift run --package-path Packages/SourceKit tf-fetch <enlace> --helpers Vendor/helpers --out Temp/p7b
```

Sin `--pick` lista los candidatos; con `--pick N` descarga y convierte.

## Helpers embebidos

| Helper | Origen | Licencia |
|---|---|---|
| yt-dlp | `yt-dlp_macos` de la release oficial, versión y SHA-256 fijados | Unlicense |
| Deno | `deno-aarch64-apple-darwin.zip` de la release oficial, versión y SHA-256 fijados | MIT |
| ffmpeg | Compilado propio desde el tarball oficial (versión y SHA-256 fijados), mínimo: `--disable-everything --disable-autodetect` más demuxers Matroska/WebM y MOV/MP4, parsers y decodificadores nativos de Opus y AAC, codificador `pcm_s24le`, muxer WAV y protocolo de ficheros. Sin `--enable-gpl` ni `--enable-nonfree` | LGPL 2.1 o posterior |

- `Tools/helpers/fetch.sh` baja y verifica yt-dlp y Deno; `Tools/helpers/build-ffmpeg.sh` compila ffmpeg (solo necesita las herramientas de línea de comandos de Xcode). Los dos dejan el resultado en `Vendor/helpers/`, que no se versiona. Las versiones y sumas viven en `Tools/helpers/versions.env`.
- Una fase de script de `App/project.yml` copia los tres a `Contents/MacOS/` y firma cada uno con la identidad de la app, igual que `tf-separate`. Si falta `Vendor/helpers/`, el build falla nombrando el script que hay que lanzar. Sin notarización ni hardened runtime (ADR-001), así que el JIT de Deno no necesita permisos extra.
- El ffmpeg mínimo se valida una vez contra la conversión de P7: misma duración y diferencia nula frente al WAV de `Temp/p7/out/best-deno/`.
- **Actualización de yt-dlp.** El del bundle es la base. «Actualizar yt-dlp» baja la última release, verifica el SHA-256 y la deja en `Application Support/ToneForge/Helpers/yt-dlp` con un `yt-dlp.json` (versión, suma, fecha). Se usa la más nueva de las dos. Cuando una descarga o una búsqueda falla con error de extractor, la hoja ofrece «Actualizar y reintentar». Deno y ffmpeg solo cambian con una build nueva.

## Listas

Decidido por Jorge el 15/11/2026, dentro de la Fase 2b: al pegar el enlace de una lista de Spotify o de YouTube, la app enseña sus temas y él marca cuáles se descargan y procesan y cuáles se omiten. «Descargar y procesar» es una sola acción: descargar, importar y separar los stems.

**Enlaces.** `open.spotify.com/playlist/<id>`, `spotify:playlist:<id>`, `open.spotify.com/album/<id>`, `spotify:album:<id>` (los álbumes de Spotify entran igual que las listas, pedido por Jorge el 15/11/2026) y `youtube.com/playlist?list=<id>` (también `music.youtube.com`). Un enlace `watch?v=…&list=…` se sigue tratando como un solo vídeo.

**Lectura.**

- Spotify: `GET https://open.spotify.com/embed/playlist/<id>` (o `embed/album/<id>`, misma estructura) y su `__NEXT_DATA__`: nombre de la lista o del álbum y, en `props.pageProps.state.data.entity.trackList`, por tema: `uri`, `title`, `subtitle` (artistas como texto), `duration` en ms e `isExplicit` (comprobado en la prueba ampliada de P7). El embed no declara el total y la lista de prueba dio justo 100 temas: cuando llegan 100, la hoja avisa de que Spotify puede haber cortado la lista.
- YouTube: `yt-dlp --flat-playlist -J <url>`: título, canal, duración e identificador de cada vídeo.

**Recorrido en la hoja** (la misma de «Desde enlace…», que reconoce el tipo de enlace):

| Paso | Qué se ve |
|---|---|
| 1. Temas | Nombre de la lista y tabla con casilla, título, artista y duración. Nada viene marcado. Los temas que ya están en la biblioteca salen como «En la biblioteca», sin casilla. Botones «Marcar todos» y «Ninguno» |
| 2. Candidatos (solo Spotify) | Se busca en YouTube cada tema marcado, uno tras otro, con su progreso. Tabla de revisión: cada tema con su candidato propuesto (el de menor diferencia, solo si es «cercano»), la diferencia de duración y un desplegable con los cinco. Los temas sin candidato cercano quedan «dudosos» y sin propuesta: se elige uno a mano o se omiten. Nada se descarga hasta pulsar «Descargar y procesar» |
| 3. Cola | Un tema tras otro: descargar, convertir, importar y encolar su separación en la cola de `Library`. Progreso por tema y total; «Cancelar» detiene lo que queda y conserva lo ya importado |
| 4. Resumen | Importados, omitidos y fallidos con su motivo; «Reintentar fallidos» |

Con una lista de YouTube no hay paso 2. La propuesta del paso 2 no es una elección en silencio: Jorge la ve entera y la confirma. Si la prueba ampliada dice que el candidato más cercano falla a menudo, la propuesta se quita y se elige siempre a mano.

**Reglas de la cola.**

- La cola vive en `AppModel`, no en la hoja: se puede cerrar la hoja y sigue; al volver a abrir «Desde enlace…» se ve su estado.
- El fallo de un tema no para la cola; va al resumen con el motivo de la tabla de errores.
- Si yt-dlp responde con el aviso de límite («Sign in to confirm you're not a bot», HTTP 429), la cola se detiene, lo dice y ofrece «Reanudar». No se reintenta sola.
- Un error de extractor (yt-dlp roto) detiene la cola y ofrece «Actualizar y reintentar».
- Duplicados: por identificador de Spotify antes de buscar (`Library.project(withSpotifyID:)`, nuevo) y por `videoID` antes de descargar.
- `origin` gana dos campos opcionales: `playlistID` y `playlistName`.

**Código.** En SourceKit: `SourceLink` reconoce listas; `SpotifyEmbedClient.playlist(id:)` y `album(id:)`; `YtDlpClient.playlist(url:)`; `PlaylistImporter`, que lleva los tres pasos sobre `SourceImporter` y publica el estado de cada tema. Tests sin red: embed de lista grabado, JSON de lista de YouTube grabado, propuesta y «dudosos», fallo de un tema sin parar la cola, parada por límite y reanudación, cancelación, duplicados.

## Estimación y condición de paso

De 5 a 8 horas con las listas (de 3 a 5 sin ellas). Fila para la tabla del plan: «2b. Fuentes externas · 5 a 8 · marca el ritmo compilar ffmpeg y probar descargas reales con varios temas»; los acumulados posteriores suben lo mismo.

Condición de paso: pegar un enlace de YouTube y otro de Spotify deja cada tema en la biblioteca listo para separar, sin más paso manual que elegir candidato; pegar una lista o un álbum, marcar parte de sus temas y pulsar «Descargar y procesar» los deja importados y separados; y la prueba ampliada con al menos cinco temas (uno sin subida oficial, uno con el directo dominante y uno largo) queda anotada en `docs/probes/P7-fuentes.md` con cuántos aciertan el candidato correcto.
