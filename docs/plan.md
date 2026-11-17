# ToneForge · Plan de implementación

Fuente de verdad del plan desde el 15/11/2026 (ADR-002); antes, copia de la pestaña «Plan» del doc de spec (rev 50).
Spec completa: [spec.md](spec.md). Bocetos de pantallas: [design/](design/).

Once fases (0 a 10) en dos etapas: primero la herramienta de estudio y la grabación con vídeo; después el igualado de tono en la pedalera. Cada fase termina en algo que se puede probar y tiene una condición de paso. Sin fechas: la duración depende de lo que salga en la Fase 0.

## Forma de trabajo

- Spec primero: cada fase empieza con una mini-spec de sus módulos (entradas, salidas, casos de prueba) antes de escribir código.
- Un paquete Swift por módulo, con sus tests: AudioKit propio (E/S y reproducción), StemKit (separación), ModelKit (descarga y compilación de modelos), SourceKit (fuentes externas: YouTube y Spotify), StudyKit (acordes, pulso, bucles), AnalysisKit (huella y distancia), MatchKit (optimizador), HeadRushKit, Tone3000Kit, TabKit, VideoKit y Store (archivo de proyecto e índice en SwiftData).
- Audios de prueba fijos en el repositorio: 3 temas cortos, 3 DI propios y sus resultados esperados, para probar análisis y distancia sin hardware.
- Lo que depende de la pedalera va detrás de una interfaz con una versión simulada, así el resto avanza aunque la Flex Prime no esté conectada.
- Una rama por fase; la fase se cierra cuando cumple su condición de paso y la spec queda actualizada con lo aprendido.

## Etapa 1 · Estudio y grabación (fases 0 a 7)

La pedalera se usa solo como interfaz de audio, con el rig que esté cargado: no hace falta controlar su editor ni TONE3000.

### Fase 0 · Pruebas de riesgo

Siete pruebas cortas e independientes, en scripts sueltos (Python o Swift), que deciden el resto del plan. Para la Etapa 1 solo hacen falta P2, P4 y P6; P1, P3 y P5 se dejan para el comienzo de la Etapa 2. P7 se añadió el 15/11/2026 para la Fase 2b (ADR-008).

- [ ] P1 Remote Editor: capturar el tráfico navegador ↔ pedalera y documentar cómo listar rigs, leer un rig, cambiar un parámetro, cargar un rig y subir un NAM o un IR. Anotar la versión de firmware. *Etapa 2.*
- [x] P2 Audio USB: qué canales de entrada y salida expone la Flex Prime, si da el DI seco, si acepta reamp, a qué frecuencia de muestreo trabaja y si el retorno procesado incluye lo que se le envía por USB (el backing). *Superada, sin plan B; ver `docs/probes/P2-audio-usb.md`.*
- [ ] P3 TONE3000: obtener clave, iniciar sesión, buscar en el catálogo por marca y modelo y descargar un .nam y un IR. Anotar límites de uso. *Etapa 2.*
- [x] P4 Modelos: convertir BS-RoFormer SW y BTC a Core ML y comprobar que dan el mismo resultado que el original y a buena velocidad; el que no funcione bien pasa a ONNX Runtime como respaldo. Comparar la separación con HTDemucs 6 stems en 3 temas y medir tiempos. Elegir el modelo de pulso y el de transcripción de batería. *Elegidos BS-RoFormer SW (Core ML publicado, CPU+GPU), BTC, Beat This! y ADTOF; ver `docs/probes/P4-modelos.md`.*
- [ ] P5 Velocidad del bucle: medir cuánto tarda la pedalera en aplicar un cambio de parámetro, en cambiar de bloque y en cargar un NAM, para estimar cuánto dura un igualado. *Etapa 2.*
- [x] P6 Velocidad: comparar la calidad al 50 % de AVAudioUnitTimePitch y de Rubber Band. *Gana `AVAudioUnitTimePitch` con overlap 8; Rubber Band no hace falta; ver `docs/probes/P6-timepitch.md`.*
- [x] P7 Fuentes externas: de un enlace de Spotify a un fichero de audio local sin credenciales, con yt-dlp. *Superada con un tema (18-24 s) y ampliada a 7 temas, con 5 de 7 aciertos en el candidato; Opus → WAV, y Jorge dio por bueno Opus de oído el 15/11/2026; ver `docs/probes/P7-fuentes.md`, ADR-008 y ADR-011. Sin oír los WAV de la prueba ampliada ni cubrir temas sin subida oficial.*

Condición de paso: para la Etapa 1, audio grabado por USB y un tema separado en local; para la Etapa 2, un parámetro cambiado desde script y un reamp grabado. *Etapa 1 cumplida (audio grabado por USB en P2; tema separado en local en `Probes/P4-modelos/bs_roformer_sw/out/stems/T1/`), confirmada por Jorge el 15/11/2026. Etapa 2 pendiente.*

Si falla: P1 → el igualado termina en una guía visual y el rig se carga a mano o por USB Transfer. P2 → interfaz de audio externa. P4 → HTDemucs como separador.

### Fase 1 · Base y biblioteca

- [x] Proyecto Xcode (macOS 15+), paquetes vacíos, permisos de cámara, micrófono y red local *`Tools/test.sh` verde.*
- [x] Modelo de datos: tema, stem, guitarra, sección, rig, toma, vídeo, perfil de equipo; guardado en un archivo por proyecto dentro de su carpeta, con SwiftData solo como índice de la biblioteca *`StoreTests`.*
- [x] Carpeta por proyecto en disco y limpieza de lo que se puede regenerar *`ProjectCleaner` en `StoreTests`.*
- [x] Importar WAV, FLAC o MP3 y convertir a la frecuencia de trabajo *`AudioImporterTests`.*
- [x] Descarga de modelos la primera vez y separación en 6 stems con progreso *`ModelStoreTests`, `HeavyModelTests` y la prueba en la app (ADR-007).*
- [x] Pantalla de biblioteca *Capturas revisadas por el orquestador.*
- [x] Sección de Ajustes en la barra lateral (icono de engranaje), con el apartado Biblioteca y equipo: carpeta de proyectos, modelos descargados, espacio en disco, limpieza y perfil de equipo *Capturas revisadas por el orquestador.*

Condición de paso: un tema importado y separado, con sus stems en disco. *Cumplida el 15/11/2026: T1 importado en la app y separado con un directorio de soporte vacío, 6 stems a 44,1 kHz en `Temp/p7/projects/mix/stems/` (ADR-007).*

### Fase 2 · Herramienta de estudio (RF7, RF10)

- [x] Reproductor de stems sincronizados con volumen, silenciar y solo *(`StudyPlayerTests`, AudioKit, 32 tests)*
- [x] Velocidad del 50 al 200 %, transposición, afinación fina y capo virtual *(`StudyPlayerTests`: 10 s al 70 % → 14,2876 s, +200 cents = 493,883 Hz; el capo cambia solo los diagramas, `ChordTests`)*
- [x] Detección de pulso, tempo, compases y tonalidad *(`BeatTests`, `BeatHeavyModelTests`, `ChordRecognizerTests` (tonalidad), `ChordHeavyModelTests`)*
- [x] Detección de acordes, tira de acordes con diagramas y corrección a mano *(`ChordRecognizerTests`, `ChordHeavyModelTests`, `ChordTests` y capturas revisadas por el orquestador)*
- [x] Secciones del tema, bucles ajustados al pulso y metrónomo *(`StudyPlayerTests` (bucle y clics), `BeatTests` (imán) y capturas)*
- [x] Pantalla de backing track *(capturas revisadas por el orquestador, `Temp/p8/`)*

Condición de paso: tocar encima de un tema sin guitarras, en bucle y al 70 %. *Cumplida el 15/11/2026, confirmada por Jorge tocando por la Flex Prime: tema sin guitarras, en bucle y al 70 % (ADR-009).*

### Fase 2b · Fuentes externas (ADR-008)

Importar temas desde un enlace de YouTube o de Spotify. El audio sale de YouTube con yt-dlp; de Spotify solo se leen metadatos. Probado en P7 (`docs/probes/P7-fuentes.md`) con un solo tema.

- [x] Lectura de metadatos de Spotify (página embed, sin credenciales) *(`SourceKitTests`, 63 tests; embed grabado en P7)*
- [x] Búsqueda en YouTube y selector de candidatos con la diferencia de duración *(`SourceKitTests`; capturas en `Temp/p9/`; prueba ampliada de P7: 5 de 7 aciertan)*
- [x] Descarga Opus → WAV e importación a la biblioteca *(`SourceKitTests`, `StoreTests` 69 tests; prueba ampliada de P7: 5 descargas en Opus, WAV de 48 kHz y 24 bit)*
- [x] Helpers embebidos (yt-dlp, Deno, ffmpeg) y su actualización *(`SourceKitTests` (`HelperLocator`, `YtDlpUpdater`); capturas de Ajustes en `Temp/p9/`)*
- [x] Listas de Spotify y de YouTube y álbumes de Spotify: marcar temas, revisión en lote y cola «Descargar y procesar» *(`SourceKitTests` (`PlaylistTests`); capturas en `Temp/p9/`; embeds de lista y álbum en la prueba ampliada)*
- [x] Repetidos: bloqueo por identificador de Spotify y `videoID`, y aviso suave por título y artista *(`StoreTests` (`OriginTests`); capturas en `Temp/p9/`)*
- [x] Eliminar un tema, editar título y artista, y re-encolar al arrancar las separaciones interrumpidas *(`StoreTests` (`TrashTests`, `RecoveryTests`); capturas en `Temp/p9/`)*

Condición de paso: pegar un enlace de YouTube y otro de Spotify deja cada tema en la biblioteca listo para separar, sin más paso manual que elegir candidato; pegar una lista o un álbum, marcar parte de sus temas y pulsar «Descargar y procesar» los deja importados y separados; y la prueba ampliada con al menos cinco temas (uno sin subida oficial, uno con el directo dominante y uno largo) queda anotada en `docs/probes/P7-fuentes.md` con cuántos aciertan el candidato correcto. *Cumplida el 15/11/2026, confirmada por Jorge en la app (ADR-011). La prueba ampliada (7 temas, 5 aciertos) no cubrió el tema sin subida oficial ni el directo dominante claro.*

### Fase 3 · Audio con el dispositivo (RF1)

- [x] Selector de dispositivo de entrada y de salida y de canales (guitarra y backing), guardado en el perfil de equipo, sin nada cableado a la Flex Prime
- [x] Calibración de latencia con un pulso (bucle de cable)
- [x] Apartado Audio de Ajustes: dispositivos, canales, frecuencia de muestreo y calibración de latencia
- [x] Envío del backing al dispositivo elegido
- [x] Grabación de la señal procesada
- [x] Alinear la toma con el backing usando la latencia medida y el retardo del rig de cada toma
- [x] A/B de tu guitarra contra la original dentro de la mezcla (en directo y última toma)

Condición de paso: toma grabada alineada con el backing con error menor de 1 ms. *Cumplida el 15/11/2026 (0,010 ms en una toma de comprobación de 60 s recién calibrada, con `tf-audio verify`; ADR-013). Límite conocido: la latencia de la Flex Prime se acorta a escalones de 12 muestras (0,25 ms) que el HAL no refleja; Jorge lo acepta y no hay corrección.*

El DI (canal, nivel, DI seco) y el reamp salieron de esta fase el 15/11/2026 (ADR-012).

### Fase 4 · Guitarras y secciones (RF6, parte de RF5)

- [x] Separar la pista de guitarras en A y B por panorama estéreo. *Cambió (ADR-014): la panorámica con máscaras se descartó; «Guitarras en L y R» usa los canales L y R, y los tramos de solo usan el modelo lead/rhythm.*
- [x] Clasificar pasajes en rítmica o solista con Basic Pitch. *Cambió (ADR-014): Basic Pitch y `PassageClassifier` hechos, pero la clasificación automática queda fuera de la cola; el solo es una sección marcada a mano.*
- [x] Nombrar las guitarras, marcar o corregir secciones a mano y mostrar la confianza
- [x] Añadir las guitarras separadas al mezclador de la Fase 2
- [x] Probar modelos dedicados a guitarra frente a BS-RoFormer SW (8,23 / 11,03 / 4,38 dB): probado, descartado (Mega 53: 7,58 dB; becruily: 5,81 dB en T1). Decidido por Jorge en la Fase 0.

Condición de paso: Robe y Uoho en pistas distintas en 3 temas de prueba. Cumplida el 16/11/2026 (3 temas de Extremoduro con «Guitarras en L y R», de oído por Jorge).

Notas de cierre (ADR-014): Backing va sin grabación ni A/B (el código de la Fase 3 se conserva para la Fase 6) y la Etapa 2 sale de la UI («Igualar tono», «Pedalera y TONE3000», rigs en Biblioteca). Un modelo solista frente a rítmica de mejor calidad queda para la Etapa 2.

### Fase 5 · Tablatura (parte de RF2, RF11)

- [x] Transcribir las guitarras con Basic Pitch y asignar cuerdas y trastes; transcribir también el bajo (4 cuerdas) y la batería (modelo aparte: bombo, caja y charles como mínimo). *Hecho y probado: `TabFingeringTests`, `TabQuantizeTests`, `TabTempoDriftTests`, `TabGridTests`, `DrumTranscriberTests` (T1: 1117/1117 golpes). Calidad según Jorge: bajo muy bueno, batería buena (platos confundidos con charles), guitarras pésimas (ADR-016; Fase 5b).*
- [x] Tablatura con alphaTab, cursor, edición y exportación a un único archivo de Guitar Pro con guitarras, bajo y batería, comprobado en Guitar Pro. *Hecho: `AlphaTabScoreTests`, `TabEditorTests`, `TabSynthTests`, `TabFingerprintTests`, `TabSourcesTests`, capturas de la pantalla y apertura en Guitar Pro 8 por Jorge. Falta que Jorge pruebe a fondo el teclado de edición y «Oír transcripción» con reproducción real.*

Condición de paso: tablatura de un tema con guitarras, bajo y batería exportada y abierta en Guitar Pro. Cumplida el 16/11/2026: «El roce de tu cuerpo» (Platero y Tú), 5 pistas y 181 compases, exportada con `--tab-export` y abierta en Guitar Pro 8 por Jorge; la batería suena con RSE.

Notas de cierre (ADR-016): la calidad de las guitarras no es aceptable y pasa a la Fase 5b; los compases irregulares (3/4, 2/4) en intros vienen del `BeatGrid`.

### Fase 5b · Calidad de la transcripción de guitarra

- [x] Probar Guitab y MuScriptor small frente a Basic Pitch fuera de la app (Python, `tf-ml`, fallar rápido), con El roce como puerta. *Medido contra la tablatura de Songsterr: Guitab E25 gana (F1 0,35–0,39 frente a 0,27–0,30) pero ninguno es reconocible; MuScriptor sin probar (licencia de los pesos).*
- [x] Rítmica escrita desde los acordes de BTC (`ChordShapes`) con el ritmo de los ataques. *Gana en lo rasgueado, 0,00 en los riffs; el híbrido no generaliza. Descartada.*
- [x] Limpieza de lo que da Basic Pitch: puerta de silencio y arreglo del port, techo de registro en MIDI 86. *`SilenceGate`, `TabTrackBuilder.guitarPitchCeiling` (`parametersVersion` 3).*
- [x] Platos de ADTOF confundidos con charles. *`DrumCymbalSeries`; Jorge lo oye mejor en El roce.*
- [x] Prueba de quitar la distorsión antes de transcribir (RemFX), El roce como puerta. *Descartada: en guitar_L, F1 +0,005 (Guitab) y −0,001 (Basic Pitch); entrenado con drive suave simulado, apenas toca la saturación de ampli grabada.*
- [x] Tablatura de Songsterr como fuente por defecto: búsqueda, emparejamiento editable, alineación con el audio; automática de respaldo (mini-spec en `docs/spec.md`, «Calidad de la tablatura»). *Hecho: hoja con vista previa donde elige Jorge (sin comparación automática por la política de acceso de Songsterr), `SongsterrAlignerTests`, `SongsterrImportPlanTests`, `SongsterrConverterTests` y las puertas reales `TF_P5B_TESTS=1` (`SongsterrAlignmentRoceTests`, `SongsterrAlignmentTornadoTests`, `SongsterrAlignmentKamelasTests`, `SongsterrSoloProjectsTests`).*
- [x] Metrónomo y compases de Songsterr (fuera de la lista inicial, decisión de Jorge de oído): `SongsterrBeatGrid`, `tab/songsterr-grid.json`, `StudySession.metronomeBeats`. *`SongsterrBeatGridTests`, `SongsterrBeatGridRoceTests`.*
- [x] Adornos (fuera de la lista inicial): `TabTechniques`, dibujo y `.gp`, 0 sin representar en El roce y Tornado. *`SongsterrTechniquesTests`, `AlphaTabTechniquesTests` y `Probes/P5b-guitarra/check-techniques.js` (46/46).*
- [x] Afinación personalizada. *`TuningCustomTests`.*

Condición de paso (aprobada por Jorge el 16/11/2026): tablatura de 3 temas reconocible en la app (rítmicas, solos y batería con los platos corregidos), juzgado por Jorge; El roce primero. Cumplida el 17/11/2026: «El roce de tu cuerpo» (Platero y Tú, #50624), «Tornado Of Souls» (Megadeth, #12824) y «Aquellas Cosas Que Solíamos Hacer» (Benito Kamelas, #3470719); Jorge: «todo perfecto».

Notas de cierre (ADR-017): Guitab/MuScriptor, la rítmica desde acordes BTC y RemFX quedan descartados. Regla: probar ramas atrasadas con copia aislada (`--projects-folder`, `--support-dir`); el binario de `fase-5b`, sin la Fase 6, borró `recording`, `montage` y el vídeo de El roce.

### Fase 5c · Interfaz de la tablatura (rama desde `fase-5b`)

- [ ] Voces de Songsterr como voz o pentagrama (hoy entran como pista de guitarra) y nombres de pista vacíos → instrumento
- [ ] Que suenen en «Oír transcripción» let ring, slides, ligados, armónicos, adornos y flam
- [ ] Editar técnicas con el teclado
- [ ] Cambios de interfaz que Jorge defina al ver la pantalla completa

Condición de paso: por definir con Jorge al ver la pantalla completa.

El DI guiado (grabar y validar la toma) salió de esta fase el 15/11/2026: solo hace falta para el igualado y pasa a la Fase 8a, en la Etapa 2.

### Fase 6 · Grabación con vídeo (RF8, parte de RF9)

- [x] Captura de cámara (webcam o iPhone) con el mismo reloj que el audio
- [x] Desfase de la cámara ajustado a mano al terminar la toma, guardado por cámara (sin calibración automática; Jorge, 16/11/2026)
- [x] Apartado Cámara y vídeo de Ajustes: cámara por defecto, resolución, fotogramas por segundo, desfase y exportación por defecto
- [x] Grabación: procesada sobre los stems con su mezcla, como en Backing (sin DI ni micro; ADR-012; Jorge, 16/11/2026)
- [x] Multitoma: partes, tomas por parte, mejor toma y punch-in (el rig recomendado para cada parte llega con la Etapa 2)
- [x] Pantalla de grabación

Condición de paso: 3 tomas grabadas y alineadas a menos de 1 fotograma.

Cumplida el 16/11/2026 (ADR-015): test de la puerta con cámara simulada (error máximo 0,069 fotogramas) y 3 tomas con el mismo desfase comprobadas por Jorge en la app con el iPhone, más el punch-in, la cuenta y Ajustes · Cámara y vídeo.

### Fase 7 · Montaje (RF9)

- [ ] Encuadre automático de la guitarra con Vision y ajuste manual
- [ ] Layouts landscape y portrait, y plano único para una rítmica y una solista
- [ ] Aparición de la solista solo en los solos, a partir de las secciones
- [ ] Compositor propio con las transiciones y vista previa en tiempo real
- [ ] Exportación: vídeo, mezcla a -14 LUFS, rótulo y WAV por pista
- [ ] Pantalla de montaje

Condición de paso: vídeo final exportado en portrait y en landscape.

### Fase 7b · Retoques de interfaz (rama desde `fase-7`)

Lista de Jorge del 17/11/2026, tras usar la app. La mini-spec se escribe al empezar; las dudas abiertas van al final.

Biblioteca:

- [ ] Quitar la cabecera de contadores (temas, tomas grabadas, vídeos exportados): no aporta
- [ ] Buscador de temas (título y artista)
- [ ] «Importar tema» abre un popup con un campo para el enlace y un botón «Importar fichero»
- [ ] Ese campo hace también de buscador de Spotify: si lo escrito no es un enlace, al pulsar «Importar» se buscan 10 resultados en Spotify, cada uno con un botón que lo reproduce en Spotify para oírlo antes de elegir
- [ ] Dos vistas: por tema (la actual) y por artista
- [ ] «Abrir» pasa a ser «Seleccionar», con otro botón para mostrar en Finder. El tema seleccionado aparece entre Ajustes y el dispositivo (título y artista, empujándolos); si no cabe se trunca y al pasar el ratón el texto se desplaza para verse entero. Al pulsarlo lleva a su página de información, con Mostrar en Finder, Eliminar y las grabaciones guardadas del tema

Backing track:

- [ ] Alargar o encoger una sección en el modo expandido sigue fallando
- [ ] No se puede crear una sección dentro de otra. Al empujar una sección contra otra, la segunda se encoge; el solo nunca se encoge de forma indirecta, solo se modifica directamente

Grabar:

- [ ] Reproducir las tomas hechas, para verlas y volver a evaluarlas por si hay que mejorarlas

Ajustes:

- [ ] El apartado «Biblioteca y equipo» pasa a ser solo «Biblioteca», sin las guitarras del perfil de equipo

Condición de paso: los diez puntos comprobados por Jorge en la app.

Decidido con Jorge (17/11/2026):

- Búsqueda en Spotify con clave propia: app de desarrollador gratuita, Web API, flujo client credentials (sin usuario). Client ID y secret en un `.env` que no se versiona (`.env.example` sí, con los nombres de las variables); nunca en el repositorio ni dentro del bundle. La app (lanzada desde Finder no ve el entorno de la shell) lee `<support dir>/.env`, si no existe el del directorio de soporte por defecto (`~/Library/Application Support/ToneForge/.env`, chmod 600), y las variables de entorno con el mismo nombre mandan sobre ambos. Jorge crea la app guiado por el orquestador. Es una excepción a «sin credenciales» de ADR-008 solo para buscar: los metadatos y el audio siguen igual. Reproducir en Spotify = abrir `spotify:track:<id>` en su app. Token: client credentials no da refresh token (los 180 días del panel son del flujo con usuario); el access token dura 1 h, se guarda en memoria y se pide otro al caducar o con un 401. Jorge tiene Premium «por ahora»: si la cuenta o la clave dejan de valer (401/403, sin clave), el campo avisa y sigue aceptando enlaces e «Importar fichero»; la búsqueda no puede ser imprescindible.
- Solo: si se empuja otra sección contra él, el arrastre se para en su borde.
- Tema seleccionado en la barra lateral: ocupa el hueco encima del bloque del dispositivo y empuja «Ajustes» hacia arriba. Sin tema seleccionado (al abrir la app, la selección no se recuerda), «Ajustes» queda donde está ahora.
- Perfil de equipo: las guitarras salen de la interfaz y del modelo de datos (con migración de los proyectos existentes); lo que guarda de audio (dispositivos, canales, latencia) se conserva.

## Etapa 2 · Igualado de tono (fases 8a, 8 y 9)

Empieza cuando la Etapa 1 está en uso. Antes de la Fase 8 se hacen las pruebas P1, P3 y P5 de la Fase 0 y, en paralelo con ellas, la Fase 8a.

### Fase 8a · DI guiado (parte de RF2)

Grabar el DI siguiendo la tablatura, para tener la toma que después se reamplifica. Viene de la antigua Fase 5.

- [ ] Canal del DI, calibración de su nivel y grabación del DI seco, ocultos al usuario (ADR-012)
- [ ] Grabar la toma con cuenta atrás, siguiendo la tablatura, y validarla: afinación, timing y clipping
- [ ] Guardar la toma como DI para el igualado

Condición de paso: toma válida a la primera en riffs sencillos.

### Fase 8 · Análisis del tono (RF4)

- [ ] Huella del tono: tercios de octava, armónicos, dinámica y anchura estéreo, con comparación nota a nota alineada en el tiempo
- [ ] Función de distancia, prototipada primero en Python y validada con escucha A/B
- [ ] Conector TONE3000: sesión, búsqueda, descarga y caché
- [ ] Apartado Pedalera y TONE3000 de Ajustes: dirección del Remote Editor, firmware, estado de la conexión y cuenta de TONE3000
- [ ] Reamp (reproducir un DI hacia la pedalera y grabar el retorno alineado) y plantillas de rig de partida para la Flex Prime
- [ ] Selección de plantillas según la saturación de la huella, y detección de efectos en el original: delay, reverb, compresión, modulación y wah
- [ ] Pantalla de igualar tono: espectros, candidatos y A/B

Condición de paso: la distancia ordena varios tonos grabados igual que tu oído en 3 temas.

### Fase 9 · Igualado en la pedalera (RF3, RF5)

- [ ] Conector HeadRush a partir de lo documentado en P1
- [ ] Catálogo de bloques, parámetros y rangos de la Flex Prime
- [ ] Optimizador en bucle sobre la pedalera: probar las plantillas, escribir parámetros, reamp, medir y repetir
- [ ] Vista de la cadena de señal con knobs editables a mano
- [ ] Añadir compresión, delay, reverb y efectos sugeridos tras igualar el tono en seco, y guardar el rig con escenas rítmica y solista y subir sus NAM e IR

Condición de paso: rig cargado en la Flex Prime en menos de 10 min. Aquí se comprueba el criterio de éxito de la v1 con los 10 temas.

### Fase 10 · Ampliaciones (v2)

Gigboard con firmware NAM custom y Spark GO y NEO, si se confirman.

## Dependencias

La Etapa 1 no depende del Remote Editor ni de TONE3000. La tablatura (5) depende de la fase 4; la grabación (6), de la 3 y la 4; el montaje (7), de la 6. En la Etapa 2, el DI guiado (8a) depende de las fases 3 y 5; el análisis del tono (8), de P3 y de la 8a; el igualado (9), de P1 y de la fase 8.

### Orden de ejecución

Mismo número de orden: se pueden hacer en paralelo o en cualquier orden entre sí. Las dependencias de las fases 5, 6, 7 y 9 y de las pruebas de la Etapa 2 son las del párrafo anterior; las demás están deducidas de lo que necesita cada tarea. Los modelos son los de «Modelos por fase».

| Orden | Qué | Va después de | Pedalera | Orquestador | Agentes |
|---|---|---|---|---|---|
| 1 | P4 · Modelos a Core ML | Nada | No | Opus | Opus |
| 1 | P6 · Calidad al 50 % | Nada | No | Opus | Sonnet |
| 1 | P2 · Audio USB | Nada | Sí | Opus | Sonnet |
| 2 | Fase 1 · Base y biblioteca | P4 | No | Opus | Sonnet |
| 3 | Fase 2 · Herramienta de estudio | Fase 1, P6 | No | Opus | Opus (pulso, acordes) · Sonnet (reproductor, pantalla) |
| 3 | Fase 2b · Fuentes externas | Fase 1, P7 | No | Opus | Sonnet (conectores y pantallas) |
| 4 | Fase 3 · Audio con el dispositivo | P2, Fase 2 | Sí | Opus | Opus (latencia, alineado) · Sonnet (selector, Ajustes de audio) |
| 4 | Fase 4 · Guitarras y secciones | Fase 2 | No | Opus | Opus (separación A/B, clasificación) · Sonnet (interfaz) |
| 5 | Fase 5 · Tablatura | Fase 4 | No | Opus | Opus (cuerdas y trastes, batería) · Sonnet (alphaTab) |
| 5 | Fase 5b · Calidad de la transcripción de guitarra | Fase 5 | No | Opus | Opus (`tf-ml`) |
| 5 | Fase 6 · Grabación con vídeo | Fases 3 y 4 | Sí | Opus | Opus (reloj común) · Sonnet (multitoma, pantalla) |
| 6 | Fase 7 · Montaje | Fase 6 | No | Fable | Opus (compositor, encuadre) · Sonnet (layouts, exportación, pantalla) |
| 6 | Fase 7b · Retoques de interfaz | Fase 7 (rama desde `fase-7`) | No | Opus | Sonnet (pantallas, buscador, Spotify) · Opus (arrastre de secciones) |
| 7 | P1 · Remote Editor | Etapa 1 en uso | Sí | Fable | Opus (análisis del tráfico) · Sonnet (scripts) |
| 7 | P3 · TONE3000 | Etapa 1 en uso | No | Fable | Sonnet |
| 7 | P5 · Velocidad del bucle | P1 | Sí | Fable | Sonnet |
| 7 | Fase 8a · DI guiado | Fases 3 y 5 | Sí | Opus | Sonnet (grabación y validación de la toma) |
| 8 | Fase 8 · Análisis del tono | P3, Fase 8a | Sí | Fable | Opus (huella, distancia) · Sonnet (TONE3000, pantalla) |
| 9 | Fase 9 · Igualado en la pedalera | P1, Fase 8 | Sí | Fable | Opus (HeadRushKit, optimizador) · Sonnet (catálogo, knobs) |
| 10 | Fase 10 · Ampliaciones (v2) | Fase 9 | Otro hardware | Sin definir | Sin definir |

Sin pedalera se puede avanzar con P4, P6 y las fases 1, 2, 2b, 4 y 5. La primera vez que hace falta conectarla es P2, que bloquea la Fase 3 pero nada de lo anterior. P4, P6 y P2 comparten una sesión orquestadora; P1, P3 y P5, otra.

## Estimación de tiempos

Entre 55 y 89 horas de trabajo con Claude Code: de 37 a 59 la Etapa 1 y de 18 a 30 la Etapa 2 (al mover el DI guiado a la Etapa 2 se le asignaron 1 a 2 horas de las 7 a 12 de la antigua Fase 5; el total no cambia). Recalibrada con experiencia real (tareas estimadas en 1 o 2 semanas han llevado 5 o 6 horas). Marca el ritmo lo que solo se puede hacer con la pedalera y de oído. No incluye una posible versión de Windows.

| Fase | Horas | Acumulado | Qué marca el ritmo |
|---|---|---|---|
| 0. Pruebas P2, P4 y P6 | 3 a 5 | 3 a 5 | Probar el USB y convertir modelos |
| 1. Base y biblioteca | 2 a 3 | 5 a 8 | Descarga de modelos y primera separación |
| 2. Herramienta de estudio | 4 a 6 | 9 a 14 | Revisar acordes y pulso en temas reales |
| 2b. Fuentes externas | 5 a 8 | 14 a 22 | Compilar ffmpeg y probar descargas reales con varios temas |
| 3. Audio con el dispositivo | 4 a 6 | 18 a 28 | Pruebas de latencia y niveles con la Flex Prime |
| 4. Guitarras y secciones | 3 a 5 | 21 a 33 | Escuchar si la separación A/B convence |
| 5. Tablatura (guitarras, bajo y batería) | 6 a 10 | 27 a 43 | Corregir transcripciones; la batería es lo más incierto |
| 6. Grabación con vídeo | 4 a 6 | 31 a 49 | Sincronía de cámara y pruebas de tomas |
| 7. Montaje | 6 a 10 | 37 a 59 | Ajustar transiciones y encuadre a la vista |
| Pruebas P1, P3 y P5 | 4 a 6 | 41 a 65 | Capturar el tráfico del Remote Editor |
| 8a. DI guiado | 1 a 2 | 42 a 67 | Tocar las tomas y ver si la validación acierta |
| 8. Análisis del tono | 5 a 7 | 47 a 74 | Reamp y validar de oído la medida de parecido |
| 9. Igualado en la pedalera | 8 a 15 | 55 a 89 | Catálogo de bloques y afinar el bucle con hardware real |

En calendario, con unas 10 horas a la semana: la Etapa 1 en 4 a 6 semanas y todo en 5 a 9.

La mayor incertidumbre no es de horas sino de resultado: si el Remote Editor no se deja controlar (P1), la Fase 9 cambia de forma, no de duración.

## Modelos por fase

Cada fase la lleva una sesión orquestadora que escribe la mini-spec, reparte el trabajo en agentes de modelo igual o menor y revisa lo que devuelven. El orquestador no programa las partes: decide, integra y comprueba la condición de paso. Reparto propuesto el 15/11/2026, sin datos medidos todavía en este proyecto: se ajusta con lo que salga en la Fase 0.

| Fase | Orquestador inicial | Agentes | Por qué |
|---|---|---|---|
| 0. Pruebas P2, P4 y P6 | Opus | Opus para la conversión a Core ML (P4); Sonnet para los scripts de P2 y P6 | Scripts cortos e independientes; lo difícil es solo la conversión |
| 1. Base y biblioteca | Opus | Sonnet para paquetes, modelo de datos, importación y pantallas; Opus para la integración del separador | APIs de Apple documentadas y trabajo guiado por la spec; el separador pide integrar el modelo |
| 2. Herramienta de estudio | Opus | Opus para pulso y acordes; Sonnet para reproductor y pantalla | Integrar modelos es lo delicado; el resto es interfaz |
| 2b. Fuentes externas | Opus | Sonnet para conectores y pantallas | APIs y scripts documentados (P7); sin modelos que integrar |
| 3. Audio con el dispositivo | Opus | Opus para latencia y alineado; Sonnet para selector y Ajustes de audio | La precisión de 1 ms pide cuidado, no un modelo mayor |
| 4. Guitarras y secciones | Opus | Opus para la separación A/B y la clasificación; Sonnet para la interfaz | Procesado de señal acotado |
| 5. Tablatura | Opus | Opus para cuerdas y trastes y para la batería; Sonnet para alphaTab | Fase larga pero de piezas conocidas |
| 5b. Calidad de la transcripción de guitarra | Opus | Opus (`tf-ml`) para la prueba de modelos y la limpieza | Probar modelos fuera de la app y fallar rápido |
| 6. Grabación con vídeo | Opus | Opus para el reloj común de audio y vídeo; Sonnet para multitoma y pantalla | La sincronía es el único punto fino |
| 7. Montaje | Fable | Opus para el compositor y el encuadre; Sonnet para layouts, exportación y pantalla | Compositor propio fotograma a fotograma, poco documentado |
| 7b. Retoques de interfaz | Opus | Sonnet para pantallas, buscador, Spotify y Ajustes; Opus para el arrastre de secciones de Backing | Interfaz casi toda; el arrastre ya ha fallado más de una vez |
| Pruebas P1, P3 y P5 | Fable | Opus para analizar el tráfico capturado; Sonnet para los scripts | Ingeniería inversa de un protocolo sin documentar |
| 8a. DI guiado | Opus | Sonnet para la grabación y la validación de la toma | Fase corta sobre el audio de la Fase 3 y la tablatura de la Fase 5 |
| 8. Análisis del tono | Fable | Opus para huella y distancia; Sonnet para el conector TONE3000 y la pantalla | Diseñar la medida de parecido decide el resultado de la v1 |
| 9. Igualado en la pedalera | Fable | Opus para HeadRushKit y el optimizador; Sonnet para el catálogo de bloques y la vista de knobs | Bucle cerrado sobre hardware real con protocolo propio |

Reglas comunes:

- Subir el orquestador de Opus a Fable solo si un mismo problema falla dos veces, y volver a Opus al resolverlo.
- Las ediciones mecánicas (renombrar, cambios de uno o dos ficheros) van a Haiku o Sonnet.
- Localizar código va siempre a un agente, no al orquestador.
- Una sesión por fase y `/clear` al cerrarla: el contexto acumulado cuesta más que la diferencia entre modelos.
- Lo que solo se puede comprobar con la pedalera o de oído no mejora con un modelo mayor.

## Primer paso

Empezar por P2 con la Flex Prime delante (qué canales da por USB y si el retorno mezcla el backing con la guitarra) y por P4 (convertir el separador a Core ML): las dos pruebas de las que depende la Etapa 1.
