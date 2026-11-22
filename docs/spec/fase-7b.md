# Retoques de interfaz (mini-spec de la Fase 7b)

Rama `fase-7b` desde `main` (Fases 5c y 7 ya cerradas allí). Lista de Jorge del 17/11/2026 (`docs/plan.md`, «Fase 7b»), numerada como allí. Decidido con Jorge el 17/11 y, las dudas de la mini-spec, el 18/11/2026.

## Condición de paso

Los diez puntos comprobados por Jorge en la app (con una copia de los proyectos), `Tools/test.sh` en verde y las capturas de Biblioteca (las dos vistas, el popup con resultados y con error), barra lateral con tema seleccionado, página del tema, Grabar con el visor de toma y Ajustes revisadas por el orquestador.

## Biblioteca

**1. Sin cabecera de contadores.** Fuera `stat("Temas"/"Tomas grabadas"/"Vídeos exportados")` (`LibraryView`) y lo que solo la alimentaba (`AppModel.recordedTakes`, `exportedVideos`). Prueba: captura.

**2. Buscador de temas.** Campo en la cabecera de Biblioteca que filtra mientras se escribe, por título y artista.
- Sin distinguir mayúsculas ni acentos; cada palabra de la consulta tiene que aparecer en el título o en el artista (pueden repartirse: «metallica one» encuentra *One* de Metallica). Vacío: todos. No se recuerda entre arranques.
- Vale para las dos vistas (punto 5). Sin coincidencias: «Ningún tema coincide con «…»».
- Lógica pura en Store (`LibraryFilter.matches(title:artist:query:)`). Pruebas: mayúsculas, acentos («cancion» → «Canción»), palabras repartidas entre título y artista, palabra que no está → fuera, consulta con espacios de sobra, vacía.

**3. Popup «Importar tema».** El botón deja de ser menú y abre un popup con un campo («Pega un enlace o busca en Spotify»), «Importar» (botón por defecto, ↩), «Importar fichero…» (el `NSOpenPanel` de hoy) y Cancelar (Esc).
- Qué es enlace (`ImportQuery.classify`, en SourceKit): texto recortado que es URL `http(s)` con host, una URI `spotify:`, o que empieza por `www.`, `youtube.com`, `youtu.be`, `music.youtube.com` u `open.spotify.com` (se le antepone `https://`). Lo demás es búsqueda. Vacío: «Importar» desactivado.
- Enlace → el flujo de enlace de hoy (`LinkImportSheet`/`SourceImporter`), dentro del mismo popup o sustituyéndolo, sin cambiar sus pasos.
- Pruebas de `classify`: URL de YouTube, de Spotify (con y sin esquema), `spotify:track:…`, texto con espacios, texto que contiene un punto pero no es enlace («AC/DC T.N.T.»), vacío.

**4. Búsqueda en Spotify.** Si lo escrito no es enlace, «Importar» busca en Spotify y muestra 10 resultados debajo del campo.
- Cada fila: carátula pequeña, título, artistas, álbum y año, duración (m:ss); botón ▶ «Oír en Spotify», que abre `spotify:track:<id>` en su app (si ninguna app abre `spotify:`, `https://open.spotify.com/track/<id>` en el navegador); y «Elegir», que lanza el flujo de enlace con `https://open.spotify.com/track/<id>` (el importador de enlaces de Spotify de la Fase 2b hace el resto).
- Mientras busca: indicador en el campo. Sin resultados: «Spotify no ha encontrado nada para «…»».
- **Clave** (decidido el 17/11): `SPOTIFY_CLIENT_ID` y `SPOTIFY_CLIENT_SECRET`. Se lee `<support dir>/.env`; si no existe, el del directorio de soporte por defecto (`~/Library/Application Support/ToneForge/.env`); después, variable a variable, el entorno del proceso manda sobre el fichero. Formato `.env`: `CLAVE=valor`, líneas vacías y `#` ignoradas, `export ` opcional, comillas simples o dobles quitadas, espacios alrededor de `=` recortados. Se lee al buscar por primera vez (y otra vez tras un error de clave, para no obligar a reiniciar si Jorge la corrige).
- **Token:** client credentials (`POST https://accounts.spotify.com/api/token`, `grant_type=client_credentials`, autenticación Basic). Solo en memoria; se renueva al caducar (`expires_in` menos 60 s de margen) o con un 401, reintentando la búsqueda una sola vez. Búsqueda: `GET https://api.spotify.com/v1/search?type=track&limit=10&q=…`.
- **Errores, sin bloquear nada:** sin clave → «Búsqueda en Spotify no disponible: falta la clave (.env)»; 401 tras renovar o 403 → «Spotify ha rechazado la clave»; 429 → «Spotify pide esperar N s»; red → «Sin conexión con Spotify». El aviso va en una línea bajo el campo; el campo sigue aceptando enlaces y «Importar fichero» sigue activo.
- **Secretos:** ni el id ni el secret ni el token se escriben en logs, mensajes de error, `Temp/` ni capturas; los errores no incluyen el cuerpo de la respuesta del token. Las pruebas usan credenciales falsas y un `HTTPFetching` simulado: ningún test llama a Spotify.
- Código en SourceKit, con el patrón protocolo + implementación real + simulada: `DotEnv.parse`, `SpotifyCredentials.load(supportDir:defaultSupportDir:environment:)`, `SpotifyTokenProvider` (actor, reloj inyectable), `SpotifySearchClient: SpotifySearching` → `[SpotifyTrackResult]` (`id`, `name`, `artists`, `album`, `year?`, `durationMs`, `imageURL?`), `SpotifySearchError` (`missingCredentials`, `rejected(status)`, `rateLimited(retryAfter)`, `network`, `badResponse`). `HTTPFetching` se amplía para POST con cabeceras si hace falta.
- Pruebas: parseo de `.env` (comentarios, `export`, comillas, espacios, línea sin `=`); precedencia (entorno > `<support dir>/.env` > el por defecto; fichero del support dir ausente → el por defecto); token reutilizado antes de caducar y pedido otra vez después (reloj simulado); 401 → token nuevo y un solo reintento; 401 dos veces → `rejected(401)`; 403 → `rejected(403)` sin reintento; 429 con `Retry-After`; parseo de una respuesta de búsqueda guardada como fixture (con y sin imagen, varios artistas, fecha solo con año); la consulta va codificada en la URL; el mensaje de error no contiene el secret.

**5. Vista por tema y por artista.** Selector «Temas | Artistas» en la cabecera.
- Por artista: un grupo por artista con su nombre y número de temas; dentro, temas por título. Se agrupa sin distinguir mayúsculas, acentos ni espacios de los extremos, y se muestra la primera grafía encontrada. Orden alfabético local; «Sin artista» al final.
- La vista elegida se recuerda entre arranques (Jorge, 18/11).
- Lógica de agrupado pura en Store, con pruebas: «Metallica» y «metallica » en un grupo, orden con acentos, sin artista al final, filtro del punto 2 aplicado antes de agrupar.

**6. Seleccionar, barra lateral y página del tema.**
- En cada fila, «Abrir» desaparece y aparece un botón «Mostrar en Finder». **Pulsar la fila la selecciona** (sin botón «Seleccionar»; Jorge, 18/11, tras probarla): fija el tema de trabajo (`backingTarget`) como hoy `open`, pero **sin** ir a su página; Biblioteca sigue a la vista. Fila seleccionada con borde/fondo verde; al pasar el ratón, tinte del naranja de acento (seleccionada manda el verde). Los botones de la fila (lápiz, Finder, menú, papelera) no seleccionan. El menú de la fila conserva el resto (Limpiar, Eliminar…).
- Con tema seleccionado, la barra lateral muestra encima de la tarjeta del dispositivo, bajo «Ajustes», una tarjeta con título (14, seminegrita) y artista (12, atenuado), una línea cada uno; «Ajustes» sube lo que haga falta. Sin tema (al abrir la app: la selección no se recuerda) la barra queda como hoy.
- Si un texto no cabe, se trunca con «…»; al pasar el ratón, la línea que no cabe se desplaza (unos 30 pt/s) hasta verse entera y vuelve al salir.
- Al pulsar la tarjeta: Biblioteca con la página del tema (`ProjectDetailView`), con Mostrar en Finder, Eliminar y una lista nueva **«Grabaciones»**: por parte, sus tomas (número, fecha, duración, mejor ★, vídeo sí/no, punches), cada una con ▶ «Ver toma» (el visor del punto 9) y «Eliminar» con confirmación (Jorge, 18/11). La lista es una vista propia (`ProjectRecordingsView(detail:)`) que hace la parte C; el orquestador la coloca en `ProjectDetailView`. La tarjeta se marca activa mientras su página está a la vista.
- Eliminar el tema seleccionado (desde la fila o la página) quita la selección.
- Pruebas: capturas (barra con título corto y con título largo truncado; página con grabaciones). El desplazamiento al pasar el ratón lo ve Jorge.

**6b. Corregir título y artista desde la lista** (Jorge, 18/11). Cada fila gana un botón con icono de lápiz (junto al de Finder) que abre una hoja con «Título» y «Artista», el botón de intercambiarlos, Guardar y Cancelar: lo mismo que el lápiz de la página del tema (`AppModel.updateSongInfo`), que se queda. Vale en la vista Temas y dentro de un artista.

**6c. Vista Artistas en recuadros** (Jorge, 18/11; sustituye a los grupos del punto 5):
- Cuadrícula adaptable de recuadros: foto cuadrada con esquinas redondeadas, nombre debajo (truncado) y «N temas». Orden y agrupado como en el punto 5; «Sin artista» al final, con icono genérico.
- Al pulsar un recuadro: la lista de Temas solo de ese artista, con «‹ Artistas» y su nombre arriba; la flecha vuelve a la cuadrícula. Cambiar a Temas y volver a Artistas deja siempre la cuadrícula completa al principio (el artista abierto no se recuerda; el modo Temas/Artistas sí).
- Buscador: en la cuadrícula salen los artistas con algún tema que pase el filtro del punto 2; dentro de un artista, filtra sus temas.
- **Foto de Spotify** (Jorge, 18/11), con la misma clave y token del punto 4: `GET /v1/search?type=artist&limit=5&q=<nombre>`, y vale solo el resultado cuyo nombre coincide con el del artista sin mayúsculas ni acentos; de sus imágenes, la menor de al menos 160 px (si ninguna llega, la mayor). Se guarda en `<support dir>/artists/` (nombre de fichero derivado del nombre plegado) y no se vuelve a pedir. Sin coincidencia: se apunta y no se reintenta en 7 días. Sin clave, sin red o error: iniciales sobre un color estable derivado del nombre, sin aviso, y se reintenta en el siguiente arranque. Pocas peticiones a la vez (2) y solo de los recuadros visibles. Renombrar un artista (6b) pide la foto del nombre nuevo.
- Pruebas: elección de la coincidencia exacta frente a otros resultados, elección de imagen por tamaño, caché (no repite petición; la negativa caduca a los 7 días con reloj simulado), sin clave → sin petición; todo con `HTTPSending` simulado.

## Backing track

**7. Alargar o encoger una sección en el modo expandido.** Arrastrar un borde de sección con los acordes expandidos tiene que comportarse igual que plegado: el borde sigue al puntero, con el mismo imán, las reglas del punto 8 y se guarda al soltar. Lo primero es reproducir el fallo y explicar la causa (coordenadas del gesto en la vista expandida, vista que se rehace durante el arrastre, gesto que compite con el de la franja…), y dejar una prueba que falle antes del arreglo. Para que se pueda probar, la cuenta del arrastre (posición → tiempo en cada modo, borde inicial, imán, límites) sale de las vistas a un tipo puro, que usan los dos modos, con pruebas en su paquete.

**8. Sin secciones dentro de otras; empujar encoge a la vecina.** Reglas en `SectionEditor` (Store), que aplican el arrastre, las teclas (`nudgeEdge`) y el marcado:
- **Crear** (arrastre en la franja o «Marcar»): solo en hueco libre. No se puede crear una sección dentro de otra (Jorge, 18/11): si el arrastre empieza dentro de una sección no se crea nada; si empieza en un hueco y entra en una sección, se queda en su borde. Más corta que `minLength` → nada. Un rango igual al de una existente sigue alternando su solo. `mark` deja de partir secciones.
- **Empujar:** al llevar el borde de A contra B, el borde de B que toca se mueve con él y B se encoge, hasta `minLength`; ahí el arrastre se para. Solo se encoge la vecina inmediata, no hay cascada. Si B es un solo, el arrastre se para en su borde (decidido el 17/11). Un solo sí empuja y encoge a una sección normal: se está modificando de forma directa.
- **Separar:** al retirar el borde de A de B, B no le sigue; queda un hueco (Jorge, 18/11).
- Pruebas (`SectionEditorTests`): crear en hueco; crear empezando dentro → nada; crear cruzando una vecina → recortada a su borde; empujar encoge a la vecina; empujar hasta `minLength` → para; empujar contra un solo → para en su borde; un solo empuja a una normal; sin cascada a la tercera; separar deja hueco; teclas con las mismas reglas; ningún resultado con solapes ni secciones anidadas (propiedad comprobada en todas las pruebas).

## Grabar

**9. Ver las tomas hechas.** Cada toma de la lista de tomas de Grabar gana ▶ «Ver toma», que abre un visor con su vídeo y su audio procesado sincronizados (`TakePreview` de la Fase 6: `processed.wav`, vídeo con su desfase y punches), con reproducir/pausa, barra de posición y cerrar.
- El visor es una vista reutilizable (`TakeViewer`), que usan Grabar y la página del tema (punto 6).
- Suena con el backing, con un botón para silenciarlo (Jorge, 18/11): se reutiliza el camino del montaje (un plan de una sola parte en plano único, sin fundidos ni rótulo) para que audio, backing y vídeo vayan juntos por construcción.
- En el visor, las mismas acciones que ya tiene la fila (marcar como mejor y eliminar) para reevaluarla sin cerrarlo; sin «Descartar» (Jorge, 18/11: `Take.discarded` sigue siendo solo de la limpieza).
- No se abre grabando; al abrirlo se para el transporte de Grabar. Toma sin vídeo: solo audio, con el recuadro en negro.
- Pruebas: captura del visor; la sincronía la juzga Jorge en una toma real.

## Ajustes

**10. «Biblioteca» sin guitarras.** El apartado «Biblioteca y equipo» pasa a «Biblioteca» y pierde las guitarras del perfil de equipo.
- Fuera de la interfaz (`SettingsView` guitarras, `GuitarDraft`, `GuitarEditor`; `AppModel.upsertGuitar`/`deleteGuitar`) y del modelo de datos (`OwnedGuitar`, `PickupType`, `EquipmentProfile.guitars`, `Take.guitarId`), decidido el 17/11. Lo de audio del perfil (dispositivos, canales, latencia, master, frecuencia) no se toca.
- Migración: los ficheros viejos se siguen leyendo (la clave sobrante se ignora) y se escriben sin ella al guardar. Sin subir `currentSchemaVersion`: quitar un opcional no rompe a un binario anterior.
- Pruebas: un `profile.json` con guitarras se lee y se reescribe sin ellas, con audio intacto; un `project.json` con `guitarId` en las tomas se abre y se guarda sin él; captura de Ajustes.
- La fila «Biblioteca y equipo» de «Ajustes» en esta spec se corrige al cerrar la fase. Si la Etapa 2 necesita guitarras (calibración del DI por guitarra), vuelven allí con su propio diseño.

## Datos

Solo se quita lo del punto 10; lo demás no toca el formato. La regla de copia aislada sigue: la app de esta rama se prueba con `--projects-folder` y `--support-dir` sobre copias, nunca con `~/Music/ToneForge`. Con `--support-dir` apuntando a una copia sin `.env`, la clave sale del directorio de soporte por defecto (el orden del punto 4).

## Código

| Parte | Puntos | Qué | Agente |
|---|---|---|---|
| A. Secciones | 7, 8 | `SectionEditor` y sus pruebas; tipo puro del arrastre; `SectionBoxes`, `SectionGridBoxes`, `BackingTimeline`, `StudySession` | `tf-engineer` |
| B. Biblioteca y Spotify | 1–6 | SourceKit: `ImportQuery`, `DotEnv`, `SpotifyCredentials`, `SpotifyTokenProvider`, `SpotifySearchClient` con pruebas; Store: `LibraryFilter` y agrupado por artista; App: `LibraryView`, popup de importar, `LinkImportSheet`, `RootView` (tarjeta del tema), `ProjectDetailView` (grabaciones), `AppModel` (selección) | `tf-implementer` |
| C. Ver tomas | 9, grabaciones del 6 | App: `TakeViewer` (visor sobre `TakePreview`/plan de montaje de una parte), `ProjectRecordingsView`, `RecordView`, `RecordController` | `tf-implementer` |
| D. Ajustes | 10 | Store: `EquipmentProfile`, `Take` y pruebas de migración; App: `SettingsView`, `SettingsTab`, funciones de guitarras de `AppModel` | `tf-implementer` |

Las cuatro en paralelo: no comparten ficheros salvo `AppModel.swift` (B toca la selección; D solo borra las dos funciones de guitarras) y el paquete Store (ficheros distintos). Después, `tf-qa` una vez y capturas revisadas por el orquestador.

## Lo que comprueba Jorge

1. Biblioteca: buscador, dos vistas, Seleccionar/Mostrar en Finder, tarjeta de la barra con un título largo (desplazamiento al pasar el ratón), página del tema.
2. Popup: un enlace de YouTube, uno de Spotify, una búsqueda con ▶ (se oye en Spotify) y «Elegir»; y, quitando la clave del `.env` de la copia, que avisa y el enlace sigue funcionando.
3. Backing: alargar, encoger y empujar secciones expandido y plegado, también contra un solo; intentar crear una dentro de otra.
4. Grabar: ver una toma con vídeo y comprobar la sincronía de imagen, toma y backing.
5. Ajustes: «Biblioteca» sin guitarras y el audio igual que antes.

## Estimación

De 6 a 9 horas. Lo incierto: la causa del fallo del arrastre en el modo expandido (ya ha fallado más de una vez) y el desplazamiento al pasar el ratón en SwiftUI sin que la barra salte.
