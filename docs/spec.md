
# ToneForge – Spec de app de escritorio para igualar tonos

Fuente de verdad de la spec desde el 15/11/2026 (ADR-002); antes, copia del doc de spec de Claude Docs.

·


## Resumen y objetivo

ToneForge es una app de escritorio (solo macOS, uso personal, todo en local y sin APIs de pago) que, a partir de un tema y del equipo del usuario, genera el rig que más se acerca al tono original y lo carga directamente en la HeadRush Flex Prime.

La diferencia con TonesMatch, ToneAdapt o GuitarAI es que no devuelve texto sacado de una base de datos: escucha. Reamplifica un DI real del usuario a través de la pedalera y ajusta los parámetros en bucle cerrado hasta minimizar la diferencia con la guitarra aislada del tema.

Alrededor de ese núcleo, la app sirve también para estudiar y grabar el tema: backing track sin las guitarras que elijas, acordes y tempo, tablatura, grabación multitoma con vídeo y montaje final en un único vídeo.

Criterio de éxito v1: en 10 temas de referencia (Extremoduro, Platero y Tú, Los Suaves, Marea, Lèpoka), cada rig generado en menos de 10 minutos una vez separado el tema y grabado el DI, y valorado como "reconocible" en escucha ciega A/B.


## Alcance v1

La v1 se centra en un único dispositivo (Flex Prime) para que el bucle de optimización sea real y el resultado se pueda cargar sin pasos manuales.

| Dentro de v1 | Fuera de v1 |
|---|---|
| HeadRush Flex Prime: audio USB, edición de rigs, carga de NAM e IR | Amplis analógicos sin captura NAM |
| macOS (CoreAudio) | Windows (posible app nativa aparte más adelante) y Linux |
| Temas desde archivo local (WAV, FLAC, MP3) | Streaming desde Spotify o YouTube |
| Tono rítmico y solista del mismo tema | Igualar el tono de bajo u otros instrumentos; transcribir voces o teclados |
| Separación de hasta 2 guitarras eléctricas simultáneas, más el solo como sección aparte | 3 o más guitarras simultáneas |
| NAM e IR desde TONE3000 | Spark GO/NEO y Gigboard (v2) |
| Tablatura de guitarras, bajo y batería, generada, editable y exportable a Guitar Pro | Transcripción perfecta de solos complejos |
| Estudio del tema: backing track, acordes, tempo, bucles y cambio de velocidad | Letras, partituras o lecciones |
| Grabación multitoma con una cámara y montaje con layouts portrait y landscape | Varias cámaras a la vez y edición de vídeo libre (cortes a mano, efectos) |
| Uso personal, compilada desde Xcode | Distribución a terceros, App Store y notarización |


## Requisitos funcionales

Los once requisitos son viables; RF3 (editar la Flex Prime) es el de más riesgo porque no hay API pública.

| ID | Requisito | Comportamiento | Dependencia o duda |
|---|---|---|---|
| RF1 | Conexión directa de la pedalera | Selector de dispositivo de audio y de canales: entrada DI (seco), salida de reamp hacia la pedalera y retorno procesado. Calibración automática de latencia y nivel con un pulso de prueba. | La Flex Prime actúa como interfaz USB (P2, firmware 5.2.0, sin driver): 4 entradas y 4 salidas. Entrada al Mac: ch1/ch2 procesado, ch3 DI seco, ch4 copia del DI. Salida del Mac: ch1/ch2 directo a salidas y auriculares sin pasar por el rig (el backing), ch3 entrada del rig en USB Mode Reamp. El retorno no incluye el backing. La latencia declarada por el dispositivo (1200 muestras) no es fiable: la medida fue de 2416 muestras (50,3 ms) y varía ~1,2 ms según el rig, así que se calibra con pulso. Admite 44,1, 48 y 96 kHz; 44,1 kHz es posible y es la nativa de los modelos. |
| RF2 | Tablatura con play para grabar el DI | Genera la tab de la sección objetivo (riff o solo) a partir de la guitarra aislada, editable. Reproduce con cursor, metrónomo y tempo variable. Graba la toma y la valida: afinación, timing y clipping. | Transcripción con basic-pitch y render con alphaTab. Reutilizable la herramienta audio → Guitar Pro del proyecto estilo Rocksmith. |
| RF3 | Editar presets de la Flex Prime desde la app | Lee y escribe rigs: bloques, parámetros, escenas, carga de NAM e IR. | El Remote Editor se sirve desde la propia pedalera por Wi-Fi: hay que hacer ingeniería inversa de su API HTTP o WebSocket. El MIDI solo admite Program Change, CC y Clock. Plan B: copiar rigs por USB Transfer. |
| RF4 | Conexión a TONE3000 | Inicio de sesión, búsqueda y descarga de NAM (A2) e IR, filtrados por marca y modelo del ampli original. Envío directo a la pedalera. | La API nació dando acceso a tonos creados o favoritos del usuario. Verificar que la búsqueda en todo el catálogo ya está abierta. |
| RF5 | Tonos rítmico y solista | Detecta o deja marcar las secciones en la forma de onda. Genera dos escenas en el mismo rig: solista con más ganancia y medios, +2 a 3 dB y delay corto. | El solo suele llevar otra toma u otro equipo: cada sección se iguala por separado. |
| RF6 | Guitarras por separado (p. ej. Robe y Uoho) | Separa las guitarras del tema, propone dos pistas y el usuario las nombra y elige cuál igualar. | Todo en local, sin APIs de pago: aislar guitarras con un modelo local y separar A/B por panorama estéreo. Solista frente a rítmica, por heurística con Basic Pitch (acordes = rítmica, notas sueltas = solista) y marcado manual. Calidad parcial cuando ambas tocan lo mismo doblado. |
| RF7 | Modo backing track | Mezclador con mute, solo y volumen por stem (voz, batería, bajo, resto y cada guitarra separada). Quitar todas las guitarras o solo las elegidas, p. ej. quitar a Uoho y dejar a Robe. Bucle de secciones, tempo variable sin cambiar el tono y metrónomo opcional. Tu guitarra suena por la Flex Prime a la vez (monitorización directa, sin latencia añadida) y se puede grabar la toma: seca (DI) y procesada.Para analizar mejor: A/B de tu tono contra la guitarra original dentro de la mezcla y no en aislado, medida de la diferencia en vivo y la toma grabada se puede usar como DI para el reamp (RF2). | Reutiliza los stems ya separados en RF6: no añade modelos. Cambio de tempo con AVAudioUnitTimePitch. Si se quita una sola guitarra de dos, puede quedar algo de ella en la otra pista. |
| RF8 | Modo grabación (vídeo + audio multipista) | Graba a la vez la webcam y el audio sobre el backing track. El audio se guarda en pistas separadas y alineadas: backing (estéreo), guitarra DI (seco), guitarra procesada de la Flex Prime (estéreo) y micro opcional. Exporta el vídeo con la mezcla y los WAV de cada pista para remezclar después.Sincronía: el audio manda; el vídeo se alinea por marcas de tiempo y una calibración inicial (palmada o destello en pantalla) corrige el retardo de la cámara. | AVCaptureSession para la cámara y AVAudioEngine para el audio, con el mismo reloj de host. Webcam a 1080p y 30 o 60 fps según lo que dé la cámara. |
| RF9 | Modo multitoma y montaje en un único vídeo | Eliges qué partes vas a grabar a partir de las guitarras separadas (p. ej. rítmica de Robe, rítmica de Uoho y solo). En cada toma suena el backing sin esa parte y con tus tomas anteriores. Puedes repetir partes y elegir la mejor toma de cada una.Al final monta todo en un vídeo con layouts landscape (1920 × 1080: lado a lado o rejilla) y portrait (1080 × 1920: apilado vertical).Solista: su vídeo y su audio solo aparecen en las secciones de solo (RF5); el resto del tiempo su recuadro desaparece y el layout se redistribuye.Portrait con una rítmica y una solista: un solo plano a pantalla completa, la rítmica durante el tema y la solista en los solos, con encuadre recortado sobre la guitarra para que se vea lo más grande posible. | Montaje con AVMutableComposition + AVVideoComposition y exportación HEVC o H.264 con AVAssetWriter. Encuadre automático con Vision (pose corporal: muñecas, codos y torso delimitan la guitarra), con ajuste manual del recorte por toma. Transiciones suaves y modernas: los recuadros se recolocan y cambian de tamaño con animación tipo muelle (ease-in-out, unos 0,5 s); el que entra aparece con escala del 92 al 100 %, opacidad y un desenfoque que se aclara; el que sale hace lo inverso. Esquinas redondeadas y sombra suave en los recuadros. Las transiciones van alineadas al pulso del tema y empiezan unos 0,3 s antes del solo, para que la solista esté a pantalla completa en la primera nota. El audio de la solista entra y sale con fundidos de 50 a 100 ms, sin cortes. Compositor de vídeo propio (AVVideoCompositing con Metal o Core Image) que interpola cada fotograma; vista previa en tiempo real antes de exportar. |
| RF10 | Herramientas de estudio tipo Riffstation | Detecta acordes sincronizados con el tema y muestra su diagrama, con el actual y el siguiente. Detecta tempo, pulso y tonalidad. Velocidad del 50 al 200 % sin cambiar la afinación, transponer, afinación fina en cents y capo virtual. Bucles ajustados al pulso y metrónomo sincronizado. Los acordes se pueden corregir a mano. | Acordes con BTC (transformer, código MIT, vocabulario grande de 170 acordes) en Core ML, aplicado sobre los stems sin voz ni batería para acertar más. Pulso con Beat This!; el tempo es la media de los intervalos entre pulsos. Cambio de tempo y tono con AVAudioUnitTimePitch. Se integra en la pantalla de backing track. |
| RF11 | Transcripción de bajo y batería | Además de las guitarras, transcribe el bajo (tablatura de 4 cuerdas) y la batería (partitura de percusión) a partir de sus stems. Todo se puede corregir a mano y se exporta en un único archivo de Guitar Pro (.gp, versiones 7 y 8) con una pista por instrumento. Forma parte de la herramienta de estudio. | Bajo: Basic Pitch sobre su stem, fiable porque suele tocar una nota a la vez. Batería: ADTOF en Core ML; bombo, caja y charles salen bien en los 3 temas de prueba, fallan algunos platos y no hay toms en el render de escucha (válido para un Guitar Pro de estudio). Exportación con el exportador de Guitar Pro 7 de alphaTab. |


## Grabación: detalles acordados

El rig no cambia solo: en cada toma lo eliges tú, en la pedalera o desde la app.

- Escucha: el backing va por USB a la Flex Prime y se oye todo en sus auriculares junto con la guitarra (routing a confirmar en la Fase 0).
- Rig por toma: la app indica qué rig igualado corresponde a cada parte, pero no lo carga automáticamente.
- Antes de grabar: cuenta atrás de 1 compás y margen previo configurable (2 compases por defecto). Punch-in opcional para regrabar un trozo de una toma.
- Cámara: webcam USB o iPhone mediante Continuity Camera.
- Exportación: volumen normalizado a -14 LUFS y rótulo opcional con el título del tema.
- Disco: de 2 a 5 GB por tema. Una carpeta por proyecto: `project.json`, `source/original.<ext>`, `audio/song.wav` (regenerable), `stems/<stem>.wav` (regenerable, con `stems/.partial` mientras se separa), `takes/`, `video/`, `rigs/` y `cache/` (regenerable; `cache/analysis.json` guarda el análisis automático con su huella, y los stems vacíos se borran y se marcan con `Stem.isEmpty`, ADR-009). Opción de limpiar tomas descartadas y stems que se pueden regenerar. Un tema se puede eliminar (a la Papelera, o de forma definitiva con salvaguarda de ruta) y su título y artista se editan en el detalle. Al arrancar se re-encolan las separaciones interrumpidas y se limpian los temporales huérfanos; al salir se cancela todo y se matan los procesos hijos (tope de 3 s) (ADR-011).


## Ajustes

La app tiene una sección de Ajustes en la barra lateral, con icono de engranaje, donde se configura una vez lo que usan todas las pantallas. Lo que se elige aquí se guarda en el perfil de equipo.

| Apartado | Qué se gestiona |
|---|---|
| Audio | Salida del backing (hoy sin selector: la Flex Prime si está conectada, por sus canales 1/2, y si no la salida por defecto; el selector llega en la Fase 3), volumen master global (en el perfil de equipo, igual en todos los temas), dispositivo, canales (DI seco, salida de reamp, retorno procesado y salida del backing), frecuencia de muestreo (de trabajo, global, 44,1 o 48 kHz; cada proyecto guarda la suya y se reconvierte solo al abrirlo, en segundo plano y sin avisar; los stems se remuestrean, no se vuelven a separar), calibración de latencia y calibración del nivel del DI |
| Cámara y vídeo | Cámara por defecto (webcam o iPhone), resolución y fotogramas por segundo, calibración del retardo de la cámara y valores de exportación por defecto |
| Pedalera y TONE3000 | Dirección del Remote Editor por Wi-Fi, firmware detectado, estado de la conexión, y cuenta y clave de TONE3000 |
| Biblioteca y equipo | Carpeta de proyectos (se pregunta en el primer arranque, con `~/Music/ToneForge` como propuesta; «Cambiar carpeta» pregunta cada vez: Mover, Solo apuntar o Cancelar, y Mover borra el original solo al final), modelos descargados y espacio en disco, limpieza, y perfil de equipo con tus guitarras y pastillas. Bloque «Fuentes externas»: versión de yt-dlp en uso (embebida o actualizada), de Deno y de ffmpeg, con «Actualizar yt-dlp» y «Volver a la embebida» (ADR-011) |

Las pantallas de trabajo (tablatura, backing track, grabar) siguen mostrando el dispositivo y el canal en uso, pero se cambian desde Ajustes.


## Arquitectura técnica

Decisión: app nativa de macOS en Swift y SwiftUI, sin Python en la app final. Audio, cámara (incluido el iPhone con Continuity Camera), vídeo e interfaz usan las herramientas de Apple. Los modelos se usan en Core ML y los cálculos de audio con Accelerate. La Fase 0 comprobó que cada modelo funciona bien en Core ML; ONNX Runtime no hizo falta. La app exige macOS 15 como mínimo (UI, y la GRU nativa de ADTOF). La única precaución de cara a una posible app nativa de Windows es que los datos de cada proyecto se guardan en un archivo dentro de su carpeta, con SwiftData solo como índice de la biblioteca.

| Módulo | Responsabilidad | Tecnología |
|---|---|---|
| UI | Proyectos, forma de onda, espectros, A/B, vista visual de la cadena de señal con knobs | SwiftUI (macOS 15+), Swift Charts, Canvas; tablatura con alphaTab dentro de un WKWebView |
| Datos | Perfil de equipo, proyectos, rigs generados, caché de NAM e IR | Archivo de proyecto (JSON) en la carpeta de cada tema; SwiftData como índice de la biblioteca |
| Motor de audio | Elegir dispositivo y canales, reproducir el DI hacia la pedalera, grabar el retorno, calibrar latencia con un pulso | AVAudioEngine sobre CoreAudio |
| Separación | Aislar guitarras del tema | BS-RoFormer SW (6 stems, pesos de uso personal) con el Core ML publicado de gridshift, unidades CPU+GPU; Neural Engine prohibido (colgó el Mac). Respaldo: BSRoformer.cpp con GGUF q8 en Metal (de momento solo el protocolo `StemSeparating`, sin integrar C++). HTDemucs descartado (pierde en SDR y en escucha ciega). Se ejecuta en un proceso aparte (`tf-separate`, embebido en la app), uno por tema, vigilado por `MemoryGuard` con límite de 10 GB: 0,32× la duración del tema y unos 3,3 GB de pico. ADR-004, ADR-007 |
| Transcripción | Audio → notas → tablatura de guitarras y bajo, y partitura de batería | Basic Pitch, con su modelo Core ML oficial, para guitarras y bajo; batería con ADTOF (puerto `xavriley/ADTOF-pytorch`; CC BY-NC-SA, uso personal, no redistribuir) en Core ML FP32 con GRU nativa, solo CPU, macOS 15. Sustituye a Omnizart. ADR-006 |
| Acordes y pulso | Acordes sincronizados, tempo, compases y tonalidad | BTC (vocabulario grande, 170) en Core ML FP16 en Neural Engine (pesos no comerciales: válido en uso personal); preproceso CQT compatible con librosa portado a Swift con filtro FIR Kaiser en lugar de soxr (error medio 5,2e-6 frente a librosa). Pulso con Beat This! `final0` (MIT), `mlmodelc` comunitario `jessengatai/supracut-beat-this` en CPU+GPU; log-mel con módulo / 32 (sqrt(n_fft)); tempo = media de los intervalos entre pulsos, no la mediana (a 50 fps va a saltos de 20 ms). Tonalidad por perfiles de Temperley sobre el croma del CQT y el histograma de acordes (validada a ciegas por Jorge en un tema real). El análisis corre en el proceso de la app (~0,3–0,7 GB, 2–3 s por tema). ADR-006, ADR-009 |
| Reproductor de estudio | Mezcla de stems, velocidad, transposición, bucles al pulso y metrónomo | AVAudioEngine + AVAudioUnitTimePitch con overlap 8, con un `AVAudioUnitVarispeed` delante que compensa el redondeo de velocidad del TimePitch; play, seek y cambios de velocidad o transposición reinician el TimePitch. Rubber Band no hace falta: a 50 % no se oyeron diferencias (ADR-005, ADR-009) |
| Análisis | FFT, tercios de octava, armónicos, envolvente y dinámica | Accelerate (vDSP) |
| Optimizador | Ajustar parámetros minimizando la distancia | CMA-ES propio en Swift sobre Accelerate |
| Conector HeadRush | Leer y escribir rigs, subir NAM e IR | URLSession y URLSessionWebSocketTask contra el Remote Editor |
| Conector TONE3000 | Login, búsqueda y descarga | URLSession + ASWebAuthenticationSession |
| Modelos | Descarga la primera vez, verifica SHA-256, compila a `.mlmodelc` y guarda en `Application Support/ToneForge/Models/<id>/` | Paquete ModelKit (`ModelStore`); BS-RoFormer SW, 351 MB compilado. Beat This! se descarga ya compilado (`.mlmodelc` zipeado) y BTC va embebido en la app (zip de `.mlpackage`, 5,4 MB, se compila la primera vez). ADR-007, ADR-009 |
| Fuentes externas | Importar un tema desde un enlace de YouTube o de Spotify, o desde una lista o un álbum | Paquete SourceKit (sin dependencia de Store): metadatos de Spotify por la página embed, búsqueda y descarga con yt-dlp (Opus, con caída a M4A) y conversión a WAV de 24 bit con ffmpeg. Helpers embebidos en `Contents/MacOS/`: yt-dlp, Deno y un ffmpeg mínimo compilado aparte (LGPL), con yt-dlp actualizable desde Ajustes. ADR-008, ADR-011 |
| Captura de vídeo | Webcam sincronizada con el audio multipista | AVCaptureSession + AVAssetWriter |
| Montaje de vídeo | Layouts, cambios por sección, encuadre de la guitarra, exportación | AVMutableComposition, AVVideoComposition con Core Image, Vision (pose corporal) |

Python queda solo como herramienta de desarrollo: prototipar la función de distancia y convertir modelos. A cambio se gana un único binario, sin runtime de Python embebido, con uso de GPU y Neural Engine en Apple Silicon. Al ser de uso personal se compila y firma en local con el Apple ID gratuito (equipo personal), sin App Sandbox ni hardened runtime, solo arm64: no hace falta cuenta de pago de Apple Developer ni notarización. Para llevarla a otros Macs se copia por USB o SSD, para evitar la cuarentena. La app pedirá permiso de cámara, micrófono y red local (para hablar con la pedalera). Si la biblioteca está en un SSD externo, macOS pide una vez el permiso de «volumen extraíble». AVFoundation no lee los Vorbis comments de FLAC: el título sale del nombre del fichero («Artista - Título.ext»). ADR-007.

Los modelos de separación pesan entre 0,7 y 1,1 GB: se descarga la primera vez que se usa, no va dentro de la app. El DI se graba con la misma guitarra con la que se va a tocar, así que las pastillas (activas o pasivas) ya quedan incluidas en la medida.


## Pipeline de igualado de tono

Todo el igualado se hace reamplificando tu DI por la pedalera real, sin simulación en el Mac y sin LLM: primero se eligen las plantillas de partida y después se afinan los parámetros.

1. Importar el tema y detectar tempo, tonalidad y afinación.
2. Separar las guitarras, asignar la pista objetivo (p. ej. "Uoho") y marcar las secciones rítmica y solista.
3. Extraer la huella de cada sección: espectro medio en tercios de octava, perfil de armónicos (nivel de saturación), compresión y dinámica, anchura estéreo y reverb o delay estimados.
4. Propuesta inicial del rig, sin LLM y sin necesidad de saber qué equipo usó el original: la app tiene unas 8 plantillas de rig de la Flex Prime (limpio, crunch británico, alta ganancia, cada una con y sin overdrive delante, más variantes con NAM de TONE3000). Descarta las que no encajan con el nivel de saturación de la huella, prueba el resto con tu DI y se queda con las 3 más cercanas como punto de partida.
5. Grabar el DI guiado por la tablatura (RF2), o usar uno de referencia si el usuario prefiere no tocar.
6. Selección de partida: reamplificar el DI por cada plantilla candidata en la pedalera y quedarse con las 3 mejores (menos de 1 minuto).
7. Refinado: escribir los parámetros en la pedalera, reamplificar, capturar y medir. El optimizador repite unas 30 a 60 iteraciones; con un DI de 4 s son unos 3 a 6 minutos.
8. Resultado: A/B con el original a volumen igualado, retoque manual de knobs en la vista visual y guardado del rig con sus escenas.

Distancia a minimizar = diferencia espectral ponderada (más peso en 200 Hz a 5 kHz) + diferencia de armónicos + diferencia de dinámica. Se tolera una inclinación global de EQ, porque la mezcla y el máster del disco cambian el balance de graves y agudos sin que sea "el tono" del guitarrista.

La comparación no es solo de frecuencias. Como el DI toca el mismo riff que el original, las dos señales se alinean en el tiempo y se comparan nota a nota: ataque de la púa, pegada y resonancia grave de los palm mutes, cómo cambian los armónicos al tocar fuerte o flojo, cuánto comprime y cuánto dura el sustain. Ahí es donde se distinguen dos amplis saturados con una EQ parecida.


## Amplis, drives y efectos

El optimizador solo mueve knobs; elegir entre un ampli u otro, o entre overdrive y distorsión, es una decisión entre opciones que se prueban una a una en la pedalera y se ordenan por la medida. Los efectos de tiempo y de movimiento se tratan aparte, después de igualar el tono en seco.

| Elemento | Cómo se gestiona | Nivel de automatización |
|---|---|---|
| Modelo de ampli (p. ej. tipo Rectifier frente a tipo 5150) | Cada familia tiene sus candidatos: bloques de la Flex Prime y capturas NAM del ampli real en TONE3000. Se prueban con el DI y se comparan nota a nota. Los 3 mejores quedan para que elijas de oído en A/B | Medido; decisión final tuya |
| Pantalla e IR | Candidatos de IR y mezcla de dos IR, con corte de graves y agudos | Medido y optimizado |
| Overdrive, distorsión o fuzz delante | Variantes de cada plantilla: sin pedal, con overdrive tipo TS, con distorsión. Se elige la que más se acerca. Varias combinaciones de pedal y ganancia de ampli pueden sonar casi igual: vale cualquiera | Medido y optimizado |
| Compresión | Se compara la dinámica del original con la de tu rig. Solo se añade un compresor si falta compresión, lo normal en limpios; en saturados ya comprime el ampli | Estimado y ajustado |
| Puerta de ruido | Según el ruido de tu rig en los silencios | Ajustado |
| Delay | Se detectan los ecos en la guitarra original: tiempo, número de repeticiones y nivel, y se ajusta al tempo del tema | Estimado; lo retocas tú |
| Reverb | Se estima por la cola al final de las notas y en los silencios. Parte suele venir de la mezcla del disco y la separación la emborrona, así que se pone corta y discreta por defecto | Estimado; lo retocas tú |
| Chorus, flanger, phaser, trémolo | Se detecta el movimiento periódico del espectro y su velocidad; se añade el bloque con esa velocidad y valores típicos | Detectado y sugerido |
| Wah | Se detecta el pico que barre entre 400 Hz y 2 kHz y en qué secciones aparece. Se añade el bloque de wah asignado al pedal de expresión: el movimiento lo haces tú | Detectado y sugerido |
| Octavador, armonizador, whammy | Fuera de v1: la app avisa si los detecta | Aviso |

Orden del proceso: primero se igualan ampli, pantalla y drive con los efectos apagados, midiendo sobre todo en ataques y notas sostenidas, donde reverb y delay influyen menos. Después se añaden compresión, delay y reverb, y por último los efectos sugeridos.

Límite a tener presente: las diferencias finas entre dos amplis de alta ganancia son justo lo que más se pierde con la mezcla del disco y la separación de pistas. Por eso la app propone y mide, pero la elección entre los finalistas es de oído.


## Riesgos

Antes de escribir código de producto hay tres investigaciones que deciden la arquitectura: la API del Remote Editor, el routing USB de la Flex Prime y el alcance de la API de TONE3000.

| Riesgo | Impacto | Mitigación o primera investigación |
|---|---|---|
| API del Remote Editor sin documentar, puede cambiar con cada firmware | Crítico: sin ella no hay RF3 ni igualado automático | Capturar el tráfico navegador ↔ pedalera (DevTools, mitmproxy) y fijar versión de firmware soportada. Plan B: rigs por USB Transfer y ajuste manual guiado |
| El USB no permite reamp ni DI seco | Alto para RF1 | Revisar la sección USB Audio del manual 5.2 y probar. Plan B: interfaz externa + caja de reamp |
| Dos guitarras con el mismo papel (rítmicas dobladas) | Medio: separación incompleta | Usar el panorama estéreo, permitir marcar a mano y avisar de la confianza del resultado |
| La mezcla y el máster enmascaran el tono | Medio | Tolerancia de inclinación de EQ y más peso en medios |
| La búsqueda en TONE3000 aún limitada | Bajo | Empezar con favoritos del usuario y ampliar cuando la API lo permita |
| Derechos del audio | Bajo en uso personal | Procesar todo en local y no redistribuir stems ni temas |
| El retorno USB de la pedalera mezcla el backing con la guitarra | Alto para RF8: no habría pista de guitarra limpia | Resuelto en P2: el retorno USB no incluye el backing. Sin plan B |
| BS-RoFormer no se deja convertir a Core ML o va lento | Medio: peor separación de guitarra | Resuelto en P4: el Core ML publicado de gridshift separa a 0,37× tiempo real en CPU+GPU. Respaldo: BSRoformer.cpp q8 en Metal (0,51×) |
| Restos de otros instrumentos en la pista de guitarra | Medio: la huella del tono sale contaminada | Medir la huella en los pasajes donde la guitarra suena más sola y dar menos peso a las bandas de bajo y platos |
| Calidad del audio al ralentizar al 50 % | Bajo | Resuelto en P6: `AVAudioUnitTimePitch` con overlap 8; Rubber Band no hace falta |
| Detección de acordes imperfecta (en torno al 75 % en triadas según un estudio) | Bajo | Detectar sobre los stems sin voz ni batería y permitir corregir a mano |
| Transcripción de batería con ADTOF: fallan algunos platos, y fallo conocido de alphaTab: las baterías exportadas no suenan en Guitar Pro 8 con el motor RSE | Bajo | Dar por bueno bombo, caja y charles y corregir el resto a mano. Comprobar la exportación en Guitar Pro en la Fase 5 |
| yt-dlp se rompe cuando YouTube cambia (extractor, firma, límite de peticiones) | Medio: no se pueden importar temas desde enlace | «Actualizar yt-dlp» desde Ajustes y «Actualizar y reintentar» ante error de extractor (ADR-011). Plan B: importar el fichero a mano |


## Decisiones y pendientes

Decidido el 14/11/2026: app nativa en SwiftUI solo para Mac, preparada para una posible app nativa de Windows (única precaución: datos de proyecto en archivos, con SwiftData como índice); modelos en Core ML, con ONNX solo como respaldo si la prueba inicial falla; uso personal, todo en local y sin APIs de pago; el rig no cambia solo al grabar. Las pantallas ya están dibujadas en el lienzo «ToneForge – Bocetos de pantallas».

Pendiente:

- [ ] Catálogo de bloques y parámetros de la Flex Prime, a partir de la investigación del Remote Editor
- [ ] Calibración del nivel de entrada del DI
- [ ] Validación de la métrica de distancia contra lo que se oye
- [ ] Lista definitiva de los 10 temas de referencia, en WAV o FLAC
- [x] Modelo local para detectar pulso y compases: Beat This! (P4, ADR-006)
- [ ] Gigboard (con firmware NAM custom) y Spark GO y NEO: previstos para v2, a confirmar


## Fuentes externas (mini-spec de la Fase 2b)

Importar un tema pegando un enlace de YouTube o de Spotify. Decisión y alternativas en ADR-008; números en `docs/probes/P7-fuentes.md`. Jorge dio por bueno Opus de oído el 15/11/2026, así que D2 queda firme. Estado: implementada y cerrada el 15/11/2026 (ADR-011).

### Recorrido

1. **Enlace.** Se admiten `youtube.com/watch?v=`, `youtu.be/`, `music.youtube.com/watch?v=`, `open.spotify.com/track/<id>` (con o sin prefijo `intl-xx`) y `spotify:track:<id>`. Listas y álbumes: ver «Listas». Episodios y cualquier otra cosa se rechazan con mensaje.
2. **Metadatos.**
   - Spotify: `GET https://open.spotify.com/embed/track/<id>` y lectura del JSON `__NEXT_DATA__`: título, artistas, duración y carátula (la mayor de las tres). Sin credenciales ni API.
   - YouTube: `yt-dlp -J --no-playlist <url>`: `track` y `artist` si vienen, y si no `title` y `channel`; duración y miniatura.
3. **Candidatos (solo Spotify).** `ytsearch5:<artista> <título>` con `--flat-playlist -J`. Se enseñan los cinco, ordenados por diferencia absoluta de duración con Spotify, cada uno con título, canal, duración y diferencia con signo. Los que quedan a 3 s o menos llevan la marca «cercano» (en P7 los tres correctos estaban entre 0,8 y 3,2 s; el umbral se revisa con la prueba ampliada). La prueba ampliada confirmó el umbral para versiones distintas (correcto más lejano a 2,7 s, incorrecto más cercano a 4,1 s) pero no para directos: un directo oficial quedó a −0,4 s. Por eso los candidatos cuyo título dice «directo», «en directo», «en vivo», «live» o «concierto» llevan además la marca «directo». Regla de Jorge (15/11/2026): se prefiere siempre la versión de estudio, salvo que el enlace pegado sea el de un directo. Si el título del tema en Spotify no dice que es un directo, los candidatos «directo» se enseñan al final de la lista, por detrás de los de estudio aunque su diferencia sea menor, y nunca se proponen en las listas. Si el título de Spotify sí lo dice (mismas palabras), es al revés: los «directo» van primero y son los únicos que se proponen. Ninguno viene preseleccionado: elige siempre Jorge. Con un enlace de YouTube no hay candidatos, solo una confirmación con título, canal y duración.
4. **Descarga.** `yt-dlp -f "bestaudio[acodec=opus]" --no-playlist --js-runtimes deno:<ruta>`, sin recodificar. Si el vídeo no ofrece Opus, se cae a M4A/AAC (`bestaudio[ext=m4a]`) y la hoja lo avisa («Sin Opus: descargado en M4A, agudos hasta ~16 kHz»); el códec queda en `origin.codec`. Decidido por Jorge el 15/11/2026; matiza ADR-008 D2, donde Opus sigue siendo la primera opción.
5. **Conversión.** `ffmpeg -i audio.<webm|m4a> -c:a pcm_s24le audio.wav`, a la frecuencia del original (48 kHz en Opus, 44,1 kHz en M4A) y sin remuestrear. El fichero descargado se borra.
6. **Importación.** El WAV entra por `Library.importSong`, igual que un fichero: queda como `source/original.wav` y de ahí sale `audio/song.wav` a la frecuencia de trabajo. A partir de aquí el tema es uno más de la biblioteca, listo para separar.

Título y artista se pueden corregir en la hoja antes de importar. La descarga y la conversión ocurren en una carpeta temporal que se borra al terminar, al fallar o al cancelar.

### Interfaz

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

### Errores

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

### Datos

`Song` gana un campo opcional `origin` (`SongOrigin`): `kind` (`youtube` o `spotify`), `url` (el enlace pegado), `videoID`, `channel`, `spotifyID`, `album`, `artwork` (ruta relativa, `source/cover.jpg`), `codec`, `ytDlpVersion` e `importedAt`. Es aditivo y opcional: `schemaVersion` sigue en 2 y los proyectos actuales se leen sin migración. El índice de SwiftData no cambia (ya guarda título y artista). `Library.importSong` admite metadatos opcionales (título, artista, origen y fichero de carátula) para no deducir el título del nombre del fichero, y comprueba el duplicado por `videoID`.

### Código

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

### Helpers embebidos

| Helper | Origen | Licencia |
|---|---|---|
| yt-dlp | `yt-dlp_macos` de la release oficial, versión y SHA-256 fijados | Unlicense |
| Deno | `deno-aarch64-apple-darwin.zip` de la release oficial, versión y SHA-256 fijados | MIT |
| ffmpeg | Compilado propio desde el tarball oficial (versión y SHA-256 fijados), mínimo: `--disable-everything --disable-autodetect` más demuxers Matroska/WebM y MOV/MP4, parsers y decodificadores nativos de Opus y AAC, codificador `pcm_s24le`, muxer WAV y protocolo de ficheros. Sin `--enable-gpl` ni `--enable-nonfree` | LGPL 2.1 o posterior |

- `Tools/helpers/fetch.sh` baja y verifica yt-dlp y Deno; `Tools/helpers/build-ffmpeg.sh` compila ffmpeg (solo necesita las herramientas de línea de comandos de Xcode). Los dos dejan el resultado en `Vendor/helpers/`, que no se versiona. Las versiones y sumas viven en `Tools/helpers/versions.env`.
- Una fase de script de `App/project.yml` copia los tres a `Contents/MacOS/` y firma cada uno con la identidad de la app, igual que `tf-separate`. Si falta `Vendor/helpers/`, el build falla nombrando el script que hay que lanzar. Sin notarización ni hardened runtime (ADR-001), así que el JIT de Deno no necesita permisos extra.
- El ffmpeg mínimo se valida una vez contra la conversión de P7: misma duración y diferencia nula frente al WAV de `Temp/p7/out/best-deno/`.
- **Actualización de yt-dlp.** El del bundle es la base. «Actualizar yt-dlp» baja la última release, verifica el SHA-256 y la deja en `Application Support/ToneForge/Helpers/yt-dlp` con un `yt-dlp.json` (versión, suma, fecha). Se usa la más nueva de las dos. Cuando una descarga o una búsqueda falla con error de extractor, la hoja ofrece «Actualizar y reintentar». Deno y ffmpeg solo cambian con una build nueva.

### Listas

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

### Estimación y condición de paso

De 5 a 8 horas con las listas (de 3 a 5 sin ellas). Fila para la tabla del plan: «2b. Fuentes externas · 5 a 8 · marca el ritmo compilar ffmpeg y probar descargas reales con varios temas»; los acumulados posteriores suben lo mismo.

Condición de paso: pegar un enlace de YouTube y otro de Spotify deja cada tema en la biblioteca listo para separar, sin más paso manual que elegir candidato; pegar una lista o un álbum, marcar parte de sus temas y pulsar «Descargar y procesar» los deja importados y separados; y la prueba ampliada con al menos cinco temas (uno sin subida oficial, uno con el directo dominante y uno largo) queda anotada en `docs/probes/P7-fuentes.md` con cuántos aciertan el candidato correcto.


## Fases y roadmap

Dos etapas. La Etapa 1 es la herramienta de estudio y la grabación con vídeo, con la pedalera solo como interfaz de audio y el rig que tú tengas cargado. La Etapa 2 es el igualado de tono, que depende de poder controlar el Remote Editor; si eso falla, pasa a modo "guía visual + carga manual".

| Etapa | Fase | Entregable | Requisitos | Condición para pasar a la siguiente |
|---|---|---|---|---|
| 1 | 0. Pruebas P2, P4 y P6 | Scripts de prueba: audio USB, conversión de modelos, calidad al ralentizar | — | Audio grabado por USB y un tema separado en local |
| 1 | 1. Base y biblioteca | App, proyectos, importar tema y separar stems | — | Un tema importado y separado, con sus stems en disco |
| 1 | 2. Herramienta de estudio | Mezclador de backing track, velocidad, transposición, bucles, acordes, tempo | RF7, RF10 | Tocar encima de un tema sin guitarras, en bucle y al 70 % |
| 1 | 2b. Fuentes externas | Importar desde un enlace de YouTube o Spotify, o desde una lista o un álbum, con helpers embebidos | — | Un enlace de YouTube y otro de Spotify dejan el tema listo para separar, sin más paso manual que elegir candidato; una lista o un álbum, con temas marcados y «Descargar y procesar», los deja importados y separados |
| 1 | 3. Audio con la pedalera | Selección de E/S, latencia, escucha del backing, grabación de DI y procesada | RF1 | Toma alineada con el backing con error menor de 1 ms |
| 1 | 4. Guitarras y secciones | Separar guitarra A y B, marcar secciones rítmica y solista | RF6, parte de RF5 | Robe y Uoho en pistas distintas en 3 temas de prueba |
| 1 | 5. Tablatura | Transcripción de guitarras, bajo y batería, tablatura con cursor, exportación a Guitar Pro | Parte de RF2, RF11 | Tablatura de un tema exportada y abierta en Guitar Pro |
| 1 | 6. Grabación con vídeo | Cámara sincronizada, audio multipista, multitoma | RF8, parte de RF9 | 3 tomas grabadas y alineadas a menos de 1 fotograma |
| 1 | 7. Montaje | Layouts, transiciones, encuadre de la guitarra, exportación | RF9 | Vídeo final exportado en portrait y landscape |
| 2 | Pruebas P1, P3 y P5 | Scripts de prueba: Remote Editor, TONE3000, velocidad del bucle | — | Un parámetro cambiado desde script y un reamp grabado |
| 2 | 8a. DI guiado | Toma grabada siguiendo la tablatura, validada y guardada como DI | Parte de RF2 | Toma válida a la primera en riffs sencillos |
| 2 | 8. Análisis del tono | Reamp, huella, distancia, plantillas de rig y TONE3000 | RF4 | La distancia ordena los tonos igual que tu oído en 3 temas |
| 2 | 9. Igualado en la pedalera | Conector HeadRush, catálogo de bloques, optimizador sobre la pedalera, rig con escenas | RF3, RF5 | Rig cargado en la Flex Prime en menos de 10 min |
| v2 | 10. Ampliaciones | Gigboard y Spark | — | Según pendientes |

Tareas de cada fase:


## Fuentes

- HeadRush Flex Prime FAQ (Remote Editor, MIDI PC/CC/Clock)
- SweetCare: HeadRush Remote Editor (el editor corre en la pedalera y se accede por Wi-Fi)
- SweetCare: Flex Prime quickstart (firmware 5.1 con NAM A2 de TONE3000)
- Manual Flex Prime v5.2
- TONE3000 API
- Moises: separación solista y rítmica
- Music.AI: guitar parts
- TonesMatch y ToneAdapt (competencia)

- BS-RoFormer SW, separación en 6 stems y comparativa de calidad de MVSep
- BTC, reconocimiento de acordes y estudio con su tasa de acierto
- Beat This! (CPJKU, MIT) y `jessengatai/supracut-beat-this` (Core ML)
- ADTOF (Zehren et al.) y su puerto `xavriley/ADTOF-pytorch`: transcripción de batería
- Fender Riffstation: funciones

- alphaTab: exportación a Guitar Pro 7 y fallo de las baterías exportadas con RSE
- Omnizart: transcripción de batería
