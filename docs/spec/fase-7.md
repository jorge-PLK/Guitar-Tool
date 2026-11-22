# Montaje (mini-spec de la Fase 7)

Montar las mejores tomas de la Fase 6 en un único vídeo, landscape o portrait, con la solista solo en los solos, encuadre sobre la guitarra, transiciones y exportación con la mezcla a -14 LUFS (RF9). Rama `fase-7`, desde `fase-6`; la Fase 5 sigue en paralelo en `fase-5` (desde `fase-4`) y se junta al terminar. Se apoya en `TakePreview` y en las partes y tomas de la Fase 6, y en las secciones de solo de la Fase 4.

Decidido por Jorge el 16/11/2026:

- **Encuadre con conmutador por toma:** fijo (un recuadro para toda la toma) o «Seguir la guitarra» (el recorte la sigue, suavizado). Los dos con ajuste manual.
- **Solo se exporta lo grabado.** El vídeo va del principio de la primera toma al final de la última; una parte sin toma en un tramo no tiene recuadro ni audio en ese tramo.
- **Fundidos de un compás:** si el vídeo no empieza con el tema, entra con un compás de fundido (imagen y sonido); si no acaba con el tema, sale con otro.
- **Rótulo opcional** con título y artista durante los 5 primeros segundos.

Decidido o ajustado por Jorge el 17 y 18/11/2026 (ADR-018):

- Toma que acaba antes que el plan: fundido a negro, no se congela el último fotograma (ver «Transiciones»).
- Plano único: una guitarra solo se ve donde tiene una toma que cubre ese instante (ver «Layouts»).
- Botón «Rotar» por cámara y por toma, para vídeo grabado en vertical (ver «Encuadre»).
- Los valores visuales (margen 48, separación 24, esquinas 24, desenfoque 16 px, plano único sin esquinas ni sombra, encuadre con margen del 15 %, relleno difuminado de 40 px al 50 %) valen por ahora.

## Qué entra en el montaje

- De cada parte de `Project.recording`, su mejor toma. Con vídeo: recuadro y audio. Sin vídeo: solo audio. Parte sin tomas: no entra.
- **Presencia de una parte:** el tramo del tema que cubre su toma (desde `songStart`, margen incluido, hasta su final). Si la parte es solista, ese tramo cortado con las secciones de solo (`Section.isSolo`); sin secciones de solo en el proyecto no se espera solo (puede ser una versión solo de rítmicas): la solista no aparece ni suena, sin bloquear ni avisar más que con una nota en su carril (Jorge, 16/11/2026). Y al revés: con solos marcados pero sin toma de la solista, el montaje se hace igual (hacer o no el solo se decide al grabar); en el solo siguen las rítmicas y suena la guitarra original. Nada de esto bloquea la exportación.
- **Tramo del vídeo:** del inicio de presencia más temprano al final más tardío.
- **Huecos sin ninguna parte, a elegir con el conmutador «Cortar huecos sin tomas»** (Jorge, 16/11/2026; desactivado por defecto): desactivado, en el hueco se ve el fondo y suena el backing; activado, el hueco se quita y el vídeo es la concatenación de los tramos con alguna parte presente. En cada corte, el tramo que acaba sale con un compás de fundido y el siguiente entra con otro (la misma regla que al principio y al final; confirmado por Jorge el 16/11/2026). La línea de tiempo marca los huecos cortados. Con «Cortar huecos», cada tramo empieza 0,5 s antes de la presencia (la entrada del recuadro); sin cortar, no. Los tramos se cuantizan a la rejilla de fotogramas.
- **Compás** para los fundidos: del pulso de la Fase 2; sin pulso, 120 BPM y 4/4 (como en la Fase 6).

## Layouts

Lienzo de 1920 × 1080 (landscape) o 1080 × 1920 (portrait), escalado a la resolución de exportación. Recuadros con margen, esquinas redondeadas y sombra suave, y el nombre de la parte abajo a la izquierda (como en el boceto; opcional con «Nombre de cada parte»). «Mantener aspect ratio de vídeo» respeta la proporción de la toma en el apilado y en el plano único, en lugar de recortar al recuadro.

| Layout | Reparto de los recuadros visibles |
|---|---|
| Landscape · lado a lado | Una fila de columnas iguales |
| Landscape · rejilla | 1: completo; 2: apilados; 3: dos arriba y uno centrado abajo; 4: 2 × 2 |
| Portrait · apilado | Una columna de filas iguales |
| Portrait · plano único | Un solo recuadro a pantalla completa, sin esquinas ni sombra |
| Landscape · plano único | Lo mismo en 1920 × 1080 |

En los tres primeros, cuando una parte entra o sale, el layout se redistribuye con los recuadros que quedan. Orden de los recuadros: el de las partes, que se cambia arrastrando los carriles de la línea de tiempo (`MontageState.partOrder`).

**Plano único: cortes libres y cobertura.** Por defecto se ve la rítmica elegida (la primera con vídeo) y, en los solos, la solista. El carril «Plano» admite cortes libres (clic o «Añadir corte», elegir guitarra, arrastrar la marca, «Quitar cortes»). La regla vive en `MontageTimeline.singleAppearances`:

- Manda el corte, pero solo donde su parte tiene imagen (`Part.coverage()`).
- Si no, el automático, solo entre partes con imagen y presencia: solistas en sus solos, luego la rítmica elegida, luego la primera no solista.
- Si no hay ninguna, sigue la que se veía y funde a negro.
- En el selector «Plano» las partes sin toma en el instante del corte salen desactivadas (`MontagePlan.singleCutCandidates(at:)`, `MontagePlanning.cutEligibleParts`). Un corte a una parte sin toma se marca en ámbar con el aviso «X no tiene toma aquí: se ve el automático». El carril pinta lo que de verdad se ve (`MontageTimeline.singleShots()`).

## Transiciones

- Recolocación y cambio de tamaño: curva tipo muelle (ease-in-out), 0,5 s.
- Entrada: escala del 92 al 100 %, opacidad de 0 a 1 y desenfoque que se aclara, en esos 0,5 s. Salida: lo inverso.
- La entrada empieza siempre 0,5 s antes del inicio de presencia, para que el recuadro esté completo en la primera nota (Jorge, 16/11/2026; RF9 decía 0,3 s, que lo dejaba al 74 % de opacidad); si la toma no tiene imagen tan pronto, desde su primer fotograma. La salida empieza al final de la presencia. Los bordes de las secciones ya están en el pulso (Fase 4).
- En el plano único, el cambio rítmica ↔ solista (o entre guitarras de un corte) es un fundido cruzado con la misma escala y desenfoque.
- **Toma que acaba antes que el plan:** `MontageTimeline.imageBrightness` funde de 1 a 0 en 0,5 s (`MontageStyle.endFade`) sobre el último fotograma retenido y queda en negro hasta el final. Se oscurece el recuadro entero (imagen, relleno difuminado y rótulo; `MontageBoxState.brightness`). Solo se aplica si el recuadro sigue más de 50 ms tras la última imagen (`MontageStyle.endFadeTolerance`). En plano único manda la regla de cobertura. Vista previa y exportación comparten timeline y compositor.
- Audio de cada parte: entra y sale con fundido de 80 ms en los bordes de su presencia, y la entrada y salida del vídeo (un compás) con la misma curva en la vista previa y en la exportación (`MontageAudioEnvelope`); la imagen sigue lineal. La guitarra original que sustituye se silencia con el fundido inverso mientras la parte está presente.
- El audio del montaje ignora el silencio del canal «Tú · parte» de Grabar y usa solo su volumen.

## Encuadre

- Vision (pose corporal) sobre fotogramas muestreados de la toma ya compuesta (base y punches, en tiempo del tema): muñecas, codos y torso delimitan la caja de la guitarra, con margen.
- **Fijo:** la mediana de las cajas de la toma. **Seguir:** la trayectoria de la caja, suavizada (sin temblor ni saltos) y con huecos de detección interpolados.
- El recorte de cada recuadro es la caja ampliada a la proporción del recuadro en ese instante, sin salirse del fotograma. Sin detección: el fotograma entero, centrado.
- **Rotar** (0°, 90°, 180°, 270° en sentido horario): se guarda por cámara (`VideoSettings.rotations`, como el desfase) y por toma (`Take.videoRotation`, nil = 0°); una toma nueva hereda el de su cámara. Se aplica al leer, sin recodificar: el compositor gira y cambia ancho y alto, el reproductor usa `preferredTransform` y Vision recibe la orientación (`VideoRotation`, `MontagePartVideo.rotation`). `TakeFraming.rotatedClockwise` transforma el encuadre guardado en lugar de reiniciarlo. La huella del análisis incluye el giro solo si no es 0°. Los punches usan el giro de su toma. Botón en la vista previa de Grabar (desactivado mientras se graba), en Ajustes de vídeo y en la ficha de cada toma en Montaje, junto a «Encuadre».
- Ajuste manual por toma (hoja «Encuadre»): en fijo, mover y escalar la caja sobre el fotograma; en seguir, zoom y desplazamiento sobre la trayectoria. «Restablecer» vuelve al automático.
- El análisis se guarda en `cache/framing/<takeID>.json` (regenerable, con huella de la toma y sus punches); el modo y el ajuste manual, en el proyecto.

## Compositor y vista previa

- Compositor propio (`AVVideoCompositing`, Core Image sobre Metal) que dibuja cada fotograma a partir de un plan puro: para un tiempo `t`, la lista de recuadros con su rectángulo, escala, opacidad, desenfoque y recorte, más el fundido global y el rótulo.
- Las tomas entran en una `AVMutableComposition` con su `videoOffset` y sus punches (como `TakePreview`), sin recodificar.
- Vista previa en tiempo real con `AVPlayer` sobre la misma composición y el mismo compositor, con el audio del montaje sin normalizar (stems y tomas con sus volúmenes y fundidos). Puede bajar la resolución para ir fluida.

## Exportación

- Vídeo: HEVC o H.264, resolución y fps de «Exportación por defecto» de Ajustes (30 fps si no hay), modificables en la pantalla. Contenedor MOV o MP4 (`export.container`). Fichero `video/<tema>-<layout>.<mov|mp4>` (se sobrescribe el del mismo layout) y botón «Mostrar en Finder». El audio del vídeo va en AAC (128 kbit/s por canal).
- Mezcla: stems con la mezcla de Grabar (`recording.mix`), las guitarras sustituidas silenciadas durante la presencia de su parte, y las tomas con su volumen de canal «Tú · parte» y sus fundidos. Normalizada a -14 LUFS integrados (ITU-R BS.1770-4). El techo de pico real es -1,3 dBTP, con o sin limitador: 0,3 dB de holgura para el códec AAC. Con el conmutador «Limitador» (activado por defecto; Jorge, 16/11/2026), un limitador con anticipación sujeta los picos al techo y la mezcla llega a -14 LUFS; desactivado, si la ganancia llevara el pico real por encima del techo se frena la ganancia y se informa de los LUFS que quedan (en las pruebas, ~-16,3). Opción de no normalizar (el limitador solo actúa al normalizar). Con material muy brillante, el AAC puede subir el pico hasta +0,49 dB, más que la holgura; aceptado.
- WAV por pista (opcional), en `video/<tema>-<layout>-pistas/`: `backing.wav` (lo que suena del tema, sin tus tomas), uno por parte (`<parte>.wav`, con sus fundidos) y `mezcla.wav` (la normalizada). Todos con la duración del vídeo y alineados; 24 bits a la frecuencia del proyecto.
- Rótulo opcional: título y debajo artista, abajo a la izquierda, sobre placa oscura translúcida, 5 s con fundido de entrada y salida.
- Progreso con cancelar; cancelar borra los ficheros a medias.

## Interfaz

**Pantalla Montaje** (boceto `docs/design/Edit.dc.html`), ya en la barra lateral; «Ir al montaje» de Grabar se activa. Cabecera con tema, número de tomas y «Exportar vídeo». Tres columnas: Layout (los cinco, con miniatura), Vista previa (reproductor con play y posición; en portrait limitada a 440 pt para que la línea de tiempo quepa sin scroll) y Exportación, compacta y sin scroll (contenedor, formato, resolución, fps, -14 LUFS con «Limitador», rótulo, «Nombre de cada parte», «Mantener aspect ratio de vídeo», WAV por pista). La lista informativa «Transiciones» va en un popover tras el botón (i) junto a la cabecera. Debajo, la línea de tiempo: secciones y un carril por parte (cabecera de 270 pt) con su presencia (barra llena = en pantalla), el tramo del vídeo y los fundidos marcados; clic para mover la vista previa; los carriles se arrastran para reordenar los recuadros. En layouts de plano único, un carril «Plano» con los cortes. En cada carril, el nombre de la parte (sin partir ni truncar) y los botones «Encuadre» (hoja con fotograma, caja, conmutador «Seguir la guitarra», zoom, «Restablecer») y «Rotar». Sin tomas con vídeo: estado vacío con enlace a Grabar.

## Datos (Store, aditivo, sin subir `schemaVersion`)

- `Project.montage: MontageState?`: `layout` (`side`, `grid`, `stack`, `single`, `singleLandscape`), `singleRhythmPartID`, `singleCuts`, `caption`, `cutGaps`, `partOrder`, `showPartLabels`, `keepVideoAspect`, `export` (copia editable de `VideoExportDefaults` más `normalize`, `limiter`, `trackWAVs` y `container`), `framing: [takeID: TakeFraming]`.
- `TakeFraming`: `mode` (`fixed`, `follow`), `manualBox` (rectángulo normalizado, para fijo), `followZoom`, `followOffset`; `rotatedClockwise(quarterTurns:)`.
- `RecordingState.partMix`: fader «Tú · parte» de Grabar, restaurado al reabrir. `Take.videoRotation` y `VideoSettings.rotations`.
- `ProjectLayout`: `framingCacheURL(takeId:)`, `montageVideoURL(layout:)`, `montageTracksDirectory(layout:)`. `Library.saveMontage`.
- Copias de seguridad de `project.json`: `project.json.bak-AAAAMMDD` (7 días) y `project.json.lost-<fecha-hora>` cuando una escritura pierde una sección de primer nivel (`losesData` compara todas las claves, también `tabSource`) o el vídeo de una toma. Perder `videoRotation` dentro de una toma no crea `.lost`.
- Todo aditivo; `schemaVersion` sigue en 2 (decisión de Jorge).
- Tipos nuevos en fichero nuevo (`Montage.swift`); en `Models.swift`, `Files.swift` y `Library.swift` solo se añade (la Fase 5 también toca Store).

## Código

VideoKit sigue sin depender de AudioKit ni de Store: recibe un `MontagePlan` con tipos propios y la app hace de puente.

| Pieza | Paquete | Agente |
|---|---|---|
| `GuitarFramer` (Vision; caja fija y trayectoria), `MontagePlan` (entrada: lienzo, fps, layout, tramo, compás, partes con presencia, ficheros, desfases, punches y encuadre, pistas de audio con volumen y tramos, rótulo), `MontageLayout` (geometría), `MontageTimeline` (estado de los recuadros en `t`), `MontageCompositor`, `MontageBuilder` (composición + compositor + mezcla de audio de la vista previa → `AVPlayerItem`), `MontageExporter` (vídeo con `AVAssetReader`/`AVAssetWriter` y el WAV de la mezcla ya normalizada), `MontageAudioEnvelope` (fundidos de audio), `VideoRotation` (giro al leer), `tf-video frame` y `tf-video montage` (desarrollo) | VideoKit | `tf-engineer` |
| `LoudnessMeter` (BS.1770-4 integrado y pico real), `MontageMixer` (mezcla fuera de línea de stems y tomas con volúmenes, tramos con fundidos y fundido global; normalización; WAV por pista) | AudioKit | `tf-implementer` |
| `MontageState`, `TakeFraming`, rutas, `Library.saveMontage` | Store | `tf-implementer` |
| Pantalla Montaje, hoja «Encuadre», `MontageController` (puente Store → `MontagePlan` y `MontageMixer`, análisis de encuadre, exportación con progreso), datos simulados y `--screen montage` en DEBUG | App | `tf-implementer` |

La geometría de los layouts va con el compositor (mismo paquete y mismos tipos) aunque el plan la asigne a Sonnet. Reparto: primera tanda en paralelo, VideoKit (`tf-engineer`), AudioKit y Store (`tf-implementer`); segunda, la app; después `tf-qa` y capturas revisadas por el orquestador.

## Pruebas

- Puerta (sin hardware): tomas sintéticas (color liso distinto por parte, con `VideoTakeWriter`), una rítmica entera, otra parcial y una solista con dos solos. Se exporta en landscape y en portrait y se comprueba: dimensiones, fps y duración (tramo del vídeo); en instantes dados, el color esperado en el centro de cada recuadro (solista solo en los solos, completa en la primera nota; la parcial fuera al acabar su toma); fundidos de un compás al principio y al final; pista de audio presente.
- `MontageLayout` y `MontageTimeline`: rectángulos sin solapes dentro del lienzo, continuidad en las transiciones, 0,5 s de anticipación y recuadro completo en la primera nota.
- `GuitarFramer`: suavizado y huecos con poses sintéticas; caja dentro del fotograma y con la proporción pedida.
- `LoudnessMeter`: contra el `ebur128` del ffmpeg embebido, diferencia menor de 0,1 LU en tonos y ruido; `MontageMixer`: -14 ± 0,2 LUFS, tope de -1,3 dBTP, fundidos de 80 ms, pistas con la misma duración.
- Store: `montage` se guarda y se lee; un proyecto anterior se abre igual; copias `.bak` y `.lost` (`ProjectBackupTests`, `testWriteLosingTabSourceCreatesLostCopy`); rotación (`VideoRotationTests`).
- Cobertura y giro (VideoKit): `MontageSingleCoverageTests` (plano único), `MontageCompositionCoverageTests` (fundido a negro), `MontageOptionsTests`, `MontageFrameGridTests`, `MontageAudioFadeTests`, `VideoRotationTests`.
- Interfaz: capturas revisadas por el orquestador (Montaje en los cinco layouts, hoja Encuadre).

Límites conocidos: la app no tiene target de tests (sin cubrir `MontagePlanning.build`, la limpieza al cancelar, `BarTiming.sectionStop` ni los retoques de `RecordController` y `BackingController`); `limiterOutOfTolerance` sin test determinista; el solo del canal «Tú · parte» no se guarda; el ffmpeg embebido no trae `ebur128` y la medida de referencia usa el de Homebrew; el iPhone con Continuidad en vertical está sin probar; un fichero con transformación propia se gira según su tamaño natural.

## Lo que comprueba Jorge

1. Hoja «Encuadre» sobre tomas reales: la caja automática coge la guitarra, en fijo y siguiendo.
2. Vista previa: transiciones y entrada de la solista a la vista.
3. Exportar el mismo tema en landscape y en portrait y verlos; abrir los WAV por pista en un DAW.

## Estimación y condición de paso

De 6 a 10 horas, como en el plan.

Condición de paso: vídeo final exportado en portrait y en landscape, visto por Jorge; y el test de la puerta.

Cumplida el 18/11/2026 (ADR-018): Jorge probó a mano la app («todo correcto»), con el vídeo exportado en portrait y en landscape, y `MontageGateTests` es el test de la puerta.
