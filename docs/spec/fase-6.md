# Grabación con vídeo (mini-spec de la Fase 6)

Grabar tomas con cámara y la señal procesada sobre el backing, por partes y con varias tomas por parte, alineadas con el tema (RF8, parte de RF9). Va en paralelo con la Fase 5, en la rama `fase-6` (worktree aparte, desde `fase-4`). Se apoya en el audio de la Fase 3 (`AudioSession`, `TakeRecorder`, `TakeAligner`) y en las guitarras y secciones de la Fase 4.

Decidido por Jorge el 16/11/2026 (cambia RF8 y dos casillas del plan; va en un ADR nuevo al cerrar):

- **Sin calibración automática de la cámara.** Ni destello ni palmada: al terminar cada toma, un ajuste de desfase a mano con la vista previa. Ese valor queda como desfase por defecto de esa cámara para las tomas siguientes.
- **Sin micro.** Solo se graba la guitarra procesada (como en la Fase 3). Sin DI (ADR-012).
- **El backing son los stems con su mezcla**, configurable como en Backing (mezclador con volumen, silencio y solo por stem y por guitarra). No se graba: se reproduce desde los stems, que ya están alineados con el tema.
- **Punch-in sobre un tramo marcado**, que sustituye audio y vídeo del tramo.
- **Cada toma graba desde la sección elegida hasta que se pulsa parar** o acaba el tema.

## Cámara y sincronía

- Cámaras: todas las de vídeo del sistema (webcam USB, cámara integrada, iPhone por Continuity Camera), con sus formatos (resolución y fps). Por defecto, la de Ajustes; si no está conectada, se avisa y se puede grabar sin vídeo.
- Reloj común: la captura de vídeo entrega cada fotograma con su marca en el reloj de host; el audio de la Fase 3 sabe qué instante de host corresponde a cada muestra de salida y el ancla del reproductor, qué posición del tema corresponde a cada muestra. Con eso, cada fotograma se sitúa en tiempo del tema. El fichero de vídeo se escribe con esa marca (tiempo del tema), sin aplicar el desfase manual.
- Desfase manual (`videoOffset`, en segundos, positivo = la imagen llega tarde): se guarda en la toma y se aplica al reproducir y en el montaje, sin recodificar. Valor inicial de cada toma: el desfase por defecto de la cámara (0 si no hay).
- Fichero: `takes/<id>/video.mov`, HEVC, solo vídeo, con la resolución y los fps elegidos. Si la cámara no da el formato pedido, el más cercano, y la toma guarda el real.

## Partes y tomas

- **Parte:** nombre, qué guitarra sustituye (una de las pistas de la Fase 4 —rítmica, izq., der., solista— o ninguna, para una parte añadida), si es solista (marcado por defecto cuando sustituye a la solista; el montaje de la Fase 7 la enseña solo en los solos), sus tomas y su mejor toma.
- Propuesta inicial: una parte por pista de guitarra del proyecto, con su nombre del mezclador. «Añadir parte» pide nombre y qué guitarra sustituye.
- Al grabar una parte suena el backing con la mezcla de Grabar, con la guitarra de esa parte silenciada, más la mejor toma de cada una de las otras partes («tus tomas anteriores»), cada una como canal «Tú · nombre de la parte» del mezclador.
- Mejor toma: la última grabada hasta que se elige otra. Una toma se puede borrar (con confirmación; borra su carpeta).
- La mezcla de Grabar se guarda en el proyecto, aparte de la de Backing; la primera vez se copia de Backing.

## Grabar una toma

- Reglas de la Fase 3: dispositivo conectado, `guitarIn` asignado, velocidad 100 % y sin bucle; si no, el botón se desactiva con el motivo. Sin calibración de latencia se graba, se marca y se avisa.
- Inicio: selector «Empezar en» con las secciones (por defecto el principio; en una parte solista, el primer solo).
- Cuenta de 1 compás (activada por defecto) con clics del metrónomo y número grande sobre la vista previa; después arranca el backing en el inicio menos el margen (2 compases por defecto; 1 compás o sin margen) y se graba audio y vídeo. Compases del pulso de la Fase 2; sin pulso, a 120 BPM y 4/4.
- Fin: al pulsar parar o al acabar el tema. La toma se guarda entera (incluido el margen) y se alinea como en la Fase 3.
- Al parar se abre la hoja «Ajustar desfase»: vista previa del vídeo con la guitarra grabada, desfase en ms (±500 ms) con botones de ±1 fotograma y ±1 ms, «Guardar como desfase por defecto de esta cámara» (marcado) y los botones «Guardar toma» y «Descartar toma». El desfase se puede volver a ajustar después desde la toma.

## Punch-in

- Con «Punch-in» activado sobre una toma, se marcan entrada y salida en la línea de tiempo (imán al compás, ⌥ libre).
- Arranca en la entrada menos el margen, con cuenta si está activada; hasta la entrada suena la toma vieja y desde la entrada se silencia (te oyes por la monitorización del aparato). Se para solo 0,5 s después de la salida.
- Audio: la toma queda aplanada en `takes/<id>/processed.wav`, con fundidos cruzados de 10 ms en la entrada y la salida; la original se guarda en `takes/<id>/base/processed.wav` y cada punch en `takes/<id>/punch-<n>/`. Vídeo: no se recodifica; la toma guarda la lista de punches (tramo, ficheros y su desfase) y la vista previa y el montaje los componen.
- Varios punches en la misma toma: el último manda en su tramo.

## Interfaz

- **Pantalla Grabar** (boceto `docs/design/Record.dc.html`), en la barra lateral entre Backing y Montaje: vista previa de la cámara con «REC · Toma N · nombre de la parte», formato real y la cuenta; barra de grabación (Grabar/Parar, tiempo, «Empezar en», «Cuenta de 1 compás», «Margen», «Punch-in», y a la derecha el desfase por defecto de la cámara); mezclador como el de Backing en lugar del bloque «Pistas de audio», con el medidor de la entrada de guitarra; panel «Partes» con estado (Pendiente, Grabando, Hecha), botones de toma (la mejor en verde) y menú de toma (Marcar como mejor, Ajustar desfase, Punch-in, Borrar). Sin la línea del rig (Etapa 2) ni el recuadro de encuadre (Fase 7). «Ir al montaje», desactivado hasta la Fase 7.
- **Ajustes · Cámara y vídeo** (boceto `docs/design/Settings.dc.html`, pestaña existente): Cámara (por defecto, resolución, fps, con vista previa pequeña); Sincronía (desfase por defecto de la cámara elegida, editable, en lugar de «Calibrar retardo»); Exportación por defecto (formato HEVC o H.264 y resolución, -14 LUFS, rótulo sí/no, WAV de cada pista sí/no): solo se guarda, la usa la Fase 7.

## Datos (Store, aditivo, sin subir `schemaVersion`)

- `EquipmentProfile.video: VideoSettings?`: `cameraUID`, `resolution`, `fps`, `offsets` (desfase por defecto por cámara) y `export` (`VideoExportDefaults`).
- `Project.recording: RecordingState?`: `parts: [RecordingPart]`, `mix` (como `StemMix` de Backing), `startSectionID`, `countIn`, `preRollBars`.
- `RecordingPart`: `id`, `name`, `replaces: GuitarRole?`, `isLead`, `takeIDs`, `bestTakeID`.
- `Take` gana campos opcionales: `partID`, `videoFile`, `videoOffset`, `videoFormat` (cámara, ancho, alto, fps reales), `punches: [TakePunch]` y `baseProcessedFile`. `TakePunch`: `start`, `end` (tiempo del tema), `processedFile`, `videoFile`, `videoOffset`.
- `ProjectLayout`: `videoURL(takeId:)`, `baseProcessedURL(takeId:)`, `punchDirectory(takeId:n:)`.
- Esta fase va en paralelo con la Fase 5, que también toca Store: los tipos nuevos van en ficheros nuevos y los cambios en `Models.swift`, `Files.swift` y `Library.swift` se limitan a añadir campos y métodos.

## Código

| Pieza | Paquete | Agente |
|---|---|---|
| `CameraDevice`, `CameraProviding` (real y simulada), `CameraCapture` (real con AVCaptureSession y simulada con retardo, jitter y fotogramas perdidos), `VideoTakeWriter` (AVAssetWriter HEVC con marcas en tiempo del tema), `HostTimeMap` (host ↔ tema), `TakePreview` (composición de vídeo + toma procesada con desfase y punches), `tf-video` (desarrollo: `cameras`, `record`, `sync`) | VideoKit | `tf-engineer` |
| Instante de host de cada muestra y del ancla (lo que necesita `HostTimeMap`); varias pistas de toma en `StudyPlayer` (las mejores de las otras partes); silencio con fundido de la toma vieja en la entrada del punch; aplanado del punch con fundidos de 10 ms | AudioKit | `tf-engineer` (mismo agente que VideoKit: comparten tiempos y la caché de `swift build`) |
| `VideoSettings`, `RecordingState`, `RecordingPart`, campos de `Take`, `TakePunch`, rutas, `Library.saveRecording`, borrar toma | Store | `tf-implementer` |
| Ajustes · Cámara y vídeo | App | `tf-implementer` |
| Pantalla Grabar, hoja «Ajustar desfase», flujo de grabación y punch-in, cableado en `AppModel` y barra lateral | App | `tf-implementer` |

Reparto: primera tanda en paralelo, VideoKit + AudioKit (`tf-engineer`) y Store (`tf-implementer`). Segunda, en serie para no pisarse el build de la app: Ajustes · Cámara y vídeo y luego la pantalla Grabar (`tf-implementer`). Después `tf-qa` y capturas revisadas por el orquestador.

## Pruebas

- Sin hardware (puerta de tests): cámara simulada con retardo conocido y jitter de ±2 ms, audio simulado de la Fase 3. Se graban 3 tomas de 60 s (una empezando a mitad de tema, otra con deriva de audio de 50 ppm); con el mismo desfase para las 3, cada fotograma cae en su tiempo del tema con error menor de medio fotograma, al principio y al final. Fotogramas perdidos no desplazan los siguientes.
- `HostTimeMap`: conversiones ida y vuelta exactas a 44,1 y 48 kHz y con cambio de ancla (seek).
- Punch: el aplanado conserva fuera del tramo la toma original muestra a muestra y deja fundidos de 10 ms; la composición de vídeo usa el punch dentro del tramo y la base fuera.
- Store: los campos nuevos se guardan y se leen; un proyecto o un perfil anteriores se abren igual; borrar una toma la quita de su parte y reasigna la mejor.
- Interfaz: capturas revisadas por el orquestador (Grabar con cámara simulada, hoja de desfase, Ajustes · Cámara y vídeo).

## Medidas con hardware (las hace Jorge)

1. `tf-video cameras`: cámaras y formatos que ve la app (webcam e iPhone).
2. En la app, con la Flex Prime y el iPhone: 3 tomas de una parte. En cada una, golpe seco en las cuerdas al principio y al final; ajustar el desfase en la primera y comprobar que en las otras dos, con el mismo desfase, golpe e imagen coinciden fotograma a fotograma.
3. Una parte con punch-in: el tramo sustituido cuadra en audio y vídeo.

## Lo aprendido al cerrar la fase (16/11/2026, ADR-015)

- Con el iPhone (1080p30) y la Flex Prime, `tf-video sync` midió 1754 fotogramas sin pérdidas, jitter RMS 0,93 ms (máx. 15,06 ms), audio +29 ppm frente al host y cámara − audio −83 ppm (cadencia del iPhone, no afecta). El retardo de entrega va de 43 a 254 ms (mediana 57).
- Por ese retardo la cámara arranca al abrir Grabar (unos 1,5 s hasta el primer fotograma) y al parar se espera unos 0,5 s a los últimos fotogramas.
- La cuenta suena en un segundo `StudyPlayer`, para no tocar el que reproduce el backing.
- Las cámaras se re-sondean cada 2 s en Grabar: el proveedor admite un solo manejador de cambios.
- Mezclador compacto por defecto y vídeo lo más grande, sin scroll en ventanas 16:9.
- Pendientes: suavizar las marcas de la cámara (solo si hace falta), desfase propio por punch desde la hoja y ganancia igualada en los canales «Tú · parte».

## Retoques al cerrar la Fase 7 (18/11/2026, ADR-018)

- **Parada automática:** la grabación se para sola al acabar la sección elegida más el margen (`BarTiming.sectionStop`).
- **Tomas a otra frecuencia:** si una toma no está a la frecuencia del proyecto, se remuestrea al cargar (`TakeResampling`); `Library.migrate` no las reconvierte y la caché remuestreada va al temporal, sin limpiarse.
- **Botón «Rotar»** en la vista previa de Grabar (desactivado mientras se graba): 0°, 90°, 180° y 270° por cámara, heredado por cada toma nueva; ver «Encuadre» en la mini-spec de la Fase 7. También en Ajustes de vídeo, sobre la vista previa en directo.
- `Tools/test.sh App` compila solo la app (unos 5 s en incremental) y no escribe `Temp/last-run.txt`.

## Estimación y condición de paso

De 4 a 6 horas, como en el plan: quitar la calibración y el micro resta lo que añaden el punch-in con vídeo y el mezclador en Grabar.

Condición de paso: 3 tomas grabadas y alineadas a menos de 1 fotograma con un mismo desfase, comprobado por Jorge en la app; y el test de la puerta con la cámara simulada.
