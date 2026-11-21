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

- [x] Voces de Songsterr como voz o pentagrama (hoy entran como pista de guitarra) y nombres de pista vacíos → instrumento
- [x] Que suenen en «Oír transcripción» let ring, slides, ligados, armónicos, adornos y flam
- [x] Editar técnicas con el teclado
- [x] Cambios de interfaz que Jorge defina al ver la pantalla completa: mute y solo por pista, todas las pistas a stem o a transcripción de una vez, y bucle sobre una selección de la tablatura

Condición de paso (Jorge, 17/11/2026): en los tres temas de la 5b, voces en pentagrama sin pistas sin nombre; suenan let ring, slides, ligados, armónicos, adornos y flams; P.M., bend, vibrato y slide se ponen y quitan con las teclas de Guitar Pro y se guardan; mute/solo por pista; todas a stem o a transcripción de una vez; una selección suena en bucle. El roce es la puerta. No comprobada por Jorge (renunció a la prueba manual el 18/11/2026); lo que falle pasa a la fase final de arreglos. Mini-spec en `docs/spec.md`, «Interfaz de la tablatura».

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

- [x] Encuadre automático de la guitarra con Vision y ajuste manual — *`GuitarFramerTests`; hoja «Encuadre» probada por Jorge*
- [x] Layouts landscape y portrait, y plano único para una rítmica y una solista — cinco layouts, con cortes libres y regla de cobertura (ADR-018) — *`MontageSingleCoverageTests`, `MontageTimelineTests`*
- [x] Aparición de la solista solo en los solos, a partir de las secciones — *`MontageTimelineTests`, `MontageCompositionCoverageTests`*
- [x] Compositor propio con las transiciones y vista previa en tiempo real — incluido el fundido a negro de la toma que acaba antes — *`MontageCompositionCoverageTests`, `MontageRendererTests`, `MontageAudioFadeTests`, `MontageFrameGridTests`*
- [x] Exportación: vídeo (MOV o MP4, audio AAC), mezcla a -14 LUFS con techo de -1,3 dBTP, rótulo y WAV por pista — *`MontageGateTests`, `MontageOptionsTests`; AudioKit: `LoudnessMeterTests`, `MontageMixerTests`, `MontageMixerOrderTests`, `MontageLimiterSinglePassTests`, `MontageLimiterTruePeakTests`, `TakeResamplingTests`*
- [x] Pantalla de montaje — columna de exportación compacta con (i), orden de carriles arrastrable
- [x] Botón «Rotar» (0°, 90°, 180°, 270°) por cámara y por toma, aplicado al leer sin recodificar (Grabar, Ajustes de vídeo y ficha de toma en Montaje) — *`VideoRotationTests` (VideoKit y Store); el iPhone con Continuidad en vertical sigue sin probar*

Condición de paso: vídeo final exportado en portrait y en landscape.

Cumplida el 18/11/2026 (ADR-018): Jorge probó a mano la app («todo correcto») con el vídeo exportado en portrait y en landscape, y `MontageGateTests` cubre la puerta sin hardware.

### Fase 7b · Retoques de interfaz (rama desde `fase-7`)

Lista de Jorge del 17/11/2026, tras usar la app. La mini-spec se escribe al empezar; las dudas abiertas van al final.

Biblioteca:

- [ ] Quitar la cabecera de contadores (temas, tomas grabadas, vídeos exportados): no aporta
- [ ] Buscador de temas (título y artista)
- [ ] «Importar tema» abre un popup con un campo para el enlace y un botón «Importar fichero»
- [ ] Ese campo hace también de buscador de Spotify: si lo escrito no es un enlace, al pulsar «Importar» se buscan 10 resultados en Spotify, cada uno con un botón que lo reproduce en Spotify para oírlo antes de elegir
- [ ] Dos vistas: por tema (la actual) y por artista
- [ ] «Abrir» pasa a ser «Seleccionar», con otro botón para mostrar en Finder. El tema seleccionado aparece entre Ajustes y el dispositivo (título y artista, empujándolos); si no cabe se trunca y al pasar el ratón el texto se desplaza para verse entero. Al pulsarlo lleva a su página de información, con Mostrar en Finder, Eliminar y las grabaciones guardadas del tema

- [ ] Corregir título y artista desde la lista: icono de lápiz en cada fila (añadido el 18/11/2026)
- [ ] Vista Artistas en recuadros con foto (de Spotify) y nombre; al pulsar uno, sus temas con flecha para volver; al volver de Temas, siempre la cuadrícula completa (añadido el 18/11/2026)

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

### Fase 7c · Port a Windows (sin rama aún; rama `fase-7c` desde `main`)

Pedida por Jorge el 18/11/2026: ToneForge en Windows para su uso y para prestarla a un par de amigos. Se compila y se prueba en una máquina virtual de Windows en el Mac, sin GitHub Actions para iterar (decisión de Jorge, 18/11/2026): ciclo corto, sin push y sin gastar minutos. Mini-spec al empezar; sin estimación todavía. Orquestador y agentes aprobados por Jorge el 18/11/2026 (tablas de orden y modelos).

- [x] Máquina virtual de compilación y pruebas, lo primero de la fase: UTM (gratis, `brew install --cask utm`) con Windows 11 ARM64 (ISO oficial de Microsoft; sin activar basta para probar), 4 núcleos, 8 GB, unos 100 GB de disco, guest tools de UTM (SPICE y agente QEMU), carpeta compartida con el repo del Mac y una instantánea de Windows recién instalado. La instalación de Windows la hace Jorge (cuenta local con `Shift+F10` → `oobe\bypassnro`); el resto, el agente.
- [x] Entorno de compilación dentro de la VM: Visual Studio Build Tools (MSVC y SDK de Windows, ARM64 y x64) y el toolchain de Swift para Windows; segunda instantánea con todo instalado. Los modelos grandes van en releases (`models-v1`, `Tools/models/fetch.sh`) y `.gitattributes` ya fija LF.
- [x] Compilar las dos arquitecturas en la VM: ARM64 nativa y x64 (los PCs de los amigos), las dos desde el mismo comando. La x64 se prueba en la VM con la emulación de Windows ARM. Script en `Tools/` que lanza la compilación en la VM, instala el resultado y lo arranca, para iterar sin tocar la VM a mano (`utmctl` y la carpeta compartida).
- [x] Prueba de viabilidad, que decide el resto (fallar rápido): qué paquetes compilan con Swift para Windows en ARM64 y x64 y qué depende de Apple (SwiftUI, Core ML, AVFoundation, Accelerate, Vision); con qué se hace la interfaz; cómo se sustituyen modelos (ONNX Runtime, ya previsto como respaldo en P4), audio (WASAPI o ASIO), cámara y vídeo, y helpers (yt-dlp, Deno y ffmpeg para Windows). Resultado en `docs/probes/P8-windows.md` y un ADR; decide Jorge.
- [x] Alcance de la versión de Windows: qué funciones de la Etapa 1 entran, decidido por Jorge con el resultado de la prueba de viabilidad: todo de una, interfaz WebView2 (ADR-020).
- [x] Capa de plataforma: todos los paquetes compilan en Windows (ARM64 y x64) y sus tests pasan en la VM, con los del Mac en verde. *Hecho el 19/11/2026: suite entera del Mac y `App` en verde; en la VM los 13 paquetes en ARM64 y x64 con 0 fallos; 114 saltos `[paso 7]` (reproductor 37, remuestreador 23, onnx-runtime 17, direct2d 14, sintetizador 11, media-foundation 11, parada 1) y 5 saltos `[windows]` permanentes. Tareas heredadas para el paso 7 al final del «Corte del paso 6».*
- [x] Piezas de Windows: señal, audio (decodificación, WASAPI, reproductor), modelos con ONNX Runtime y GPU, vídeo con Media Foundation y helpers. *Hecho el 21/11/2026, solo x64 (ARM64 retirado como puerta el 19-20/11): suite entera del Mac verde; en la VM x64 Debug los 13 paquetes con 0 fallos y 0 saltos `[paso 7]` (eran 114): NativeKit 45 pasados/1 saltado, AudioKit 184/3, VideoKit 82/3, Store 202/1, ModelKit 18/6, StudyKit 45/4, TabKit 228/23, StemKit 77/13, SourceKit 116/0, y AnalysisKit, HeadRushKit, MatchKit y Tone3000Kit 1/0. Quedan saltos `[windows]` justificados (sin GPU DirectX 12 en la VM, CoreMedia, etiquetas ID3, `posixPermissions` en NTFS, zips de modelos no sincronizados, FoundationNetworking sin `file://`, sin AudioToolbox) y de variables de entorno (`TF_MODEL_TESTS` y similares). `tf-audio.exe` y `tf-video.exe` compilan como PE x64; `tf-audio devices` lista los dos endpoints HDA con su driver y mínimo de 128 muestras en compartido y exclusivo. Con modelo real (`TF_MODELS_DIR=C:\tf-models`): pose MoveNet frente a Vision error medio 0,0251 (umbral 0,05), 75,9 ms por fotograma; encuadre 126 ms por muestra. Falta, en un PC: DirectML y tiempos sin emulación, latencia y `verify` con la Flex Prime, `tf-video sync` con cámara, HEVC por hardware y el oído (ver «Pendiente tras el paso 7»).*
- [ ] Interfaz WebView2: anfitrión, puente con el núcleo Swift y las 7 pantallas.
- [ ] Instalador de Windows (solo x64 desde el 19-20/11/2026; antes unificado ARM64 y x64 en un solo `.exe`) publicado como release en GitHub, como la v1.0 de macOS. GitHub Actions (`windows-latest`) solo si la compilación x64 desde la VM no sale limpia; en repo privado sus minutos de Windows cuentan doble. El instalador cumple el requisito de la Fase 7d (modo silencioso, por usuario, cerrar y relanzar la app).
  - *Retirado el 20/11/2026 («abandonamos ARM64»): un solo instalador x64; sin `IsWow64Process2` ni `/ARCH`. Se conservan el modo silencioso, la instalación por usuario y cerrar y relanzar la app. Lo que sigue es la decisión original, por historia.*
  - Unificado (decisión de Jorge, 19/11/2026): lleva las dos arquitecturas y decide al instalar cuál copia según la máquina nativa del equipo, leída con `IsWow64Process2` (no con `PROCESSOR_ARCHITECTURE` ni con `GetNativeSystemInfo`, que dan x64 si el propio instalador corre emulado en ARM64). El instalador en sí es x64 o x86 para arrancar en los dos (Windows 11 ARM emula x64). Solo se instala una arquitectura: ejecutable, DLL de Swift, ONNX Runtime y DirectML, helpers (yt-dlp, Deno, ffmpeg) y shims de NativeKit de la que toque; lo que no depende de la arquitectura (páginas de la interfaz WebView2, SoundFont, recursos) va una vez. Los modelos ONNX no van dentro: se bajan aparte (`models-win-v1`).
  - *Retirado el 20/11/2026 (solo x64).* Forzar arquitectura con un parámetro (`/ARCH=x64` o `/ARCH=arm64`, también en modo silencioso), para probar la x64 en la VM ARM64; forzar ARM64 en un equipo x64 se rechaza con un mensaje claro. Una reinstalación o actualización conserva la arquitectura instalada salvo que se fuerce otra, y al cambiar borra la anterior.
  - Tamaño medido al hacerlo (el doble de binarios nativos, más o menos); si pasa de lo razonable para prestarlo a los amigos, se vuelve a Jorge antes de partirlo en dos.

Mini-spec de los pasos 1 y 2 (18/11/2026):

- **VM.** UTM 5.0.9. VM `ToneForge-Win11` en `/Volumes/SSD Mac/VMs/` (al disco interno le quedan 41 GB; decisión de Jorge, 18/11/2026). QEMU aarch64 con hipervisor, UEFI, TPM 2.0 y RNG; 4 núcleos, 8 GB; disco NVMe de 100 GB (qcow2, crece según se usa); dos unidades USB extraíbles, una con la ISO de Windows 11 ARM64 en español (España) y otra con las guest tools; red compartida (NAT, 192.168.64.0/24). La ISO se baja a mano porque Microsoft rechaza la descarga por script (SentinelReject).
- **Control desde el Mac.** Claude Code sigue en el Mac y no se instala en la VM. Se usa OpenSSH Server de Windows (alias `tf-win` en `~/.ssh/config`, clave del Mac, PowerShell como shell) y, de reserva, el agente QEMU de las guest tools (`utmctl exec`). Las capturas de la VM se hacen con PowerShell y se traen por `scp` para juzgarlas en el hilo principal.
- **Paso de ficheros.** `git ls-files` empaquetado con tar por ssh a `C:\tf` (ruta corta, sin espacios). Se compila siempre en la copia local. La carpeta compartida de UTM (WebDAV) queda solo de reserva.
- **Instantánea `windows-limpio`:** Windows instalado, guest tools y SSH, sin toolchain.
- **Toolchain.** No por `winget`: falla en sesión SSH (0x8a15000f «Data required by the source is missing»), porque el índice AppX no se registra fuera de una sesión interactiva. Se usan los instaladores directos `aka.ms/vs/17/release/vs_BuildTools.exe` (VC.Tools.ARM64, VC.Tools.x86.x64, SDK de Windows 11) y el `.exe` de swift.org para Windows ARM64, la versión estable vigente. Las versiones se anotan en `docs/probes/P8-windows.md`.
- **Prueba del toolchain.** Un «hola mundo» SwiftPM compilado en ARM64 nativo y con `swift build --arch x86_64` para x64; `dumpbin /headers` confirma la máquina y el x64 arranca con la emulación de Windows ARM. `--triple` no sirve: SwiftPM 6.4 lo ignora y saca ARM64. El x64 se compila con `--static-swift-stdlib`, porque el instalador ARM64 no instala el runtime x64. Al terminar, instantánea `toolchain`.
- **Licencias.** Windows sin activar para pruebas. Build Tools con los términos de Visual Studio Community (desarrollador individual, apps propias).
- **Orquestación propuesta.** El hilo principal (Opus) orquesta y monta la VM y el toolchain con Jorge (pasos 1-2, sin subagente). El script `Tools/` de compilar, instalar y arrancar en la VM va a `tf-implementer`. Prueba de viabilidad: `cavecrew-investigator` hace el inventario de dependencias de Apple por paquete, `web-researcher` investiga el estado de Swift en Windows, la interfaz, WASAPI/ASIO y los helpers, `tf-engineer` evalúa señal, audio y vídeo, y `tf-ml` lleva los modelos a ONNX Runtime en Windows. Después, `tf-docs` escribe P8 y el ADR, y `tf-qa` añade la compilación de Windows a su verificación.

Mini-spec del paso 3 (18/11/2026):

- **Un comando.** `Tools/win/build.sh [--package <ruta del repo>] [--product <nombre>] [--arch arm64|x64|both] [--gui] [--no-run] [--clean] [--stop]`, desde el Mac. Por defecto, paquete `Tools/win/smoke`, las dos arquitecturas y arrancar en consola. Salida resumida como `Tools/test.sh` (una línea por etapa: VM, ficheros pasados, compilación de cada arquitectura con segundos, máquina PE, salida del programa y código); el log completo va a `Temp/logs/win-<fecha>.log`. Códigos: 0 bien, 1 falla el programa, 2 falla la compilación, 3 VM o ssh inaccesibles.
- **VM.** Si `ToneForge-Win11` está parada, `utmctl start` y espera a que responda `ssh tf-win` (con tope de tiempo). No toca las instantáneas. `--stop` la apaga al acabar; si no, la deja encendida.
- **Paso de ficheros.** `git ls-files -co --exclude-standard` (rastreados con su contenido del árbol de trabajo, más los nuevos no ignorados) empaquetados con el `tar` del Mac (`COPYFILE_DISABLE=1`, sin xattrs), `scp` del tar y extracción con el `tar.exe` de Windows en `C:\tf`. Se sobrescribe sin borrar, para conservar los `.build` y compilar incremental; `--clean` borra `C:\tf` antes (y con él los `.build`).
- **Compilación en la VM.** Un `.ps1` versionado en `Tools/win/remote/`, que llega con el resto del repo y se ejecuta por ssh; nada de PowerShell complejo en línea. Recarga el PATH de Machine y User, y compila en la copia local: ARM64 con `swift build -c release --static-swift-stdlib` y x64 con `--arch x86_64 --static-swift-stdlib`, comprobando `$LASTEXITCODE` tras cada una. Los `.ps1` en ASCII (PowerShell 5.1 lee como ANSI los ficheros sin BOM).
- **Instalación.** Copia el ejecutable del producto (y las `.dll` y carpetas `.resources` que haya junto a él) a `C:\ToneForge\arm64\` y `C:\ToneForge\x64\`, y lee la máquina de la cabecera PE (0xAA64 y 0x8664) para confirmarla sin `dumpbin`.
- **Arranque.** En consola, por ssh, capturando la salida y el código de cada arquitectura. Con `--gui`, en la sesión interactiva del usuario `tf` mediante una tarea programada (`/IT`), porque la sesión ssh no tiene escritorio; la salida estándar va a un fichero, se trae por `scp` y se hace una captura de pantalla a `Temp/win/`. Si `tf` no tiene sesión iniciada, lo dice y sale con 3.
- **Paquete de humo `Tools/win/smoke`.** SwiftPM mínimo con Foundation, un ejecutable que imprime arquitectura, versión de Windows, locale y un `NumberFormatter(.decimal)`, y con `--wait <s>` se queda abierto para la captura en modo `--gui`.
- **Verificación.** `Tools/win/build.sh` con la VM parada: arranca, compila las dos, la máquina PE es la correcta y las dos imprimen; `--gui` deja captura; una segunda ejecución sin cambios compila incremental (más rápida).

Mini-spec del paso 4, prueba de viabilidad (18/11/2026):

- **Fallar rápido, por orden.** (1) Barrido de compilación: cada paquete de `Packages/` con `Tools/win/build.sh --package Packages/<Kit> --arch arm64 --no-run`; la x64 solo de los que compilen (los errores de Apple no dependen de la arquitectura). Tabla paquete · compila · primer error. Con `--no-run` en una biblioteca, la instalación falla por falta de ejecutable: manda la línea `BUILD`, no el código de salida. (2) A la vez, sin VM: inventario de lo que depende de Apple por paquete y target, y estado del arte en internet. (3) Con (1) y (2): señal, audio y vídeo, y modelos con ONNX Runtime.
- **Corte.** Un bloqueo duro (sin interfaz viable, sin forma de ejecutar el modelo de separación, sin audio de E/S usable) para lo que dependa de él y se informa a Jorge en el momento, sin completar el resto.
- **Qué devuelve cada subsistema.** Pieza de Apple que se usa, sustituto en Windows, esfuerzo (S/M/L), riesgo y la prueba hecha (o por qué no se puede hacer en la VM). Latencia de audio, Flex Prime y cámara no se miden en la VM: quedan como pruebas para Jorge en un PC.
- **Sin tocar los paquetes.** Las pruebas mínimas van a `Probes/P8-windows/` (SwiftPM o scripts) y se compilan con `build.sh --package Probes/P8-windows/<prueba>`. El código de `Packages/` y `App/` no cambia en este paso.
- **VM compartida.** `build.sh` usa siempre `C:\tf`: un solo usuario a la vez. Durante el barrido, solo el hilo principal; después, `tf-engineer` y `tf-ml` se turnan con un cerrojo (`mkdir Temp/win/vm.lock` antes, `rmdir` al acabar).
- **Reparto (orquestación aprobada).** `cavecrew-investigator`: inventario de Apple. `web-researcher`: Swift en Windows, interfaz, WASAPI/ASIO, cámara y vídeo, helpers, ONNX Runtime y empaquetado (notas en `Temp/research/windows-port.md`). `tf-engineer`: señal (Accelerate), audio (AVAudioEngine/Core Audio) y vídeo (AVFoundation). `tf-ml`: modelos de P4 con ONNX Runtime en Windows (ARM64 y x64 emulada), comparados con la salida de Core ML. Barrido, integración y decisión de seguir: hilo principal.
- **Resultado.** Sección «Prueba de viabilidad» de `docs/probes/P8-windows.md` (tabla por paquete y por subsistema) y un ADR con las opciones y una recomendación, escritos por `tf-docs`. Decide Jorge; el alcance (paso 5) sale de esa decisión.

Mini-spec del port (pasos 6-8, 18/11/2026; ADR-020). **Solo x64 (decisión de Jorge, 19-20/11/2026: «abandonamos ARM64»):** el código ARM64 no se borra pero deja de ser puerta, QNN queda fuera de la cadena automática (solo con `TF_ONNX_PROVIDER=qnn`) y las menciones a ARM64 de abajo quedan como historia.

- **Orden.** (1) Capa de plataforma, que bloquea todo lo demás. (2) Piezas de Windows por subsistema, en paralelo cuando no se pisen. (3) Interfaz WebView2, cuyo esqueleto y puente pueden empezar a la vez que (2). (4) Instalador unificado ARM64/x64. Lo que depende de hardware real (E/S de audio en vivo y latencia con la Flex Prime, cámara, HEVC, velocidad en GPU/NPU) se programa ya y se valida cuando Jorge tenga un PC.
- **Capa de plataforma.** El código de macOS no cambia de comportamiento: lo atado a Apple queda detrás de protocolos dentro de cada paquete, con la implementación actual en ficheros `#if canImport(...)`/`#if os(macOS)` y la de Windows en `#if os(Windows)`. Las dependencias C vendorizadas (código fuente, sin binarios en git) van en un paquete nuevo `Packages/NativeKit`: pocketfft, dr_wav/dr_mp3/dr_flac, shim WASAPI, shim Media Foundation, cabeceras de la API C de ONNX Runtime, Signalsmith Stretch, TinySoundFont y el remuestreador. CryptoKit → swift-crypto en los dos sistemas si da los mismos hashes; si no, solo en Windows. `Store` sustituye SwiftData en Windows (índice en JSON o SQLite, a decidir en la parte). Puerta: `Tools/test.sh` verde en el Mac y, en la VM, compilación y tests de cada paquete; `Tools/win/build.sh` gana `--test` (`swift test` en la VM, salida resumida).
- **Señal.** pocketfft + capa DSP en Swift con las operaciones de vDSP que se usan; remuestreo libsoxr (LGPL) o r8brain (MIT), validado con los fixtures de Python de pulso y acordes. En el Mac sigue vDSP.
- **Audio.** Decodificación con dr_*. E/S dúplex con WASAPI propio (IAudioClient3 o exclusivo, por eventos) con marcas QPC por búfer, para conservar la medida de latencia y el alineado actuales; miniaudio solo si basta para la reproducción. Reloj QPC en vez de `mach_absolute_time`. Reproductor: mezclador propio + Signalsmith Stretch. Sintetizador de la tablatura: TinySoundFont. ASIO fuera.
- **Modelos y aceleración.** ONNX de los seis modelos (separación, lead/rhythm, Beat This!, BTC, Basic Pitch, batería) en una release `models-win-v1`, comparados con Core ML como en P8. Proveedor elegido en tiempo de ejecución: se enumeran las GPU con DXGI (fabricante y VRAM) y se intenta, por orden, ~~QNN (NPU Snapdragon, solo ARM64; retirado de la cadena automática el 19/11/2026)~~, CUDA (si está instalado), DirectML (cualquier GPU DirectX 12, ARM64 y x64) y CPU, pasando al siguiente si la sesión no se crea. La primera vez en cada equipo, un fragmento fijo se compara entre GPU y CPU con el umbral de P8; si no cuadra, ese modelo queda en CPU en ese equipo y se recuerda. CUDA (proveedor CUDA de ONNX Runtime con CUDA 12 y cuDNN 9, unos 1-2 GB) no va dentro del instalador: el instalador (en las dos arquitecturas; NVIDIA N1X «RTX Spark» trae GPU NVIDIA en Windows ARM64 y CUDA 13.4 ya soporta Windows on Arm) detecta una GPU NVIDIA (WMI, fabricante 0x10DE) y la versión del driver y, si es compatible, lo descarga durante la instalación a una carpeta aparte; también se puede bajar después desde Ajustes (decisión de Jorge, 18/11/2026). Se comprueba en la parte del instalador si la licencia de NVIDIA permite redistribuir esas DLL desde una release propia; si no, se descargan de los servidores de NVIDIA. También se comprueba si ONNX Runtime publica el proveedor CUDA para Windows ARM64; mientras no lo haga, en ARM64 la GPU NVIDIA va por DirectML. En la VM, DirectML sobre WARP prueba detección, cambio de proveedor y resultados, no la velocidad.
- **Vídeo.** Captura con Media Foundation SourceReader y marcas QPC; escritura y exportación con IMFSinkWriter (H.264 por defecto; HEVC si hay codificador), con el AAC sin compensar (decisión de Jorge, 19/11/2026; antes «compensando los 44 ms»: es AVFoundation quien recorta 2112 muestras al leer, MF y ffmpeg dan 0 ms) y la tolerancia de medio fotograma; composición con Direct2D + DirectWrite; encuadre con MoveNet o RTMPose en ONNX Runtime en vez de Vision.
- **Helpers y sistema.** `Tools/helpers/fetch.sh` baja yt-dlp, Deno y ffmpeg (BtbN LGPL) para Windows ARM64 y x64, verificando las versiones ARM64 que las notas web daban sin comprobar. `Process` con Job Object para que mueran los nietos. Rutas en `%LOCALAPPDATA%\ToneForge`. Locale con `GetUserDefaultLocaleName` pasado a los formateadores.
- **Interfaz.** Ventana Win32 desde Swift con WebView2 (runtime evergreen de Windows 11) por un shim C/COM; puente JSON entre la página y el núcleo Swift. Las pantallas parten de los bocetos `docs/design/*.dc.html` y de la tablatura web que ya usa `TabWebHost`. Tecnología de la página (sin framework o uno ligero) a decidir en la parte.
- **Reparto (según «Modelos por fase»).** Capa de plataforma y piezas de señal, audio, vídeo y aceleración: `tf-engineer`. ONNX de los modelos y su validación: `tf-ml`. Helpers, `--test` de build.sh, Store e interfaz: `tf-implementer`. `tf-qa` añade la compilación y los tests de Windows a su verificación.
- **Condición de paso (aprobada por Jorge el 18/11/2026; «ARM64 y» retirado el 20/11/2026).** En la VM, x64: importar un tema por enlace, separarlo, ver acordes y tablatura y reproducirlo en bucle al 70 %, con la interfaz WebView2; grabación y montaje probados en la VM hasta donde da sin cámara ni audio reales. Lo de hardware queda como lista de pruebas para el PC.

Corte del paso 6, capa de plataforma (aprobado por Jorge el 18/11/2026, con sus tres desvíos: DSP y dr_* adelantados, SourceKit y ModelKit a Sonnet, Store elige JSON o SQLite):

- **Qué entra.** Las costuras (protocolos e `#if`) de todos los paquetes, y en Windows lo barato y ya probado en P8: la fachada DSP sobre pocketfft y la decodificación con dr_* (se adelantan de la pieza «señal» y «audio» del paso 7 porque sin ellas casi ningún test numérico corre en la VM), CryptoKit → swift-crypto, reloj QPC, `Process` con Job Object y el índice de `Store`. Lo demás (WASAPI, reproductor y Signalsmith, TinySoundFont, remuestreador, ONNX Runtime, Media Foundation, Direct2D, encuadre) queda en Windows como un stub que lanza `PlatformError.unsupported("paso 7: <pieza>")`, y sus tests se saltan en Windows con `XCTSkip("[paso 7] <pieza>")`. `--test` cuenta los saltos, para que el paso 7 los vaya bajando a cero. `App/` no se toca (es la de macOS; la de Windows es el paso 8).
- **Regla del Mac.** Cero cambio de comportamiento: lo de Apple sigue llamándose igual, solo que detrás de la fachada o en un `#if canImport(...)`. La fachada DSP en el Mac pasa directa a vDSP.
- **NativeKit** (`Packages/NativeKit`, nuevo). Objetivos C, con fuentes vendorizadas y su licencia: `CPocketFFT`, `CDrAudio` (dr_wav, dr_mp3, dr_flac) y `CMiniz` solo si `SourceKit` usa `Compression` para zlib/deflate. Objetivos Swift: `NativeDSP` (las 46 operaciones de vDSP/vForce que usan `AudioKit`, `StemKit`, `StudyKit` y `TabKit`, con dos motores: `vDSP` en el Mac y portátil en Swift + pocketfft en todos; en el Mac los tests comparan los dos motores operación por operación), `NativeAudioFile` (leer y escribir WAV/FLAC/MP3 a `Float` mono o multicanal; `AVAudioFile` en el Mac, dr_* en Windows) y `NativePlatform` (`HostClock` con `mach_absolute_time` o QPC y la misma unidad, `ChildProcess` con `Process` + grupo de procesos en el Mac y Job Object en Windows, carpeta de soporte con `Application Support` o `%LOCALAPPDATA%\ToneForge`). Los shims de WASAPI, Media Foundation, ONNX Runtime, Signalsmith y TinySoundFont llegan a NativeKit en el paso 7.
- **swift-crypto** como dependencia condicionada a Windows (`.when(platforms: [.windows])`) e `#if canImport(CryptoKit)`; un test con vectores conocidos confirma los mismos hashes en los dos sistemas.
- **`Tools/win/build.sh --test [--filter <X>]`.** `swift test` del paquete en la VM, ARM64 nativo y x64 (`--arch x86_64`, emulada; `swift test` no admite `--static-swift-stdlib`, así que el runner x64 carga las DLL x64 del runtime de Swift, sacadas una vez de `Redistributables` a `C:\tf-rtl-x64` por `remote/x64-runtime.ps1`); sin instalar ni arrancar. Salida resumida por arquitectura: pasados, fallados, saltados (con su etiqueta `[paso 7]`) y los fallos con fichero:línea; log en `Temp/logs/`. Códigos como `test.sh`: 0, 1 fallos, 2 compilación, 3 VM. Y `build.sh` toma él mismo el cerrojo `Temp/win/vm.lock` (espera con tope y lo suelta aunque falle), para que ningún agente dependa de acordarse.
- **Partes, olas y agentes.** Todas en el mismo árbol de trabajo; cada agente toca solo su paquete (más su `Package.swift`) y prueba con `Tools/test.sh <Paquete>`, nunca la suite entera.

| Parte | Ola | Agente | Contenido |
|---|---|---|---|
| 6.0 NativeKit | 1 | `tf-engineer` | Paquete nuevo de arriba, con sus tests en el Mac y en la VM |
| 6.1 `--test` y cerrojo | 1 | `tf-implementer` | `build.sh` y `Tools/win/remote/test.ps1` |
| 6.2 Store | 1 | `tf-implementer` | SwiftData → índice propio en Windows (JSON o SQLite, lo decide la parte con el tamaño real del índice), CryptoKit, CoreGraphics |
| 6.3 SourceKit | 2 | `tf-implementer` | Darwin `kill`/`pid_t` → `ChildProcess`, `Compression`, CryptoKit, DispatchSource; son conectores y lo delicado ya está en NativeKit |
| 6.4 ModelKit | 2 | `tf-implementer` | CoreML detrás de un protocolo (stub en Windows), `ditto` → `tar.exe`, CryptoKit, descarga con FoundationNetworking |
| 6.5 AudioKit | 2 | `tf-engineer` | HAL y `AVAudioEngine` detrás de protocolos (stub en Windows), análisis sobre `NativeDSP`, `HostClock`, `Mutex` |
| 6.6 StudyKit | 2 | `tf-engineer` | LogMel y CQT sobre `NativeDSP`, CoreML detrás de protocolo, `MonoResampler` (stub), `StudyPlayer` (stub), decodificación con `NativeAudioFile` |
| 6.7 TabKit | 2 | `tf-engineer` | Igual que StudyKit, más `TabSynthRenderer` (stub) |
| 6.8 StemKit | 2 | `tf-engineer` | STFT sobre `NativeDSP`, CoreML detrás de protocolo, `tf-separate` y `tf-memhog` (`arc4random_buf`, SIGTERM, `ChildProcess`) |
| 6.9 VideoKit | 3 | `tf-engineer` | Depende de AudioKit: captura, escritor, compositor, exportador y encuadre detrás de protocolos (stubs), `HostTimeMap` sobre `HostClock` |

- **Por qué así.** NativeKit lo usan casi todos, así que la ola 2 espera a la 6.0; la 6.1 y la 6.2 no dependen de ella y van a la vez. En la ola 2, NativeKit queda congelada: si a una parte le falta una operación, la añade en un fichero suyo `NativeDSP/Extra<Paquete>.swift` y lo dice en su informe. SourceKit y ModelKit van a Sonnet, aunque la mini-spec da la capa de plataforma a `tf-engineer`, porque son fontanería sin señal.
- **Puerta de cada parte.** `Tools/test.sh <Paquete>` verde en el Mac (y `Tools/test.sh App` compila), el paquete compila en la VM en ARM64 y x64 (al iterar, solo ARM64 con `--arch arm64`; las dos en una pasada final, decisión de Jorge del 18/11/2026 para no tener la VM ocupada con la x64 emulada; cerrojo por paquete y más núcleos para la VM, a valorar en el paso 7) y, con `--test` ya disponible, sus tests pasan en las dos con los saltos `[paso 7]` listados. **Puerta del paso 6:** `tf-qa` una vez, con la suite entera del Mac y `--test` de los 13 paquetes en la VM; después `tf-docs` (CODEMAP con NativeKit, P8, casilla).

Tareas que el paso 6 deja al paso 7 (19/11/2026), además de la lista de piezas de la mini-spec; cada una baja saltos `[paso 7]` de `--test`:

- **Enlace estático con `curl.lib`.** `--static-swift-stdlib` con FoundationNetworking falla porque el toolchain trae `libcurl.lib`. Remedio: copia o alias `curl.lib` con `-Xlinker /LIBPATH:`, o enlace dinámico con DLL; revisar zlib y libxml2. Afecta al ejecutable de la app de Windows; `tf-fetch` (de desarrollo) queda fuera.
- **Parada ordenada de `tf-separate`.** No hay SIGTERM entre procesos en Windows y `TerminateJobObject` deja carpetas `.tf-separate-*`. Propuesta: un evento con nombre que vigile el helper (1 salto `[paso 7]` parada).
- **Reproductor.** Costura `StudyPlaybackEngine` (cargar stems, play/pausa, buscar, velocidad, tono, volumen por stem), mezclador propio y Signalsmith. Hoy `StudyPlayer`, `StemFeed`, `StemScheduler`, `HostedRenderer` y `ClickRenderer` no existen en Windows; 4 pruebas de grabación alineada (`AudioSessionTests`, `TakeAlignmentTests`, `FeedbackLoopTests`) esperan a esta costura.
- **Vídeo.** Captura con `IMFSourceReader` (marcas QPC de 100 ns → ticks QPC → `HostClock.seconds`), escritor HEVC con PTS = tiempo del tema a 90 000 (`IMFSinkWriter`) y exportador; compositor Direct2D con protocolos nuevos para `MontageRenderer` (hoy devuelve `CIImage`) y `MontagePreview` (sus miembros son de AVFoundation); `TakePreview.plan` como tipo puro que se pueda probar en Windows; encuadre (pose); `tf-video` en Windows (usa `CoreAudioIO.ensureInputPermission`); `FramePixelBuffer` real.
- **Pruebas de Jorge en un PC (con la Flex Prime y cámara).** `tf-audio latency --restarts 10` sobre WASAPI con variación entre arranques < 0,25 ms (como el Mac; el 0,2 original se corrigió el 21/11/2026); `tf-video sync` con cámara.
- **VM.** Cerrojo por paquete y más núcleos, a valorar para no tener la VM ocupada. *Resuelto en el corte del paso 7.*

Límite conocido: la VM vale para comprobar que arranca, la interfaz y la lógica; la latencia de audio, la Flex Prime por USB y la cámara no se miden en una VM y las prueba Jorge en un PC con Windows.

Corte del paso 7, piezas de Windows (aprobado por Jorge el 19/11/2026). **Cambio de alcance (19-20/11/2026): solo x64.** Donde abajo se lee ARM64 o «las dos arquitecturas», la puerta es solo x64 (`--arch x64`, emulada en la VM); el código ARM64 se conserva sin ser puerta.

- **Qué entra.** Implementación en Windows de todo stub `paso 7:`; los 114 saltos `[paso 7]` bajan a 0 o a `[windows]` justificado. `App/` no se toca.
- **Regla del Mac.** Cero cambio de comportamiento: código nuevo solo en `#if os(Windows)` o en objetivos nuevos de NativeKit. Las costuras nuevas (`StudyPlaybackEngine`, protocolos de `MontageRenderer` y `MontagePreview`, `TakePreview.plan` como tipo puro) mantienen la API compatible en fuente y `Tools/test.sh App` compila.
- **Propiedad.** Un agente por paquete a la vez. Tras la 7.0 el `Package.swift` de NativeKit queda congelado y cada parte toca solo el directorio de su objetivo.

| Parte | Ola | Agente | Contenido | Saltos que baja |
|---|---|---|---|---|
| 7.0 Base NativeKit | 0 | `tf-implementer` | Todos los objetivos de una vez, con fuentes vendorizadas, licencia y esqueleto vacío: `CResampler` (r8brain), `CSignalsmith`, `CTinySoundFont`, `CWASAPI`, `CMediaFoundation`, `CDirect2D`, `COnnxRuntime`, y los Swift `NativeResample` y `NativeONNX` con la firma pública ya fijada. Script que baja ONNX Runtime y DirectML de NuGet con SHA a `Vendor/` | 0 |
| 7.1 Remuestreador | 1 | `tf-engineer` | r8brain (MIT) primero, validado con los fixtures de pulso y acordes antes de cablear; libsoxr (LGPL) solo de respaldo, como DLL. NativeKit, AudioKit (`AudioImporter`, `TakeResampling`) y StudyKit | remuestreador 19 |
| 7.2 Vídeo MF | 1 | `tf-engineer` | `CMediaFoundation` y VideoKit: captura con `IMFSourceReader` y marcas QPC, escritor, exportador con el AAC sin compensar (antes «con los 44 ms compensados»; decisión de Jorge, 19/11/2026), `FramePixelBuffer` real | media-foundation 11 |
| 7.3 Modelos ONNX | 1 | `tf-ml` | Los 6 modelos más el de pose (MoveNet o RTMPose), comparados con Core ML con el umbral de P8; prueba de un trozo de separación intermedio (T entre 345 y 1151) con tope de tiempo, y si no sale se queda el de 4 s. En el Mac; la VM solo para `ort-smoke`. Los modelos pasan a la VM por `scp`; la release `models-win-v1` NO se publica todavía (decisión de Jorge, 19/11/2026: antes quiere hacer mejoras globales). Umbrales: misma red SNR ≥ 60 dB; frente a Core ML argmax ≥ 99 % (umbral 100 %) o SDR ≥ 15 dB; pose ≤ 0,05. Separación con T=345 por defecto y T=575 con ≥ 16 GB. Pendiente al publicar: añadir `pose.onnx` al catálogo de ModelKit y a la release (hoy se lee de `<TF_MODELS_DIR o C:\tf-models>\pose\model.onnx`) | 0 |
| 7.4 Sintetizador | 1 | `tf-engineer` | TinySoundFont tras `TabSynthBackend` con el mismo SoundFont del Mac, y el remuestreador de `MonoAudio` en TabKit contra la firma de la 7.0 | sintetizador 11, remuestreador 2 |
| 7.5 Helpers y sistema | 1 | `tf-implementer` | `Tools/helpers/fetch.sh` para Windows ARM64 y x64, enlace estático con `curl.lib`, papelera de reciclaje en Store | 0 (stubs sin salto) |
| 7.6 Reproductor | 2 | `tf-engineer` | AudioKit: costura `StudyPlaybackEngine`, mezclador propio, Signalsmith, y `StemFeed`, `StemScheduler`, `HostedRenderer` y `ClickRenderer` en Windows; recupera las 4 pruebas de grabación alineada a 1 muestra | reproductor 36 |
| 7.7 WASAPI | 2 | `tf-engineer` | `CWASAPI` y un probe propio `Probes/P8-windows/wasapi`; aún no entra en AudioKit | 0 |
| 7.8 ONNX Runtime | 2 | `tf-engineer` | `NativeONNX` (sesión, DXGI → QNN / CUDA / DirectML / CPU, comparación GPU-CPU recordada por equipo), ModelKit, StudyKit, TabKit, StemKit, y la parada ordenada de `tf-separate` con evento con nombre | onnx-runtime 17, remuestreador 2, parada 1 |
| 7.9 Compositor | 2 | `tf-engineer` | `CDirect2D` y VideoKit: protocolos para `MontageRenderer` y `MontagePreview`, `TakePreview.plan` como tipo puro | direct2d 14, reproductor 1 |
| 7.10 WASAPI en AudioKit | 3 | `tf-engineer` | `WASAPIAudioIO` real y `tf-audio` en Windows (con listado de dispositivos) | 0 |
| 7.11 Encuadre | 3 | `tf-engineer` | Pose sobre `NativeONNX`, `tf-video` en Windows | 0 propios (3 stubs) |

- **Por qué así.** AudioKit lo tocan tres partes y va en serie (7.1 → 7.6 → 7.10); VideoKit igual (7.2 → 7.9 → 7.11). El reproductor no depende de WASAPI (las pruebas alineadas usan `SimulatedAudioIO`), solo del remuestreador. WASAPI tiene 0 saltos y la VM no tenía dispositivo de audio: se desarrolla en un probe y entra en AudioKit al final. Dependencias: 7.0 antes que todo; 7.1 antes que 7.6 y 7.8; 7.3 antes que 7.8 y 7.11; 7.2 antes que 7.9; 7.6 y 7.7 antes que 7.10.
- **VM.** Cerrojo global (el paso de ficheros reescribe todo `C:\tf`, así que un cerrojo por paquete no vale). La VM sube a 6 núcleos y sigue con 8 GB (el Mac tiene 5+6 núcleos y 18 GB); se intenta añadir una tarjeta de sonido virtual para que WASAPI abra un dispositivo. Los tests con modelo, de uno en uno y con la VM en exclusiva (pico de 5,6 GB en la separación).
- **Fuera del corte.** Las etiquetas de título y artista con dr_* (`AudioImporter`): se queda el nombre del fichero, como límite `[windows]`.
- **Puerta de cada parte.** Como en el paso 6: `Tools/test.sh <Paquete>` verde en el Mac, `Tools/test.sh App` compila, `--test --arch x64` (ARM64 retirado el 20/11/2026), con sus saltos `[paso 7]` a cero. **Puerta del paso 7:** `tf-qa` una vez (suite del Mac y `--test` de los 13 paquetes en la VM); después `tf-docs`.
- **Para Jorge, sin PC (en el Mac).** WAV del reproductor al 70 % (Signalsmith frente a TimePitch) y del sintetizador, con nombres `CHECK_*.wav` únicos; MP4 de Media Foundation con `mp4check`.
- **Para Jorge, en un PC.** `tf-audio latency --restarts 10` (compartido y exclusivo, variación < 0,25 ms, como el Mac; el 0,2 original se corrigió el 21/11/2026); `tf-audio verify` 60 s (< 1 ms por clic); listado de dispositivos de `tf-audio` (línea Driver y periodo mínimo; entregado por la 7.10); `tf-video sync` (< medio fotograma); exportar un montaje y listado de codificadores (HEVC por hardware; 7.2); `ort-smoke <dir> --runs 3` en CPU y con selector de proveedor (7.8); un tema entero con 16 GB.

Pendiente tras el paso 7 (hallazgos sin tocar, 21/11/2026; van al paso de la interfaz o a arreglos):

- `AudioSession.close()` (`AudioSession.swift`) no suelta el reproductor alojado, y el portátil se desengancha en un `Task` asíncrono (`PortableStudyPlayer.swift`): en Windows los ficheros de stems siguen abiertos un rato tras cerrar la sesión y no se pueden borrar ni reescribir. `tf-video` lo esquiva con `player.detach()`.
- La clave de calibración no distingue compartido de exclusivo (hoy `calibration-exclusive.json` aparte) y `AudioSetup` no sabe marcar dos ids de WASAPI como el mismo aparato (`clock` siempre `.single`).
- `tf-separate`: unos 10 s de inferencia pura por trozo T=345 frente a 15,5-17,5 s medidos; 4-8 s por trozo fuera del modelo (¿arena de ORT apagada, ¿DSP portátil?). Falta un desglose por etapa. Hilos de ORT medidos en la VM (trozo T=345, CPU x64 emulada, con el Mac cargado, deriva de ~17 %): automático 10,1-11,9 s; 6 hilos 10,6 s; 4 → 9,7 s; 3 → 13,6 s; 2 → 15,8 s. El automático ya es óptimo: no se fijan hilos.
- En `rotulo` la caja del título tapa el chip «Parte A» en las dos plataformas (decidir si va a arreglos generales).
- `models-win-v1` sin publicar; al publicarla, añadir `pose.onnx` al catálogo de ModelKit y a la release.
- Para Jorge, en un PC (se añade a la lista del corte): `tf-audio devices` (línea Driver) y `tf-audio latency --restarts 10 --mode exclusive` además de compartido; DirectML (`TF_ONNX_PROVIDER=DirectML … ort-smoke.exe C:\tf-models\bs_roformer --runs 3`, DLL en `C:\tf-ort-dml\x64`); tiempos de separación sin emulación (en la VM ~9-10× tiempo real); `tf-audio verify`; `tf-video sync`; exportar un montaje. Sin escuchar: `Temp/win/listen/CHECK_synth_*`, `CHECK_player_*` y `CHECK_ortmodels_*`.

Tiempos del paso 7 (VM x64 sana con `dotpr` nuevo; el Mac en Debug). El tope de 15 s de reloj de `calibrateLatency` se deja como estaba. Release no mueve la separación (es ONNX Runtime en CPU emulada).

| Qué | Debug x64 | Release x64 | Mac (Debug) |
|---|---|---|---|
| Alineado (`AudioSessionTests.testCalibrateRecordAligned…`) | 25,7 s | 7,8 s | 3,19 s |
| Bucle de realimentación (`FeedbackLoopTests.testVerifyTake…`) | 89,5 s | 9,1 s | ~2,6 s |
| `TakeAlignmentTests.testPassCondition…` | 10,7 s | 2,8 s | — |
| Convolución FFT 951 × 2,6 M (con generar entrada) | 1,36 s | 0,033 s | 1,31 s |
| Reproductor alojado 60 s en tiempo real | 59,3 s, pasa | 53,7 s, pasa | pasa |
| Suite AudioKit entera (solo tests) | 490 s | 161 s | 280 s |
| Bombeo de 512 muestras, rig / bucle | 0,70 / 15,8 ms | 0,85 / 9,3 ms (VM lenta) | 0,044 / 0,341 ms |
| `tf-separate` 44,1 kHz / 48 kHz (s por minuto de audio) | 529 / 530 | 622 / 510 | 21,4-22,2 (Core ML, trozo largo, CPU+GPU; P4, `docs/probes/P4-modelos.md`; no medido con `tf-separate` a 48 kHz) |
| Separación: trozo T=345 / pico | 17,5 s / 3436 MB | 15,5 s / 3431 MB | sin dato comparable |
| `lead_rhythm` (s por minuto) | 157 | 139 | sin dato comparable |

SNR frente a ORT del Mac: 119,3 / 118,9 dB. StemKit con modelo en release: 81/0, 9 saltos de bancos opcionales. `docs/probes/P8-windows.md` enlaza a esta tabla.

Condición de paso: la de la mini-spec del port (aprobada por Jorge el 18/11/2026; solo x64).

### Fase 7d · Actualizaciones automáticas (sin rama aún; rama `fase-7d` desde `main` al cerrar la 7c)

Pedida por Jorge el 19/11/2026, solo planeada: la app busca versiones nuevas y ofrece actualizar o saltar esa versión, con el changelog, en macOS y en Windows. Va después de la 7c porque el lado de Windows necesita su instalador (paso 8) y la interfaz WebView2. Estimación: 4 a 6 horas.

Decisiones de Jorge (19/11/2026):

- **Motor: mismo feed, diálogo propio.** Un solo appcast con el formato de Sparkle, firmado con EdDSA (ed25519). En macOS instala Sparkle 2 (MIT), que ya resuelve sustituir el `.app`, pedir permiso de administrador y relanzar, pero con nuestro diálogo SwiftUI a través de `SPUUserDriver`. En Windows, `UpdateKit` (Swift) lee el mismo feed, verifica la firma con swift-crypto (`Curve25519.Signing`, ya es dependencia en Windows) y lanza el instalador; el diálogo es el mismo, en WebView2. Descartados Sparkle + WinSparkle tal cual (diálogos fuera del diseño; el de WinSparkle es Win32 y pinta las notas con el motor de IE) y todo propio (traslocación de Gatekeeper, permisos de `/Applications` y relanzar, a mano).
- **Cuándo: al abrir, cada 24 h y con botón.** Comprueba sola al arrancar y una vez al día si sigue abierta. En Ajustes, «Buscar actualizaciones» y un interruptor para desactivar la comprobación automática. Nunca instala sin preguntar.
- **Changelog: notas de la release de GitHub.** En Markdown, las escribe Jorge (o las redacta Claude y Jorge las aprueba) al publicar; el script de release las pasa a HTML y las mete en el feed. El diálogo enseña las de todas las versiones entre la instalada y la nueva.
- **Un solo canal, estable.** Las pruebas previas se hacen con la compilación local, como ahora.

- [ ] Prueba de Sparkle, lo primero (fallar rápido), en `docs/probes/P9-actualizaciones.md`: dos compilaciones locales (1.0.1 → 1.0.2) servidas desde un feed local, con la app firmada con el equipo de desarrollo y sin notarizar, instalada en `/Applications` por el `.pkg` (queda propiedad de root). Qué se mide: si pide administrador y sustituye la app, si se conservan los permisos de cámara y micrófono (TCC, ligado a la firma), si el requisito designado de la firma (`codesign -d -r-`) cambia al renovar el certificado anual de Apple (si cambia, la primera versión con el certificado nuevo vuelve a pedir esos permisos), si la cuarentena de Gatekeeper molesta, y qué paquete de actualización conviene (`.pkg` o archivo con el `.app`). Si Sparkle no sirve con esta firma, se vuelve a Jorge antes de seguir.
- [ ] `Packages/UpdateKit`: feed (lectura y comparación de versiones), política (cuándo comprobar, versión saltada, «Más tarde»), verificación de firma y descarga, detrás de un protocolo con tres implementaciones: Sparkle en macOS (dependencia solo para macOS), Windows y simulada para los tests (feeds de prueba). Tests en el Mac y en la VM.
- [ ] Diálogo de actualización: boceto `docs/design/Update.dc.html` aprobado por Jorge antes de programarlo; después, versión SwiftUI y versión WebView2.
- [ ] Ajustes → «Actualizaciones» en las dos: versión instalada, «Buscar actualizaciones», interruptor de comprobación automática, última comprobación.
- [ ] Instalación en Windows: bajar el instalador unificado, verificar la firma, lanzarlo en modo silencioso, cerrar la app y que el instalador la relance.
- [ ] Script de release `Tools/release/publish.sh`: compila la de macOS, recoge el instalador de Windows de la VM, firma todo con la clave EdDSA, deja la release de GitHub en **borrador** con las notas y prepara en la rama `gh-pages` el commit del appcast (añadiendo el `<item>` nuevo a los anteriores) sin hacer push. Publicar es siempre un paso de Jorge, en este orden: la release y después el push de `gh-pages`. Un `--retract <versión>` prepara el commit que quita una versión rota del feed. Activar Pages en el repo (rama `gh-pages`) lo hace Jorge una vez.

Mini-spec propuesta (se cierra al empezar la fase):

- **Feed en GitHub Pages** (decisión de Jorge, 19/11/2026): `https://jorge-plk.github.io/Guitar-Tool/appcast.xml`, servido desde una rama `gh-pages` aparte (no `/docs`, para no mezclar el sitio con la documentación). Los instaladores siguen en las releases de GitHub (Pages limita a 100 MB por fichero). Ventajas frente a `releases/latest/download`: URL fija que no depende de qué release es «Latest» (las de modelos no estorban), retirar una versión rota es quitar su `<item>`, el historial vive en un solo fichero y el changelog se corrige sin sacar versión. Orden al publicar: primero la release con los instaladores y después el feed, para que nadie vea una versión que da 404. La caché de Pages tarda unos 10 minutos, que no importa con comprobaciones cada 24 h. Un `<item>` por versión y plataforma (`sparkle:os="macos"` o `"windows"`); en Windows basta uno, porque el instalador es unificado y elige la arquitectura él mismo (7c, paso 8). La app acepta `--update-feed <url>` para probar contra un feed local sin publicar nada.
- **Versión.** Una sola fuente para las dos plataformas: versión visible semver y número de compilación creciente, que es el que compara Sparkle (`sparkle:version`). En Windows va al recurso de versión del `.exe` y del instalador. No se ofrece bajar de versión.
- **Firma.** La clave privada EdDSA se genera con `generate_keys` de Sparkle y vive en el llavero del Mac de Jorge, nunca en el repo; la pública va en `SUPublicEDKey` (Info.plist) y compilada en la de Windows. Además, SHA-256 de cada fichero en el feed. Jorge guarda una copia de la privada fuera del Mac: si se pierde, las copias instaladas no aceptan más actualizaciones y hay que reinstalar a mano. Esta clave no es la de Apple y no caduca. El certificado Apple Development de Jorge (equipo `PAC5B4GH83`) sigue firmando el `.app` y se renueva cada año; Sparkle acepta una actualización con el certificado de Apple cambiado si la firma EdDSA es válida (y al revés), pero no las dos a la vez: nunca se cambia la clave EdDSA en la misma versión en la que se estrena un certificado renovado.
- **Diálogo.** «ToneForge X.Y disponible», versión instalada y nueva, tamaño, changelog acumulado y tres botones: «Actualizar», «Saltar esta versión» y «Más tarde». Después, progreso de descarga y verificación e «Instalar y reiniciar». Saltar oculta esa versión pero no las siguientes; el botón manual de Ajustes enseña también la saltada. «Más tarde» vuelve a avisar en la siguiente comprobación.
- **Cuándo no molesta.** Si hay una grabación, una exportación de montaje o una separación en marcha, el aviso espera a que acabe; instalar no se permite hasta entonces. Sin red: la comprobación automática calla y la manual da un error claro.
- **Datos.** Los proyectos y la carpeta de soporte no se tocan al actualizar. Toda migración del índice de `Store` tiene que leer lo de la versión anterior (ver la nota de datos borrados por un binario atrasado).
- **Requisito para el instalador de Windows (7c, paso 8).** Modo silencioso, instalación por usuario en `%LOCALAPPDATA%` (sin UAC en cada actualización), cerrar la app abierta (Restart Manager) y relanzarla, no volver a bajar CUDA si ya está, y conservar la arquitectura instalada al actualizar.
- **Reparto (propuesto; según «Modelos por fase»).** Orquestador Opus. `web-researcher`: Sparkle 2 con `SPUUserDriver`, actualizaciones con `.pkg` y TCC con firma de desarrollo, y modo silencioso del instalador que elija la 7c. Prueba de Sparkle: hilo principal con `tf-implementer`. `tf-implementer`: UpdateKit, diálogo (SwiftUI y WebView2), Ajustes, instalación en Windows y script de release. `tf-docs` y `tf-qa` al final. Nada pide Opus: no hay señal ni modelos.

Condición de paso (propuesta, a aprobar por Jorge): en el Mac, de una compilación instalada a una más nueva desde un feed de prueba: el aviso sale con el changelog acumulado; «Saltar» oculta esa versión y no la siguiente; «Actualizar» descarga, verifica, instala, relanza y conserva proyectos y permisos de cámara y micrófono; un fichero con la firma alterada se rechaza. Lo mismo en la VM de Windows, en ARM64 y en x64. Sin red, la comprobación automática no dice nada. Con una grabación en marcha no aparece el aviso.

### Fase 7e · Editor de layouts propio (sin rama aún)

Pedida por Jorge el 18/11/2026 (era la 7c hasta que el port a Windows tomó ese número, y la 7d hasta que la tomaron las actualizaciones automáticas). Mini-spec al empezar; sin estimación todavía. No consta en las tablas de orden y modelos hasta que se decida orquestador y agentes (iría después de la 7).

- [ ] Elegir dónde va cada guitarra en el lienzo (layouts propios, además de los cinco fijos)
- [ ] Modos de aparición: empujar (el resto se recoloca) o tapar (el recuadro entra encima)
- [ ] Fundidos al cambiar una guitarra de lado

Condición de paso: por definir con Jorge.

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
| 6 | Fase 7c · Port a Windows | Fase 7b (rama desde `main`) | No | Opus | Sonnet (script de la VM, investigación) · Opus (audio, señal, vídeo; modelos con `tf-ml`) · Haiku (inventario de dependencias) |
| 7 | Fase 7d · Actualizaciones automáticas | Fase 7c (rama desde `main`) | No | Opus | Sonnet (UpdateKit, diálogo, Ajustes, script de release, investigación) |
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
| 7c. Port a Windows | Opus | VM y toolchain en el hilo principal con Jorge; Sonnet (`tf-implementer`) para el script de compilar, instalar y arrancar en la VM; prueba de viabilidad con Haiku (`cavecrew-investigator`, inventario de dependencias de Apple), Sonnet (`web-researcher`, interfaz, WASAPI/ASIO, helpers), Opus (`tf-engineer`, audio, señal y vídeo) y Opus (`tf-ml`, ONNX Runtime); `tf-docs` y `tf-qa` al final | Ida y vuelta con la VM y decisiones de plataforma; lo delicado es sustituir lo que da Apple |
| 7d. Actualizaciones automáticas | Opus | Sonnet (`tf-implementer`) para UpdateKit, diálogo, Ajustes, instalación en Windows y script de release; Sonnet (`web-researcher`) para Sparkle y el instalador | Librería conocida (Sparkle) y fontanería; lo delicado es la firma y no romper datos, no un modelo mayor |
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
