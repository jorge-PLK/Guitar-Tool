
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
| RF1 | Conexión directa de la pedalera | Dispositivo genérico (cualquier pedalera o interfaz): entrada y salida elegibles por separado, con canales de guitarra y de backing. Calibración automática de latencia con un pulso de prueba. El DI y el reamp pasan a la Etapa 2 (ADR-012). | Medido en la Fase 3 (ADR-013, 48 kHz, búfer 512): ida y vuelta de 1339,27 a 1566,24 muestras (27,9 a 32,6 ms) por la guitarra del canal 1, y retardo del rig vacío de 70,7 muestras; la latencia se acorta a escalones de 12 muestras (0,25 ms) que el HAL no refleja (límite conocido). La Flex Prime actúa como interfaz USB (P2, firmware 5.2.0, sin driver): 4 entradas y 4 salidas. Entrada al Mac: ch1/ch2 procesado, ch3 DI seco, ch4 copia del DI. Salida del Mac: ch1/ch2 directo a salidas y auriculares sin pasar por el rig (el backing), ch3 entrada del rig en USB Mode Reamp. El retorno no incluye el backing. La latencia declarada por el dispositivo (1200 muestras) no es fiable: la medida fue de 2416 muestras (50,3 ms) y varía ~1,2 ms según el rig, así que se calibra con pulso. Admite 44,1, 48 y 96 kHz; 44,1 kHz es posible y es la nativa de los modelos. |
| RF2 | Tablatura con play para grabar el DI | Genera la tab de la sección objetivo (riff o solo) a partir de la guitarra aislada, editable. Reproduce con cursor, metrónomo y tempo variable. Graba la toma y la valida: afinación, timing y clipping. | Transcripción con basic-pitch y render con alphaTab. Reutilizable la herramienta audio → Guitar Pro del proyecto estilo Rocksmith. |
| RF3 | Editar presets de la Flex Prime desde la app | Lee y escribe rigs: bloques, parámetros, escenas, carga de NAM e IR. | El Remote Editor se sirve desde la propia pedalera por Wi-Fi: hay que hacer ingeniería inversa de su API HTTP o WebSocket. El MIDI solo admite Program Change, CC y Clock. Plan B: copiar rigs por USB Transfer. |
| RF4 | Conexión a TONE3000 | Inicio de sesión, búsqueda y descarga de NAM (A2) e IR, filtrados por marca y modelo del ampli original. Envío directo a la pedalera. | La API nació dando acceso a tonos creados o favoritos del usuario. Verificar que la búsqueda en todo el catálogo ya está abierta. |
| RF5 | Tonos rítmico y solista | Detecta o deja marcar las secciones en la forma de onda. Genera dos escenas en el mismo rig: solista con más ganancia y medios, +2 a 3 dB y delay corto. | El solo suele llevar otra toma u otro equipo: cada sección se iguala por separado. |
| RF6 | Guitarras por separado (p. ej. Robe y Uoho) | Separa las guitarras del tema, propone dos pistas y el usuario las nombra y elige cuál igualar. | Todo en local, sin APIs de pago: aislar guitarras con un modelo local y separar A/B por panorama estéreo. Solista frente a rítmica, por heurística con Basic Pitch (acordes = rítmica, notas sueltas = solista) y marcado manual. Calidad parcial cuando ambas tocan lo mismo doblado. |
| RF7 | Modo backing track | Mezclador con mute, solo y volumen por stem (voz, batería, bajo, resto y cada guitarra separada). Quitar todas las guitarras o solo las elegidas, p. ej. quitar a Uoho y dejar a Robe. Bucle de secciones, tempo variable sin cambiar el tono y metrónomo opcional. Tu guitarra suena por la Flex Prime a la vez (monitorización directa, sin latencia añadida) y se puede grabar la toma: procesada en la Etapa 1; el DI seco queda para la Etapa 2 (ADR-012). Para analizar mejor: A/B de tu tono contra la guitarra original dentro de la mezcla y no en aislado, medida de la diferencia en vivo y la toma grabada se puede usar como DI para el reamp (RF2). | Reutiliza los stems ya separados en RF6: no añade modelos. Cambio de tempo con AVAudioUnitTimePitch. Si se quita una sola guitarra de dos, puede quedar algo de ella en la otra pista. |
| RF8 | Modo grabación (vídeo + audio multipista) | Graba a la vez la webcam y el audio sobre el backing track. El audio se guarda en pistas separadas y alineadas: backing (estéreo), guitarra DI (seco), guitarra procesada de la Flex Prime (estéreo) y micro opcional. Exporta el vídeo con la mezcla y los WAV de cada pista para remezclar después.Sincronía: el audio manda; el vídeo se alinea por marcas de tiempo y una calibración inicial (palmada o destello en pantalla) corrige el retardo de la cámara. | AVCaptureSession para la cámara y AVAudioEngine para el audio, con el mismo reloj de host. Webcam a 1080p y 30 o 60 fps según lo que dé la cámara. Fase 6: sin calibración automática ni micro; desfase manual por cámara, ADR-015. |
| RF9 | Modo multitoma y montaje en un único vídeo | Eliges qué partes vas a grabar a partir de las guitarras separadas (p. ej. rítmica de Robe, rítmica de Uoho y solo). En cada toma suena el backing sin esa parte y con tus tomas anteriores. Puedes repetir partes y elegir la mejor toma de cada una.Al final monta todo en un vídeo con layouts landscape (1920 × 1080: lado a lado o rejilla) y portrait (1080 × 1920: apilado vertical).Solista: su vídeo y su audio solo aparecen en las secciones de solo (RF5); el resto del tiempo su recuadro desaparece y el layout se redistribuye.Portrait con una rítmica y una solista: un solo plano a pantalla completa, la rítmica durante el tema y la solista en los solos, con encuadre recortado sobre la guitarra para que se vea lo más grande posible. | Montaje con AVMutableComposition + AVVideoComposition y exportación HEVC o H.264 con AVAssetWriter. Encuadre automático con Vision (pose corporal: muñecas, codos y torso delimitan la guitarra), con ajuste manual del recorte por toma. Transiciones suaves y modernas: los recuadros se recolocan y cambian de tamaño con animación tipo muelle (ease-in-out, unos 0,5 s); el que entra aparece con escala del 92 al 100 %, opacidad y un desenfoque que se aclara; el que sale hace lo inverso. Esquinas redondeadas y sombra suave en los recuadros. Las transiciones van alineadas al pulso del tema y empiezan 0,5 s antes del solo, para que la solista esté a pantalla completa en la primera nota. El audio de la solista entra y sale con fundidos de 50 a 100 ms, sin cortes. Compositor de vídeo propio (AVVideoCompositing con Metal o Core Image) que interpola cada fotograma; vista previa en tiempo real antes de exportar. |
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
| Audio | Dispositivos de entrada y de salida, canales de guitarra y de backing, volumen master global (en el perfil de equipo, igual en todos los temas), frecuencia de muestreo (de trabajo, global, 44,1 o 48 kHz; cada proyecto guarda la suya y se reconvierte solo al abrirlo, en segundo plano y sin avisar; los stems se remuestrean, no se vuelven a separar) y calibración de latencia. El DI seco, la salida de reamp y la calibración del nivel del DI llegan en la Etapa 2 (ADR-012) |
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
| Motor de audio | Elegir dispositivo y canales, mandar el backing al dispositivo, grabar la guitarra, calibrar latencia con un pulso | `AudioSession` sobre `AudioIO` (CoreAudio real y simulada); el reproductor se aloja en la sesión con `AVAudioEngine` en render manual en tiempo real, donde `AVAudioUnitTimePitch` retrasa 4096 muestras (0 en offline) y los stems salen de `StemFeed` (ADR-013) |
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
| Transcripción de batería con ADTOF: fallan algunos platos (charles confundido con crash o ride) | Bajo | Corregir a mano; mejora prevista en la Fase 5b. La batería exportada suena con RSE en Guitar Pro 8 (ADR-016) |
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


## Audio con el dispositivo (mini-spec de la Fase 3)

Elegir dispositivo y canales, calibrar la latencia, mandar el backing al dispositivo, grabar la señal procesada y alinearla con el backing (RF1, parte de RF7). Estado: implementada y cerrada el 15/11/2026 (ADR-013).

Decidido por Jorge el 15/11/2026:

- **Nada cableado a la Flex Prime.** La app trabaja con cualquier pedalera o interfaz: se elige entre todas las entradas y salidas del sistema y se asigna cada canal a mano. Ninguna lógica mira el nombre del dispositivo.
- **Entrada y salida pueden ser dispositivos distintos**, con corrección de deriva.
- **El DI sale de la Etapa 1.** En esta fase no hay canal de DI, ni calibración de su nivel, ni grabación del DI seco: la app no pide nada sobre el DI. Todo ello pasa a la Etapa 2 (Fase 8a), y allí irá oculto al usuario. Esto cambia las casillas de la Fase 3 del plan y la pista de DI de la Fase 6: va en un ADR nuevo.
- **A/B:** en directo y con la última toma.

### Dispositivo y canales

Lo que se guarda en el perfil de equipo (`EquipmentProfile.audio`, opcional y aditivo; un perfil antiguo se lee sin él):

| Campo | Contenido |
|---|---|
| `outputDeviceUID` | Dispositivo de salida. Vacío = salida por defecto del sistema |
| `inputDeviceUID` | Dispositivo de entrada. Vacío = sin entrada (no se puede grabar) |
| `backingOut` | Par de canales de salida del backing. Por defecto 1 y 2 |
| `guitarIn` | Uno o dos canales de entrada con tu guitarra tal como suena (la señal procesada) |
| `bufferFrames` | 512 fijo (el probado en el soak de P2); no se enseña |
| `latency` | Última calibración de latencia, con el canal de referencia interno si lo hay (ver abajo) |

Reglas:

- Los selectores listan todos los dispositivos con entradas y todos los que tienen salidas, por separado, con el número de canales de cada uno. Al elegir un dispositivo, el backing queda en 1 y 2 y los demás papeles sin asignar. Para saber qué canal es cuál, cada canal de entrada muestra un medidor en vivo en el propio selector.
- Para grabar hace falta `guitarIn`. Un canal no puede tener dos papeles.
- **Mismo dispositivo en entrada y salida:** un solo reloj, se abre tal cual. **Dispositivos distintos:** la app crea un dispositivo agregado privado (no aparece en el sistema) con la salida como reloj maestro y corrección de deriva en la entrada, y lo destruye al cerrar. La toma guarda con cuál de los dos modos se grabó.
- **Convivencia con la Fase 2:** desaparece la salida automática. `OutputRouting.isFlexPrime`, `flexPrimeName` y `flexPrimeOutputs` se eliminan; el backing sale por `outputDeviceUID` y `backingOut`, y si no hay nada elegido o el dispositivo no está, por la salida por defecto del sistema, canales 1 y 2. `FlexPrimeMonitor` pasa a `AudioDeviceMonitor` y la barra lateral muestra el nombre del dispositivo elegido y si está conectado. Consecuencia: tras actualizar hay que elegir la pedalera una vez en Ajustes.
- **Dispositivo no conectado:** el backing sigue por la salida por defecto; grabar, calibrar y el A/B en directo quedan desactivados con el motivo a la vista. La configuración no se borra y se recupera sola al reconectar. Si se desconecta a mitad de toma, la toma se detiene y se guarda lo grabado.
- **Frecuencia:** al abrir el dispositivo la app le pide la frecuencia de trabajo. Si el dispositivo no la acepta (la Flex Prime solo la cambia desde su menú), el backing sigue sonando (el motor convierte), pero grabar y calibrar se bloquean con el aviso «El dispositivo está a X kHz y la frecuencia de trabajo es Y kHz» y el botón «Usar X kHz como frecuencia de trabajo». Un cambio de frecuencia caduca la calibración.

### Calibración de latencia

Qué se mide: las muestras entre que una señal sale por el canal izquierdo de `backingOut` y vuelve por el primer canal de `guitarIn`. Es justo el desfase que tendrá una toma respecto al backing que se oye. Hace falta un bucle físico: un cable de una salida del dispositivo a su entrada de guitarra. Es el único método que vale para cualquier equipo e incluye los conversores.

- **Señal:** barrido logarítmico de 500 Hz a 8 kHz, 100 ms, con fundidos de 5 ms, a −12 dBFS. 10 repeticiones cada 500 ms; la primera se descarta.
- **Detección:** correlación cruzada con el barrido enviado (filtro adaptado). Se toma la primera llegada, no el máximo: el pico más temprano que alcance el 50 % del mayor, para que un eco del bucle no engañe. Submuestra por interpolación sinc de la correlación alrededor del pico.
- **Resultado:** mediana de las 9 medidas, en muestras con decimales, y dispersión (máximo menos mínimo). Válida si la dispersión es de 0,1 ms o menos y el pico destaca 20 dB sobre el fondo. Si no, se dice por qué: sin señal (falta el cable), saturada (bajar volumen) o inestable.
- **Lo que se guarda:** latencia, dispersión, fecha y la clave: UID de entrada y de salida, frecuencia, búfer, canal de referencia y canal de salida.
- **Caducidad:** la calibración vale mientras la clave no cambie. Si cambia cualquier campo, el estado pasa a «Sin calibrar». No caduca por tiempo; se enseña la fecha.
- **Sin calibrar no se bloquea la grabación** (decisión de Jorge). Lo que se mide en cada toma es solo el retardo del rig; la latencia de ida y vuelta (unos 50 ms con la Flex Prime) solo sale del pulso con cable. Por eso, sin calibración válida la toma se alinea con la latencia que declara el dispositivo (poco fiable: en P2 declaraba 25 ms y eran 50), se marca con `latencyCalibrated = false` y Backing avisa de que puede ir desfasada decenas de ms. Al calibrar después, las tomas sin calibrar hechas con esa misma clave se vuelven a desplazar solas con la latencia buena.
- **Variación entre rigs: se corrige en cada toma, sin preguntar nada.** Durante la calibración el barrido llega a todos los canales de entrada del dispositivo, no solo a `guitarIn`. Si alguno que no es `guitarIn` lo recibe antes, ese canal lleva la señal sin pasar por el rig: la app lo guarda como canal de referencia interno (`referenceIn`) junto con su latencia, que no depende del rig. No se enseña ni se graba. En cada toma se mide el retardo de `guitarIn` respecto a ese canal (ver Alineado). Si ningún canal llega antes (una interfaz sin rig dentro), no hay referencia ni hace falta: la latencia calibrada de `guitarIn` vale tal cual.
- **Con una pedalera el bucle realimenta** (entrada → rig → salida → cable → entrada). Por eso se calibra con un rig vacío o con el volumen del rig bajo, y por eso se toma la primera llegada. Además, el bucle a través del rig oscila (se midieron tonos de 2794 y 2255 Hz a −21 y −18 dBFS) y falsea la medida: se recomienda silenciar el rig y medir por el canal seco, o dejar el volumen muy bajo. `tf-audio verify` responde «NO CONCLUYENTE» si detecta oscilación (pico ≥ −60 dBFS y ≥ 30 dB sobre su entorno).

Medido con la Flex Prime (ADR-013): la variación entre reinicios seguidos del motor es 0,00 muestras, así que la calibración vale entre reinicios y no hace falta calibrar por sesión. Límite conocido del aparato, aceptado por Jorge (no se aprecia de oído): su latencia se acorta a escalones de 12 muestras exactas (0,25 ms), que el HAL no refleja y que sobreviven al cierre de la sesión. Se midieron 0 escalones en una toma de 60 s, 24 muestras en otra y 36 (0,75 ms) en una de 300 s. No hay corrección: `verify` registra las marcas de host (`Temp/tf-audio/verify-hal.csv`) para saber si el Mac puede verlo, y la compensación (`--track-host`) no está hecha. La regla de caducidad no cambia.

### DI: fuera de esta fase

Pasa a la Fase 8a, junto con el DI guiado (ADR-010): el canal del DI, la calibración de su nivel (queda apuntado para entonces lo hablado: pico entre −12 y −3 dBFS tocando fuerte, por guitarra), la grabación del DI seco y «Usar la última toma como DI». La salida de reamp tampoco se incluye: ni en Ajustes ni en el perfil, hasta la Etapa 2 o hasta que Jorge lo indique. También sale de la Fase 6 la pista de DI del multipista. Lo único que queda aquí es el canal de referencia interno de la calibración, que la app encuentra sola y usa solo para medir el retardo del rig. En la Etapa 2 nada de esto se le pide al usuario de forma directa. El pendiente «Calibración del nivel de entrada del DI» sigue abierto. El boceto de Ajustes muestra «Entrada DI» y «Calibrar nivel del DI»: no se construyen.

### Grabación

- Botón «Grabar» de la pantalla Backing. Graba desde la posición actual hasta que se pulsa parar, con el backing sonando por `backingOut`.
- **Fichero:** `takes/<id>/processed.wav` (mono o estéreo, según `guitarIn`), WAV float32 a la frecuencia del proyecto.
- **Se guarda ya alineado:** la muestra 0 corresponde al instante `songStart` del tema. Quien lo lea después no necesita saber nada de latencias.
- **`Take` gana campos opcionales**, todos aditivos: `songStart` (segundos), `sampleRate`, `latencySamples`, `rigDelaySamples`, `rigDelayReliable`, `latencyCalibrated`, `calibrationKey` y `clock` (`single` o `aggregate`). `processedFile` ya existe; `diFile` se queda vacío hasta la Etapa 2. `schemaVersion` sigue en 2 y no hay migración, como pasó con `origin`.

### Alineado con el backing

1. El reproductor publica un ancla al arrancar: qué posición del tema corresponde a qué muestra de salida, contando la latencia de sus propios nodos (Varispeed y TimePitch).
2. Las muestras de entrada llegan con su marca de tiempo. La posición del tema de cada muestra grabada es la del ancla menos la latencia calibrada.
3. Si hay canal de referencia interno, el retardo del rig en esa toma se mide por correlación cruzada de las envolventes de `guitarIn` y del canal de referencia, en una ventana de 0 a 20 ms. Si el pico no es claro (mucho delay o reverb), se usa el último valor fiable, la toma se marca con `rigDelayReliable = false` y se avisa. El canal de referencia se escucha solo para medir: no se guarda en disco.
4. La toma se desplaza la latencia de la referencia más el retardo del rig, redondeado a muestras enteras; el resto, de media muestra como mucho (unos 10 µs), se ignora. Sin canal de referencia, se desplaza la latencia calibrada de `guitarIn`.

**Demostración sin hardware (tests de la puerta).** `SimulatedAudioIO` devuelve por la entrada lo que sale por la salida con una latencia conocida, con decimales, y admite saturación, ruido y deriva en ppm. Con él:

- La calibración recupera la latencia con error de 0,05 muestras o menos, a 44,1 y 48 kHz, con latencias con decimales, ruido a −60 dB y un eco posterior más fuerte que la primera llegada.
- Falla con el motivo correcto sin señal, con saturación y con dispersión alta.
- **Test de la condición de paso:** el reproductor en render offline toca un backing con clics; el dispositivo simulado lo devuelve con latencia L; se calibra, se graba una toma y se comprueba que cada clic de la toma alineada cae donde el del backing con error de 1 muestra o menos (0,02 ms), al principio y al final de una toma de 60 s. Se repite arrancando a mitad de tema.
- La calibración aguanta una vuelta saturada (como la de un rig con ganancia) con error de 1 muestra o menos.
- Con un canal simulado que llega antes que `guitarIn`, la calibración lo elige como referencia; sin él, no elige ninguno.
- El retardo del rig por toma se recupera con error de 2 muestras o menos con saturación, también cuando es distinto del que había al calibrar, y se marca como no fiable con un delay del 100 %.
- Con una calibración de otra clave, la toma se graba con la latencia declarada y queda marcada como sin calibrar; al calibrar después se corrige y pasa el test de la condición de paso.

**Demostración con hardware (condición de paso).** Una toma de comprobación con el cable puesto: `tf-audio verify` (y lo mismo desde la app) reproduce 60 s de clics, graba la vuelta, alinea y da el error de cada clic en muestras y en ms, con el máximo y la pendiente (la pendiente es la deriva sin corregir, lo que importa con dos dispositivos). Pasa si el máximo es menor de 1 ms. Después, una toma tocada sobre un tema, para oírla.

### A/B dentro de la mezcla

Panel «Comparar en la mezcla» de Backing, sobre el stem de guitarra (con la Fase 4 se podrá elegir cuál).

- **A · Original:** el stem de guitarra suena.
- **B · Tú en directo:** el stem se silencia y te oyes por la monitorización del dispositivo. La app no controla ese volumen, así que no compensa: enseña la diferencia de nivel en dB (RMS de tu procesada en los últimos 3 s frente al del stem en ese tramo, con su fader) para que la ajustes en el aparato.
- **B · Última toma:** el stem se silencia y suena tu toma procesada, alineada, por la misma cadena que los stems (sigue la velocidad). Se iguala en sonoridad al stem de forma automática: RMS con ponderación K sobre el tramo de la toma, sin contar silencios, con tope de ±12 dB; la ganancia aplicada se enseña. La toma aparece como canal «Tú» en el mezclador.
- La medida de diferencia de tono («Diferencia en directo» del boceto) es de la Etapa 2; aquí solo nivel.

### Ajustes · Audio

Como el boceto, con los cambios de arriba: grupo Dispositivo (entrada, salida, frecuencia), grupo Canales (entrada de guitarra y salida del backing, con medidores de entrada) y grupo Calibración (estado y fecha de la latencia y el botón «Calibrar latencia», con su hoja: instrucciones, progreso, resultado en números). Nada de DI.

### Código

Todo el audio en **AudioKit**; Store solo guarda datos y no depende de AudioKit (la app hace de puente, como hasta ahora).

| Pieza | Paquete | Qué hace |
|---|---|---|
| `AudioDevice`, `AudioDeviceProviding` | AudioKit | Dispositivos con entradas y salidas, frecuencias admitidas, cambios. Sustituye a `AudioOutputDevice`. `CoreAudioDeviceProvider` y `SimulatedDeviceProvider` |
| `AudioSetup`, `AudioRouting` | AudioKit | Configuración resuelta (dispositivos, canales, modo de reloj) y la regla de la salida por defecto |
| `AudioIO` → `CoreAudioIO`, `SimulatedAudioIO` | AudioKit | El protocolo detrás del que queda el hardware: abrir una sesión dúplex, entregar la entrada con marcas de tiempo y emitir la salida. La versión real incluye el agregado privado |
| `LatencyProbe`, `LatencyCalibrator` | AudioKit | Barrido, detección de primera llegada con submuestra y estadística |
| `TakeRecorder`, `TakeAligner` | AudioKit | Captura y escritura del WAV alineado |
| `LoudnessMatch` | AudioKit | Ganancia de la toma frente al stem |
| `StudyPlayer` | AudioKit | Ancla de reproducción, pista de toma con desplazamiento y salida según `AudioSetup` |
| `tf-audio` | AudioKit | Ejecutable de desarrollo, no se embebe: `devices`, `latency`, `verify`, `record`. Da números y deja los WAV en `Temp/` |
| `AudioSettings`, `LatencyCalibration`, campos de `Take` | Store | Datos |
| Ajustes · Audio, `AudioDeviceMonitor`, grabar y A/B en Backing | App | Interfaz y cableado |

Reparto: tres tandas. Primera, en paralelo: señal y simulador (`tf-engineer`) y datos de Store más dispositivos genéricos (`tf-implementer`). Segunda, en paralelo: E/S real, grabador, reproductor y `tf-audio` (`tf-engineer`) y Ajustes · Audio (`tf-implementer`). Tercera: grabar y A/B en Backing (`tf-implementer`). Luego `tf-qa`.

### Medidas con hardware (las hace Jorge)

Con la Flex Prime: USB Mode **Live**, 48 kHz, búfer 512. Montaje real usado (ADR-013): rig silenciado y `--guitar 3`, es decir, midiendo por el canal seco, porque el bucle a través del rig oscila. Cable de jack de la salida principal izquierda (o de auriculares) a la entrada de guitarra, con el volumen de salida a un tercio. En Ajustes: entrada y salida «HeadRush Flex Prime», backing 1 y 2, guitarra 1 y 2. Con otro aparato, lo mismo con sus canales.

1. `tf-audio latency --restarts 5`: latencia en ms, dispersión y variación entre reinicios.
2. `tf-audio verify`: error de alineado máximo y pendiente. Esto es la condición de paso.
3. Repetir 2 con entrada y salida en dispositivos distintos, para ver qué deja la corrección de deriva.
4. Quitar el cable, cargar un rig real y grabar una toma tocada: oír el A/B.

### Reglas propias de esta fase (aprobadas por Jorge el 15/11/2026)

- Solo se graba a velocidad del 100 % y con el bucle desactivado; con otra velocidad, el botón se desactiva y dice por qué.
- Sin cuenta atrás ni margen previo en esta fase: llegan con la pantalla de grabación (Fase 6) y el DI guiado (Fase 8a).
- Búfer fijo de 512, sin selector.
- El aviso y el botón de frecuencia descritos arriba.
- La latencia sin calibrar no bloquea la grabación: avisa, marca la toma y la corrige al calibrar.

### Estimación y condición de paso

De 4 a 6 horas, frente a las 2 a 4 del plan. La diferencia: dispositivos genéricos en lugar de la Flex Prime fija, entrada y salida en dispositivos distintos y el A/B con la toma grabada; quitar el DI resta cerca de una hora. Fila para el plan: «3. Audio con el dispositivo · 4 a 6 · marca el ritmo las pruebas de latencia y niveles con el hardware».

Condición de paso: toma grabada alineada con el backing con error menor de 1 ms, medido con la toma de comprobación de Jorge.


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


## Guitarras y secciones (mini-spec de la Fase 4)

Separar la pista de guitarras en una pista por guitarra, clasificar sus pasajes en rítmica o solista, nombrarlas y llevarlas al mezclador (RF6, parte de RF5). Va en paralelo con la Fase 3, en la rama `fase-4` (worktree aparte). Decidido por Jorge el 15/11/2026: la condición de paso se comprueba solo de oído con 3 temas de Extremoduro; la prueba de modelos de guitarra va primero y falla rápido; la separación propone izquierda, derecha y centro y descarta la que salga vacía.

### Opciones de guitarras y tramos de solo (revisión de Jorge, 15/11/2026; manda sobre lo que contradiga más abajo)

Tres opciones por canción, guardadas en `project.json`:

1. **Una pista (por defecto).** Todas las guitarras en `stems/guitar.wav`, canal «Guitarras» del mezclador, como hasta la Fase 3.
2. **Guitarras en L y R (interruptor).** L = canal izquierdo, R = canal derecho de `stems/guitar.wav` (`stems/guitar_L.wav`, `stems/guitar_R.wav`). Sin centro ni máscara de panorama: la pista central desaparece como concepto.
3. **Tramos de solo (varios por canción, marcados a mano).** Dentro de cada tramo, el modelo de solista frente a rítmica saca el solo a `stems/guitar_lead.wav`; lo que queda del tramo vuelve a la parte rítmica. Fuera de los tramos, la solista vale 0 y la rítmica es la pista de guitarras entera. La parte rítmica es una pista (`stems/guitar_rhythm.wav`) o L y R, según el interruptor de la opción 2. Fundidos de 100 ms en los bordes. Sin tramos no hay solista.

- Las pistas siempre suman `stems/guitar.wav`. Los tramos marcados a mano nunca se descartan por nivel.
- Modelo: Mel-Band RoFormer «Lead_Rhythm_Guitar» (pesos anónimos de Hugging Face, licencia openrail; uso personal). Saca la solista; rítmica = entrada − solista. Probado en Platero y T3 el 15/11/2026 (Jorge lo da por bueno de oído). Va a Core ML; ADR propio.
- El solo es una sección más (Jorge, 15/11/2026): una sola lista de secciones por canción, cada una con inicio, fin, nombre y la marca «Solo». Los tramos de solo de la separación salen de las secciones con «Solo» (fuente única de verdad).
- Interfaz: interruptor «Guitarras en L y R». Sin carriles de secciones ni de solos en Backing: las secciones se dibujan como cajas con su nombre por encima de la tira de acordes, envolviendo los acordes que abarcan (borde ajustado al acorde más cercano solo en el dibujo); las de solo, en naranja con insignia. Se marcan desde la tira: arrastrar sobre los acordes crea el bucle (⌥ = compases), se escucha, y «Marcar sección» / «Marcar como solo». En una caja: clic = bucle, arrastrar bordes = ajustar (imán al acorde, ⌥ al compás), clic derecho = renombrar, alternar «Solo», borrar. Una sección marcada dentro de otra la parte. «Aplicar» / «Descartar» solo con cambios; solo se reprocesan las pistas si cambian las secciones de solo. Objetivo: Backing sin scroll. Sustituye a los carriles de pasajes por guitarra y al editor «Aislar solo» con espectrograma y mapa de panorama (descartados por Jorge). Canales: «Guitarras»; o «Guitarra rítmica» + «Guitarra solista»; o «Guitarra izq.» + «Guitarra der.» (+ «Guitarra solista»).
- Sin propuesta automática de tramos en esta fase: el modelo marca como solista adornos fuera del solo (Platero 78–90 s) y el clasificador marcaba el 74 % del tema. `PassageClassifier` queda en TabKit, fuera de la cola.
- Condición de paso: se juzga con el interruptor L/R activado (Robe y Uoho en pistas distintas).

### Prueba de modelos de guitarra (primero)

- Candidatos: MVSep Mega 53 guitarra (lumabeat, MIT, MLX) y `becruily/mel-band-roformer-guitar` (sin licencia: uso personal, no redistribuir). Referencia a batir: BS-RoFormer SW con 8,23 / 11,03 / 4,38 dB de SDR en guitarra (T1 / T2 / T3), con la misma métrica y entrada que P4.
- Falla rápido: cada candidato se prueba con T1 en su runtime original; si no supera 8,23 dB se descarta sin seguir.
- Se adopta solo si la media de T1–T3 mejora en más de 1 dB y se puede pasar a Core ML (CPU+GPU). Si se adopta, entra como paso extra solo para la guitarra y su integración se decide con Jorge en un ADR. Si no, la Fase 4 trabaja sobre `stems/guitar.wav` de BS-RoFormer SW.
- Resultados en `docs/probes/P4-modelos.md`, apartado «Fase 4: modelos de guitarra». Scripts en `Probes/P4-modelos/guitar_models/`.

### Separación por panorama

- Entrada: `stems/guitar.wav` (estéreo, a la frecuencia de trabajo). Salida: hasta tres pistas estéreo en `stems/guitar_L.wav`, `stems/guitar_C.wav` y `stems/guitar_R.wav` (regenerables, como el resto de `stems/`).
- Método: STFT con Accelerate, índice de panorama por bin a partir de las magnitudes de L y R, y máscaras suaves por canal. La pista izquierda sale del canal L, la derecha del R y la de centro de los dos; en cada bin las máscaras suman 1. Así la suma de las pistas es la pista de guitarras, y con todas a 0 dB la mezcla no cambia. La misma máscara en los dos canales se probó y queda unos 7 dB peor con guitarras abiertas (T1, 15/11/2026). Los parámetros (anchura del centro, estrecha por defecto, y suavidad de la transición) son constantes con nombre, ajustables desde los tests.
- Pista vacía: se descarta la que cumpla `StemLevelMeter.isEmpty` (RMS < −60 y pico < −30 dBFS; el pico era −40 hasta el 21/11/2026, ver ADR-009 D11) o quede muy por debajo de la pista de guitarras (ver propuestas). Una pista descartada no aparece en el mezclador ni se guarda en disco.
- Confianza por pista (alta, media o baja): mezcla de cuánta energía de la pista cae lejos de las zonas de transición y de cuánto se parecen las envolventes de las pistas que quedan. Dos guitarras dobladas que tocan lo mismo dan media o baja (riesgo «rítmicas dobladas»); una guitarra sola con foco, alta; una entrada mono, baja. La correlación L/R de la entrada se descartó como criterio: daba baja a una guitarra sola paneada. Los umbrales se calibran con T1–T3, que tienen las guitarras por separado (`guitar_parts/`).
- **Descartado (ADR-014, 16/11/2026): toda esta sección de panorama y su puerta del centro; ninguna anchura sonó bien.** Queda como historia de la decisión. Centro con puerta (Jorge, 15/11/2026): la pista central solo existe en los pasajes de solo. Fuera de ellos C vale 0 y L y R se quedan cada una con su canal entero, sin que C les robe nada; dentro, el centro es más ancho (anchura elegida por Jorge de oído en el barrido de Platero). Fundidos de unos 100 ms en los bordes. La puerta sale de los tramos que el usuario marca en el editor «Aislar solo». La detección automática solo propone un tramo cuando su confianza es alta: en Platero, el clasificador sobre la C de una primera pasada marcaba solista el 74 % del tema. Sin tramos marcados no hay pista central. Excepción: una entrada casi mono (una sola guitarra) se queda en C, sin puerta. Al aplicar el editor, las pistas se rehacen en segundo plano. Parámetros de partida dentro del tramo: centro 0,30 y suelo de coherencia 0,15, los mejores del barrido del 15/11/2026. Jorge no dio por buena ninguna anchura de oído: aislar el solo de verdad pide un modelo de solista frente a rítmica, pendiente para la Etapa 2.
- Límite medido el 15/11/2026: con máscaras de panorama, parte del solo sigue en L y R, y quedan restos de L en R y de R en L. ADRess (cancelación por azimut) se probó y se descartó: gana en T1 pero pierde en T2. La guía por notas de Basic Pitch quita 3,2 dB de solo de L y R en el banco con referencia, pero Jorge sigue oyendo el solo; queda en StemKit como opción (`centerNotes`), sin conectar.
- Corre en el proceso de la app, tras la separación y la medida de niveles, como el análisis. Proyectos ya separados: se hace al abrirlos si falta. Se rehace si cambia `stems/guitar.wav`.

### Clasificación rítmica o solista

- Basic Pitch con su modelo Core ML oficial, embebido en la app como BTC (lo valida `tf-ml` frente a la versión de Python). El envoltorio vive en TabKit, que lo reutiliza en la Fase 5.
- Se transcribe cada pista de guitarra propuesta. Por ventanas de un compás (pulso de la Fase 2) se mide la polifonía media, la fracción de tiempo con 3 notas o más, la densidad de notas y el registro. Acordes o power chords repetidos = rítmica; línea de notas sueltas = solista; sin notas = sin guitarra.
- Solista es solo un solo de verdad. Arpegios, arreglos y adornos cortos de una guitarra de acompañamiento cuentan como rítmica: mismo tono en RF5 y sin cambio de plano en RF9 (Jorge, 15/11/2026). Por eso la clasificación usa también el contexto de la pista: una pista que calla casi todo el tema y entra con una línea melódica es un solo; una que suena todo el tema con notas sueltas es acompañamiento, es decir, rítmica.
- Banco de referencia, «El roce de tu cuerpo» (Platero y Tú), según Jorge: L rítmica; R acompañamiento (arpegios, arreglos, adornos), rítmica para la app; C el solo de mitad de canción.
- Ventanas iguales seguidas se unen en pasajes de 2 compases como mínimo. Cada pasaje lleva su papel y una confianza (margen de la puntuación).
- Lo detectado va a la caché de análisis (`cache/`, regenerable). Las correcciones a mano van en `project.json` y sobreviven a un nuevo análisis, como los overrides de acordes.

### Interfaz

- Pantalla Backing (boceto `docs/design/Backing.dc.html`): si hay guitarras separadas, el canal «Guitarras» del mezclador se sustituye por un canal por guitarra propuesta, con volumen, silencio y solo. Nombre por defecto «Guitarra izq.», «Guitarra centro» y «Guitarra der.», editable en el canal (p. ej. Robe y Uoho). Insignia de confianza en el canal.
- Línea de tiempo: un carril por guitarra bajo el de secciones, con sus pasajes coloreados por papel y la confianza en la opacidad. A mano: cambiar el papel, mover los bordes (imán al pulso), partir y unir pasajes.
- Si una pista tiene confianza baja, el aviso de la spec: «Cuando dos guitarras tocan lo mismo puede quedar algo de una en la otra pista».
- **Descartado (ADR-014): el editor «Aislar solo» y los carriles de pasajes; mandan las cajas de secciones.** Editor «Aislar solo» (pedido por Jorge el 15/11/2026, entra en esta fase). Se abre desde un pasaje de solo del carril de C, o arrastrando un tramo nuevo. Tiene dos vistas del tramo, con un interruptor, que editan la misma selección:
  - Espectrograma (tiempo × frecuencia): se arrastra la franja de frecuencias del solo.
  - Mapa de panorama × frecuencia, donde cada guitarra se ve como una mancha: se dibuja un rectángulo, que fija el rango de panorama y la misma franja de frecuencias.
  - Escucha en bucle de C, L y R mientras se ajusta, y botones «Restablecer» y «Aplicar».
  La selección (tramo, franja de frecuencias y rango de panorama) se guarda en `project.json` por tramo de solo y sustituye a la puerta automática en ese tramo. Las pistas siguen sumando la pista de guitarras. Lo que queda fuera de la selección, dentro del tramo, vuelve a L y R por canal.

### Datos

- Cambios aditivos en Store, sin subir `schemaVersion` (la Fase 3 también toca Store; así no chocan): `Guitar` se rellena con `side` (`L`, `C` o `R`) y el fichero de su pista; pasajes corregidos por guitarra; mezcla por guitarra (`StemMix` admite una guitarra además de un `StemKind`). Un proyecto v2 sin guitarras se lee igual que hoy.
- Protocolo nuevo en Store (`GuitarSplitting`, o como encaje con `StudyAnalyzing`) que implementa la app, para que la cola de la biblioteca haga separación → niveles → panorama → análisis.

### Código

| Paquete | Qué | Agente |
|---|---|---|
| `Probes/P4-modelos/guitar_models/` | Prueba de modelos de guitarra | `tf-ml` |
| ModelKit + recurso de la app | Basic Pitch Core ML embebido, validado frente a Python | `tf-ml` |
| StemKit | `PanSplitter` (máscaras, pistas, vacías, confianza) y sus tests | `tf-engineer` |
| TabKit | Envoltorio de Basic Pitch y `PassageClassifier`, con sus tests | `tf-engineer` |
| Store | Modelo de datos aditivo, protocolo y paso en la cola | `tf-implementer` |
| App | Canales por guitarra, carriles de pasajes, nombres y confianza | `tf-implementer` |

### Pruebas

- `PanSplitter`: tres señales sintéticas paneadas a izquierda, centro y derecha salen en su pista con diafonía < −20 dB; la suma de las pistas reproduce la entrada (error < 1e-5); una entrada mono deja solo el centro y descarta izquierda y derecha. Con 12 s de T1 se informa la diafonía frente a `guitar_parts/` (medida, sin umbral).
- Basic Pitch: notas del Core ML frente a la referencia de Python en un fixture (test pesado con `TF_MODEL_TESTS=1`, bajo `guard.py`).
- `PassageClassifier`: listas de notas sintéticas (acordes → rítmica, línea → solista, vacío → sin guitarra), unión de ventanas y mínimo de 2 compases.
- Store: guitarras, pasajes corregidos y mezcla por guitarra se guardan y se leen; un proyecto v2 anterior se abre igual; las correcciones sobreviven a un nuevo análisis.
- Interfaz: capturas revisadas por el orquestador.

### Lo aprendido al cerrar la fase (16/11/2026, ADR-014)

- Modelo lead/rhythm adoptado: Mel-Band RoFormer anónimo (openrail) en Core ML FP16, `num_overlap` 2, `MaskModelContract.leadRhythm`. Con «Guitarras en L y R», Robe y Uoho salen en pistas distintas en 3 temas de Extremoduro (de oído).
- Los modelos dedicados de guitarra (Mega 53, 7,58 dB; becruily, 5,81 dB) no superan a BS-RoFormer SW (8,23 dB en T1). La puerta del centro y `PanSplitter` quedan sin uso; el solo se cuela algo en la rítmica y un modelo solista frente a rítmica mejor queda para la Etapa 2.
- Backing no lleva grabación ni A/B (canal «Tú», «Comparar en la mezcla», botón de grabar): el código de la Fase 3 se conserva para la Fase 6. Tampoco A/B por guitarra.
- La Etapa 2 sale de la UI: «Igualar tono», la pestaña «Pedalera y TONE3000» y los rigs en Biblioteca; «Tablatura y DI» pasa a «Tablatura».
- Secciones editables en Backing (popover, asas, ◀ ▶, Supr, colores `TF.sectionPalette`); el mezclador no muestra stems vacíos.

### Propuestas confirmadas por Jorge el 15/11/2026

1. Descartar también una pista que quede más de 24 dB por debajo de la pista de guitarras, aunque no llegue a «vacía»: sin esto, la de centro de un tema con dos guitarras abiertas sale casi siempre con restos.
2. Ventana de clasificación de un compás y pasajes de 2 compases como mínimo.
3. En el mezclador, las guitarras separadas sustituyen al canal «Guitarras»: no se muestran a la vez, para que no se sumen dos veces.
4. Los nombres por defecto «Guitarra izq.», «Guitarra centro» y «Guitarra der.».

### Estimación y condición de paso

De 3 a 5 horas, como en el plan; la prueba de modelos puede añadir 1 si un candidato pasa a Core ML.

Condición de paso: en 3 temas de Extremoduro elegidos por Jorge, Robe y Uoho quedan en pistas distintas, juzgado de oído por Jorge en la app.


## Grabación con vídeo (mini-spec de la Fase 6)

Grabar tomas con cámara y la señal procesada sobre el backing, por partes y con varias tomas por parte, alineadas con el tema (RF8, parte de RF9). Va en paralelo con la Fase 5, en la rama `fase-6` (worktree aparte, desde `fase-4`). Se apoya en el audio de la Fase 3 (`AudioSession`, `TakeRecorder`, `TakeAligner`) y en las guitarras y secciones de la Fase 4.

Decidido por Jorge el 16/11/2026 (cambia RF8 y dos casillas del plan; va en un ADR nuevo al cerrar):

- **Sin calibración automática de la cámara.** Ni destello ni palmada: al terminar cada toma, un ajuste de desfase a mano con la vista previa. Ese valor queda como desfase por defecto de esa cámara para las tomas siguientes.
- **Sin micro.** Solo se graba la guitarra procesada (como en la Fase 3). Sin DI (ADR-012).
- **El backing son los stems con su mezcla**, configurable como en Backing (mezclador con volumen, silencio y solo por stem y por guitarra). No se graba: se reproduce desde los stems, que ya están alineados con el tema.
- **Punch-in sobre un tramo marcado**, que sustituye audio y vídeo del tramo.
- **Cada toma graba desde la sección elegida hasta que se pulsa parar** o acaba el tema.

### Cámara y sincronía

- Cámaras: todas las de vídeo del sistema (webcam USB, cámara integrada, iPhone por Continuity Camera), con sus formatos (resolución y fps). Por defecto, la de Ajustes; si no está conectada, se avisa y se puede grabar sin vídeo.
- Reloj común: la captura de vídeo entrega cada fotograma con su marca en el reloj de host; el audio de la Fase 3 sabe qué instante de host corresponde a cada muestra de salida y el ancla del reproductor, qué posición del tema corresponde a cada muestra. Con eso, cada fotograma se sitúa en tiempo del tema. El fichero de vídeo se escribe con esa marca (tiempo del tema), sin aplicar el desfase manual.
- Desfase manual (`videoOffset`, en segundos, positivo = la imagen llega tarde): se guarda en la toma y se aplica al reproducir y en el montaje, sin recodificar. Valor inicial de cada toma: el desfase por defecto de la cámara (0 si no hay).
- Fichero: `takes/<id>/video.mov`, HEVC, solo vídeo, con la resolución y los fps elegidos. Si la cámara no da el formato pedido, el más cercano, y la toma guarda el real.

### Partes y tomas

- **Parte:** nombre, qué guitarra sustituye (una de las pistas de la Fase 4 —rítmica, izq., der., solista— o ninguna, para una parte añadida), si es solista (marcado por defecto cuando sustituye a la solista; el montaje de la Fase 7 la enseña solo en los solos), sus tomas y su mejor toma.
- Propuesta inicial: una parte por pista de guitarra del proyecto, con su nombre del mezclador. «Añadir parte» pide nombre y qué guitarra sustituye.
- Al grabar una parte suena el backing con la mezcla de Grabar, con la guitarra de esa parte silenciada, más la mejor toma de cada una de las otras partes («tus tomas anteriores»), cada una como canal «Tú · nombre de la parte» del mezclador.
- Mejor toma: la última grabada hasta que se elige otra. Una toma se puede borrar (con confirmación; borra su carpeta).
- La mezcla de Grabar se guarda en el proyecto, aparte de la de Backing; la primera vez se copia de Backing.

### Grabar una toma

- Reglas de la Fase 3: dispositivo conectado, `guitarIn` asignado, velocidad 100 % y sin bucle; si no, el botón se desactiva con el motivo. Sin calibración de latencia se graba, se marca y se avisa.
- Inicio: selector «Empezar en» con las secciones (por defecto el principio; en una parte solista, el primer solo).
- Cuenta de 1 compás (activada por defecto) con clics del metrónomo y número grande sobre la vista previa; después arranca el backing en el inicio menos el margen (2 compases por defecto; 1 compás o sin margen) y se graba audio y vídeo. Compases del pulso de la Fase 2; sin pulso, a 120 BPM y 4/4.
- Fin: al pulsar parar o al acabar el tema. La toma se guarda entera (incluido el margen) y se alinea como en la Fase 3.
- Al parar se abre la hoja «Ajustar desfase»: vista previa del vídeo con la guitarra grabada, desfase en ms (±500 ms) con botones de ±1 fotograma y ±1 ms, «Guardar como desfase por defecto de esta cámara» (marcado) y los botones «Guardar toma» y «Descartar toma». El desfase se puede volver a ajustar después desde la toma.

### Punch-in

- Con «Punch-in» activado sobre una toma, se marcan entrada y salida en la línea de tiempo (imán al compás, ⌥ libre).
- Arranca en la entrada menos el margen, con cuenta si está activada; hasta la entrada suena la toma vieja y desde la entrada se silencia (te oyes por la monitorización del aparato). Se para solo 0,5 s después de la salida.
- Audio: la toma queda aplanada en `takes/<id>/processed.wav`, con fundidos cruzados de 10 ms en la entrada y la salida; la original se guarda en `takes/<id>/base/processed.wav` y cada punch en `takes/<id>/punch-<n>/`. Vídeo: no se recodifica; la toma guarda la lista de punches (tramo, ficheros y su desfase) y la vista previa y el montaje los componen.
- Varios punches en la misma toma: el último manda en su tramo.

### Interfaz

- **Pantalla Grabar** (boceto `docs/design/Record.dc.html`), en la barra lateral entre Backing y Montaje: vista previa de la cámara con «REC · Toma N · nombre de la parte», formato real y la cuenta; barra de grabación (Grabar/Parar, tiempo, «Empezar en», «Cuenta de 1 compás», «Margen», «Punch-in», y a la derecha el desfase por defecto de la cámara); mezclador como el de Backing en lugar del bloque «Pistas de audio», con el medidor de la entrada de guitarra; panel «Partes» con estado (Pendiente, Grabando, Hecha), botones de toma (la mejor en verde) y menú de toma (Marcar como mejor, Ajustar desfase, Punch-in, Borrar). Sin la línea del rig (Etapa 2) ni el recuadro de encuadre (Fase 7). «Ir al montaje», desactivado hasta la Fase 7.
- **Ajustes · Cámara y vídeo** (boceto `docs/design/Settings.dc.html`, pestaña existente): Cámara (por defecto, resolución, fps, con vista previa pequeña); Sincronía (desfase por defecto de la cámara elegida, editable, en lugar de «Calibrar retardo»); Exportación por defecto (formato HEVC o H.264 y resolución, -14 LUFS, rótulo sí/no, WAV de cada pista sí/no): solo se guarda, la usa la Fase 7.

### Datos (Store, aditivo, sin subir `schemaVersion`)

- `EquipmentProfile.video: VideoSettings?`: `cameraUID`, `resolution`, `fps`, `offsets` (desfase por defecto por cámara) y `export` (`VideoExportDefaults`).
- `Project.recording: RecordingState?`: `parts: [RecordingPart]`, `mix` (como `StemMix` de Backing), `startSectionID`, `countIn`, `preRollBars`.
- `RecordingPart`: `id`, `name`, `replaces: GuitarRole?`, `isLead`, `takeIDs`, `bestTakeID`.
- `Take` gana campos opcionales: `partID`, `videoFile`, `videoOffset`, `videoFormat` (cámara, ancho, alto, fps reales), `punches: [TakePunch]` y `baseProcessedFile`. `TakePunch`: `start`, `end` (tiempo del tema), `processedFile`, `videoFile`, `videoOffset`.
- `ProjectLayout`: `videoURL(takeId:)`, `baseProcessedURL(takeId:)`, `punchDirectory(takeId:n:)`.
- Esta fase va en paralelo con la Fase 5, que también toca Store: los tipos nuevos van en ficheros nuevos y los cambios en `Models.swift`, `Files.swift` y `Library.swift` se limitan a añadir campos y métodos.

### Código

| Pieza | Paquete | Agente |
|---|---|---|
| `CameraDevice`, `CameraProviding` (real y simulada), `CameraCapture` (real con AVCaptureSession y simulada con retardo, jitter y fotogramas perdidos), `VideoTakeWriter` (AVAssetWriter HEVC con marcas en tiempo del tema), `HostTimeMap` (host ↔ tema), `TakePreview` (composición de vídeo + toma procesada con desfase y punches), `tf-video` (desarrollo: `cameras`, `record`, `sync`) | VideoKit | `tf-engineer` |
| Instante de host de cada muestra y del ancla (lo que necesita `HostTimeMap`); varias pistas de toma en `StudyPlayer` (las mejores de las otras partes); silencio con fundido de la toma vieja en la entrada del punch; aplanado del punch con fundidos de 10 ms | AudioKit | `tf-engineer` (mismo agente que VideoKit: comparten tiempos y la caché de `swift build`) |
| `VideoSettings`, `RecordingState`, `RecordingPart`, campos de `Take`, `TakePunch`, rutas, `Library.saveRecording`, borrar toma | Store | `tf-implementer` |
| Ajustes · Cámara y vídeo | App | `tf-implementer` |
| Pantalla Grabar, hoja «Ajustar desfase», flujo de grabación y punch-in, cableado en `AppModel` y barra lateral | App | `tf-implementer` |

Reparto: primera tanda en paralelo, VideoKit + AudioKit (`tf-engineer`) y Store (`tf-implementer`). Segunda, en serie para no pisarse el build de la app: Ajustes · Cámara y vídeo y luego la pantalla Grabar (`tf-implementer`). Después `tf-qa` y capturas revisadas por el orquestador.

### Pruebas

- Sin hardware (puerta de tests): cámara simulada con retardo conocido y jitter de ±2 ms, audio simulado de la Fase 3. Se graban 3 tomas de 60 s (una empezando a mitad de tema, otra con deriva de audio de 50 ppm); con el mismo desfase para las 3, cada fotograma cae en su tiempo del tema con error menor de medio fotograma, al principio y al final. Fotogramas perdidos no desplazan los siguientes.
- `HostTimeMap`: conversiones ida y vuelta exactas a 44,1 y 48 kHz y con cambio de ancla (seek).
- Punch: el aplanado conserva fuera del tramo la toma original muestra a muestra y deja fundidos de 10 ms; la composición de vídeo usa el punch dentro del tramo y la base fuera.
- Store: los campos nuevos se guardan y se leen; un proyecto o un perfil anteriores se abren igual; borrar una toma la quita de su parte y reasigna la mejor.
- Interfaz: capturas revisadas por el orquestador (Grabar con cámara simulada, hoja de desfase, Ajustes · Cámara y vídeo).

### Medidas con hardware (las hace Jorge)

1. `tf-video cameras`: cámaras y formatos que ve la app (webcam e iPhone).
2. En la app, con la Flex Prime y el iPhone: 3 tomas de una parte. En cada una, golpe seco en las cuerdas al principio y al final; ajustar el desfase en la primera y comprobar que en las otras dos, con el mismo desfase, golpe e imagen coinciden fotograma a fotograma.
3. Una parte con punch-in: el tramo sustituido cuadra en audio y vídeo.

### Lo aprendido al cerrar la fase (16/11/2026, ADR-015)

- Con el iPhone (1080p30) y la Flex Prime, `tf-video sync` midió 1754 fotogramas sin pérdidas, jitter RMS 0,93 ms (máx. 15,06 ms), audio +29 ppm frente al host y cámara − audio −83 ppm (cadencia del iPhone, no afecta). El retardo de entrega va de 43 a 254 ms (mediana 57).
- Por ese retardo la cámara arranca al abrir Grabar (unos 1,5 s hasta el primer fotograma) y al parar se espera unos 0,5 s a los últimos fotogramas.
- La cuenta suena en un segundo `StudyPlayer`, para no tocar el que reproduce el backing.
- Las cámaras se re-sondean cada 2 s en Grabar: el proveedor admite un solo manejador de cambios.
- Mezclador compacto por defecto y vídeo lo más grande, sin scroll en ventanas 16:9.
- Pendientes: suavizar las marcas de la cámara (solo si hace falta), desfase propio por punch desde la hoja y ganancia igualada en los canales «Tú · parte».

### Retoques al cerrar la Fase 7 (18/11/2026, ADR-018)

- **Parada automática:** la grabación se para sola al acabar la sección elegida más el margen (`BarTiming.sectionStop`).
- **Tomas a otra frecuencia:** si una toma no está a la frecuencia del proyecto, se remuestrea al cargar (`TakeResampling`); `Library.migrate` no las reconvierte y la caché remuestreada va al temporal, sin limpiarse.
- **Botón «Rotar»** en la vista previa de Grabar (desactivado mientras se graba): 0°, 90°, 180° y 270° por cámara, heredado por cada toma nueva; ver «Encuadre» en la mini-spec de la Fase 7. También en Ajustes de vídeo, sobre la vista previa en directo.
- `Tools/test.sh App` compila solo la app (unos 5 s en incremental) y no escribe `Temp/last-run.txt`.

### Estimación y condición de paso

De 4 a 6 horas, como en el plan: quitar la calibración y el micro resta lo que añaden el punch-in con vídeo y el mezclador en Grabar.

Condición de paso: 3 tomas grabadas y alineadas a menos de 1 fotograma con un mismo desfase, comprobado por Jorge en la app; y el test de la puerta con la cámara simulada.
## Tablatura (mini-spec de la Fase 5)

Parte de RF2 (tablatura con cursor, editable) y RF11 (bajo y batería, un único Guitar Pro). Rama `fase-5` desde `fase-4`, en un worktree: la Fase 6 va en paralelo y toca App y Store, así que esta fase añade ficheros nuevos y toca lo compartido lo mínimo. El DI guiado (grabar y validar la toma) es de la Fase 8a: la pantalla no lleva el panel «Entrada» ni «Última toma» del boceto `Tab.dc.html`, ni «Grabar toma».

### Decisiones de Jorge (16/11/2026)

1. **Cuándo:** se transcribe al abrir Tablatura por primera vez, con progreso, y se guarda. Si cambian las guitarras (L y R, tramos de solo), se rehace el pase de las pistas afectadas.
2. **Una entrada por pista:** cada pista de guitarra que exista según `GuitarSettings` (una pista, o L y R, más la solista si hay tramos de solo) es una pista de la tablatura y del Guitar Pro, con el nombre de `Guitar.name`; más bajo y batería. Los stems vacíos no generan pista.
3. **Sonido:** por defecto suenan los stems reales con el reproductor de estudio (velocidad, bucle, mezcla) y el cursor sigue al audio. Un conmutador por pista, «Oír transcripción», sustituye el stem de esa pista por la transcripción sintetizada.
4. **Edición completa básica:** guitarras y bajo: cambiar traste, pasar la nota a otra cuerda con la misma altura, borrar, añadir en la posición del cursor y cambiar duración. Batería: poner o quitar golpe por pieza en la rejilla. Deshacer y rehacer.
5. **Afinación por pista:** estándar por defecto (EADGBE; bajo EADG), con selector por pista: medio tono abajo, un tono abajo y drop D. Cambiarla reasigna cuerdas y trastes conservando las alturas, y va al Guitar Pro.

### Recorrido

1. Jorge abre un tema separado y entra en Tablatura. Si no hay transcripción o alguna pista está desfasada, se transcriben esas pistas con una barra de progreso por pista; las demás se cargan al momento.
2. Pestañas de pista (p. ej. «Guitarra izq.», «Guitarra der.», «Solo», «Bajo», «Batería»), cada una con su afinación (guitarras y bajo) y su «Oír transcripción».
3. La tablatura (alphaTab) muestra la pista elegida; el cursor sigue a la reproducción. Clic en una nota la selecciona y lleva el cursor; «Editar notas» activa el teclado de edición.
4. Barra de transporte como en Backing: volver al inicio, reproducir, velocidad 50–200 %, metrónomo y bucle (sección o compases seleccionados).
5. «Exportar a Guitar Pro» guarda un único `.gp` con todas las pistas (diálogo de guardar; nombre por defecto «Artista - Título.gp»).

### Transcripción

- **Guitarras:** `BasicPitchTranscriber` (TabKit, Fase 4) sobre el WAV de cada pista de guitarra. Notas polifónicas.
- **Bajo:** Basic Pitch sobre `stems/bass.wav`, reducido a una nota a la vez (la de más amplitud en cada ataque), 4 cuerdas.
- **Batería:** ADTOF Core ML FP32, `.cpuOnly`, con el contrato de `docs/probes/P4-modelos.md` (preproceso, entrada `[1, T, 84, 1]`, salida `[1, T, 5]`, umbrales y picos). Cinco piezas: bombo 35, caja 38, tom 47, charles 42, platos 49 (MIDI de percusión GM). Modelo embebido en la app como BTC y Basic Pitch (1,8 MB; licencia CC BY-NC-SA, uso personal, no se redistribuye la app).
- **Rejilla:** compases y pulsos de `BeatGrid` (StudyKit). Cada pulso se divide en semicorcheas o en tresillos de corchea, lo que menos error dé con los ataques de ese pulso. Ataques al punto más cercano; la duración llega hasta el final de la nota o el siguiente ataque de la misma pista, cuantizada; huecos como silencios. Todos los tempos escritos son enteros (BPM de negra): el tempo base de un tramo es la mediana del tempo real de sus 4 primeros compases (o los que queden), redondeada al entero más cercano. Un cambio de tempo por compás cuando la duración del compás se aleja más de un 2 % del tempo real vigente, o cuando el inicio escrito de un compás (sumando duraciones a los tempos enteros) se separa del real más de 20 ms (`maxWrittenDrift`): ese compás lleva el entero que más reduce la deriva a su final y el siguiente vuelve al tempo base entero. A tempo real no entero constante hay correcciones periódicas (dos cambios cada pocos compases); a tempo real entero constante, ninguna. Así el Guitar Pro no se desincroniza del tema; los tiempos de `TabScore` (cursor, sintetizado) son siempre los reales.
- **Cuerdas y trastes:** Viterbi sobre la secuencia de acordes y notas: cada nota en una cuerda distinta, trastes 0–24, coste por apertura de la mano dentro del acorde (más de 4 trastes muy penalizado), por salto de posición entre acordes y una preferencia leve por trastes bajos y cuerdas al aire. Acordes de más notas que cuerdas: se quitan las de menos amplitud. Notas fuera del registro de la afinación: se suben o bajan una octava y se cuentan en un aviso.
- **Desfase por pista:** cada pista guarda una huella de su origen (ruta, tamaño y fecha del WAV, versión del modelo y de los parámetros). Si no coincide al abrir, esa pista se rehace y sus ediciones se pierden; un aviso dice qué pistas se rehicieron. La afinación no forma parte de la huella: cambiarla reasigna cuerdas sin transcribir de nuevo.

### Partitura, sonido y exportación

- **Modelo propio en TabKit (`TabScore`, Codable):** pistas (nombre, tipo guitarra / bajo / batería, afinación), compases (inicio en segundos, compás, tempo), pulsos con su subdivisión, y notas (altura MIDI, cuerda, inicio y duración en la rejilla) o golpes (pieza). Las operaciones de edición y el deshacer viven aquí y se prueban sin interfaz. Se guarda en `tab/score.json` dentro de la carpeta del proyecto (no es caché: lleva las ediciones).
- **alphaTab** (versión fijada, embebida en la app, sin CDN; MPL-2.0) dentro de un `WKWebView`: renderiza a partir de `TabScore` y exporta con su exportador de Guitar Pro 7. La forma de pasarle la partitura (alphaTex, MusicXML o construir el `Score` en JS) la decide la prueba inicial.
- **Riesgo conocido:** las baterías que exporta alphaTab no suenan en Guitar Pro 8 con RSE. Se comprueba al principio con un `.gp` de prueba (guitarra, bajo y batería) que Jorge abre en Guitar Pro; si falla, se busca el ajuste del instrumento de percusión que lo arregle, y si no lo hay, se acepta que la batería se lea pero no suene con RSE.
- **Transcripción sintetizada:** se renderiza fuera de tiempo real a un WAV por pista (`AVAudioUnitSampler` con el soundfont GM de alphaTab; batería en el banco de percusión) en `cache/tab/`, y entra al reproductor de estudio como una pista más; «Oír transcripción» silencia el stem y activa la sintetizada, así sigue velocidad, bucle y sincronía sin un segundo reloj. Se vuelve a renderizar tras editar (con rebote).
- **Cursor:** la posición del reproductor se convierte a compás y pulso con los tiempos de `TabScore` y se envía a alphaTab.

### Datos

- Store, solo aditivo y sin subir `schemaVersion` (la Fase 6 también toca Store): rutas en `ProjectLayout` (`tab/score.json`, `cache/tab/`). `tab/` no entra en la limpieza; `cache/tab/` sí. `TabScore` es de TabKit; Store no depende de TabKit y la app hace de puente.

### Código

| Parte | Qué | Agente |
|---|---|---|
| 0. Prueba de alphaTab | Embeber alphaTab y su soundfont en la app; desde una partitura de prueba (guitarra, bajo, batería) renderizar y exportar un `.gp` a `Temp/p5/`, que Jorge abre en Guitar Pro; elegir el formato de entrada | `tf-implementer` |
| 1. ADTOF en la app | `.mlpackage` FP32 con GRU nativa embebido (zip en `App/Resources/Models/`), entrada en `ModelCatalog`, fixture con activaciones y golpes de referencia de Python | `tf-ml` |
| 2. TabKit: partitura | `TabScore`, rejilla y cuantización, cuerdas y trastes con afinaciones, reducción del bajo, edición y deshacer, conversión tiempo ↔ posición, huellas | `tf-engineer` |
| 3. TabKit: batería | `DrumTranscriber`: STFT y banco logarítmico con Accelerate, Core ML, picos; paridad con el fixture | `tf-engineer` |
| 4. Sintetizado | Render fuera de tiempo real de una pista de `TabScore` a WAV con el soundfont, alineado con el tema | `tf-engineer` |
| 5. App | Pantalla Tablatura, puente con alphaTab, orquestación de la transcripción por pista, cursor, edición, «Oír transcripción», exportación; rutas en Store | `tf-implementer` |

Orden: 0, 1 y 2 en paralelo; 3 tras 1; 4 tras 2; 5 tras 0 y 2, integrando 3 y 4.

### Pruebas

- Cuantización: ataques sintéticos sobre una rejilla con tempo variable caen en su subdivisión; un pulso con ataques en tresillo elige tresillos; los tiempos de compás de `TabScore` reproducen los del `BeatGrid` (error < 1 ms).
- Cuerdas y trastes: escalas y acordes abiertos conocidos (Mi, La, Re, power chords) salen en su digitación habitual; ninguna nota comparte cuerda en un acorde; cambiar de afinación conserva las alturas; notas fuera de registro se cuentan.
- Bajo: entrada polifónica sale con una nota por ataque.
- Edición: cada operación y su deshacer devuelve la partitura idéntica; pasar de cuerda conserva la altura y se niega si el traste sale de 0–24.
- Batería: activaciones y golpes de `DrumTranscriber` frente al fixture de Python (diferencia de activación < 1e-4; golpes a ±10 ms); pesado con `TF_MODEL_TESTS=1` bajo `guard.py` si hace falta el modelo.
- Huellas: cambiar el WAV de una pista marca solo esa pista como desfasada.
- Sintetizado: un golpe en el pulso N suena en el tiempo del pulso N del tema (error < 1 ms).
- Exportación: el `.gp` se genera y alphaTab lo vuelve a leer con el mismo número de pistas, compases y notas. La apertura en Guitar Pro la comprueba Jorge.
- Interfaz: capturas revisadas por el orquestador.

### Estimación y condición de paso

De 6 a 10 horas, como en el plan; lo incierto es la calidad de la transcripción de guitarras distorsionadas y la batería en Guitar Pro.

Condición de paso: tablatura de un tema con guitarras, bajo y batería exportada y abierta en Guitar Pro (Jorge).

### Lo aprendido al cerrar la fase (16/11/2026, ADR-016)

- alphaTab 1.9.0 exporta la batería a Guitar Pro 7 y suena con RSE en Guitar Pro 8 sin parche (incluye el arreglo #2467/#2468); `patchDrumGpif` queda sin uso. La partitura se pasa como JSON propio v1 y el `Score` se construye en JS (`tf-bridge.js`).
- ADTOF FP32 con GRU nativa y `.cpuOnly` da paridad exacta con Python (1117/1117 golpes en T1); se trocea con 30 s de contexto.
- Con tempos escritos enteros, la deriva máxima del `.gp` es de unos 50 ms; cursor y sintetizado usan los tiempos reales. El sintetizado queda con precisión < 0,07 ms.
- Calidad según Jorge: bajo muy bueno; batería buena, pero ADTOF etiqueta mucho charles (probablemente abierto) como crash o ride; guitarras pésimas (en El roce, 256 notas fuera de registro movidas de octava y 72 quitadas). Pasa a la Fase 5b.
- Los compases irregulares (3/4, 2/4) en intros vienen del `BeatGrid`.
- No hay modelo publicado probado en guitarra eléctrica distorsionada ni en stems. Candidatos: Guitab (`danmor/guitab`, 6,2 M, CC BY-NC-SA, fácil a Core ML) y MuScriptor small (autorregresivo, CC BY-NC, difícil a Core ML); plan B, TabCNN con SynthTab y reentreno.
- Sin probar a fondo por Jorge: teclado de edición y «Oír transcripción» con reproducción real; calidad del soundfont por valorar.

## Calidad de la tablatura (mini-spec de la Fase 5b)

Rama `fase-5b` desde `fase-5`. Condición de paso aprobada por Jorge el 16/11/2026: tablatura de 3 temas reconocible en la app (rítmicas, solos y batería con los platos corregidos), juzgado por Jorge. El primer tema, «El roce de tu cuerpo», es la puerta: los otros dos solo se prueban si pasa.

### Lo medido (16/11/2026, solo El roce)

- **Referencia:** la tablatura de Songsterr del tema, alineada al audio (`Probes/P5b-guitarra/eval_reference.py`; datos en `Temp/`, sin versionar). Basic Pitch sobre el bajo da F1 0,46 con ella, que comprueba la alineación.
- **Transcripción automática de guitarra:** F1 por nota (altura exacta, ataque ±50 ms) de 0,21 a 0,40 en el mejor caso. Guitab E25 gana a Basic Pitch en todos los stems (0,35–0,39 frente a 0,27–0,30); acordes BTC con los ataques de Guitab ganan en lo rasgueado y dan 0,00 en los riffs; el híbrido (acordes donde se rasguea, Guitab en los riffs) no generaliza a la otra guitarra; la limpieza del solo sube 0,21 → 0,24. Jorge: «ninguna termina de parecerse». MuScriptor small no se probó (pesos con licencia que hay que aceptar a mano).
- **Conclusión:** la transcripción automática no llega a reconocible con guitarra distorsionada separada. La tablatura de Songsterr pasa a ser la fuente por defecto y la automática queda de respaldo.

### Decisiones de Jorge (16/11/2026)

1. **Songsterr por defecto.** Uso personal en local, el mismo compromiso que yt-dlp (ADR-008). Ningún dato de Songsterr se versiona ni se redistribuye.
2. **Búsqueda automática con confirmación:** al abrir Tablatura se busca por artista y título; se propone el resultado con sus pistas y Jorge confirma o elige otro de la lista. También se puede pegar un enlace.
3. **Emparejamiento de pistas propuesto y editable:** la app propone qué pista de Songsterr va con cada stem (guitarra izq., der., solista, bajo, batería) por parecido con el audio, y se puede cambiar en una lista.
4. **Automática solo de respaldo:** con tablatura de Songsterr no se transcribe. La automática entra en temas sin tablatura y en stems sin pareja.
5. **Pistas de Songsterr sin stem** (p. ej. una tercera guitarra o teclados): entran en la tablatura y en el `.gp` como pistas extra, que solo suenan con «Oír transcripción».
6. **Batería:** la de Songsterr si existe; la de ADTOF (con la corrección de platos) solo de respaldo.
7. **Afinación personalizada:** `TuningPreset` gana un caso «personalizada» para las afinaciones de Songsterr que no son ningún preset (Do estándar, 7 cuerdas), también en el selector de la app. Hecho.

Decisiones nuevas (17/11/2026, ADR-017):

8. **Elige Jorge, con vista previa.** Una sola búsqueda, resultados en el orden de Songsterr y vista previa funcional dentro de la app. Se quitó el ordenador de versiones por completitud: descargaba varias versiones y Songsterr rechaza el acceso automatizado (`ERR_ACCESS_POLICY`). Ningún agente ni test hace peticiones a Songsterr.
9. **Metrónomo y compases de Songsterr** (elegido de oído): pulsos anclados al audio, compás y primer tiempo de Songsterr, tempo escrito (si no cuadra ±15 % con lo medido, el medido). Los compases sueltos por diferencias de estructura son normales.
10. **Solista por secciones:** cada sección de solo se asigna a la pista de Songsterr que mejor suena.
11. **Adornos:** se representan, se dibujan y se exportan a `.gp` los de Songsterr; el aviso de «adorno no representado» queda en 0 en El roce y Tornado.

### Lo aprendido al cerrar la fase (17/11/2026, ADR-017)

- La URL de la página con pistas es `…/song-tab-s<id>`; `song-s<id>` da 404. Songsterr rechaza el acceso automatizado y varias descargas seguidas, por lo que la elección la hace Jorge.
- El desfase global necesita un rango ampliado por la diferencia de duración entre la tablatura y la grabación. El ajuste por bloques de 4 compases lleva una penalización por pulso para no cambiar de bloque sin motivo. La rejilla se pliega a doble o mitad de tempo, y se rellenan o quitan pulsos contra el periodo.
- Los solos se distinguen por altura exacta (`soloSalience`); en El roce, Solo 1 → Uoho con margen 0,72. El emparejamiento por croma sirve para las pistas rítmicas.
- Songsterr llama `upStroke` al rasgueo hacia abajo. alphaTab 1.9 lee `bendPoints[3]`, por lo que se duplica la cima del bend-release; el `.gp` admite 4 puntos como máximo.
- Suenan en «Oír transcripción»: palm mute, staccato, muteadas, ghost, acentos, bends, palanca y vibrato. No suenan aún: let ring, slides, ligados, armónicos, adornos y flam (Fase 5c).
- Respaldo: la puerta de silencio, el arreglo del port y el techo de registro MIDI 86 limpian Basic Pitch, pero la automática sigue sin ser reconocible con guitarra distorsionada.
- Voces de Songsterr: entran como pista `vocal` desde la Fase 5c (mini-spec «Interfaz de la tablatura»).
- Condición de paso cumplida con tres temas: «El roce de tu cuerpo», «Tornado Of Souls» y «Aquellas Cosas Que Solíamos Hacer». Jorge: «todo perfecto».
- Ramas atrasadas: el binario de `fase-5b` borró `recording`, `montage` y el vídeo de El roce al guardar `project.json`. Se prueba con copia aislada.

### Recorrido

1. Jorge abre Tablatura en un tema separado sin fuente elegida. La app busca en Songsterr con el artista y el título del proyecto (progreso «Buscando en Songsterr…»).
2. Hoja «Tablatura de Songsterr»: el primer resultado marcado, con artista, título y la lista de pistas (nombre, instrumento, afinación), más otros resultados y un campo para pegar un enlace. Botones «Usar esta», «Transcribir automáticamente» y «Cancelar».
3. Al usar una: se descargan sus pistas, se alinean con el audio y se propone el emparejamiento en una lista (stem → pista de Songsterr o «Transcripción automática»), con la confianza de cada pareja. «Aceptar» crea la tablatura.
4. Si la alineación encuentra diferencias de estructura (pulsos de más o de menos, repeticiones que faltan), un aviso dice en qué compases.
5. La pantalla sigue como en la Fase 5 (pestañas, cursor, edición, «Oír transcripción», exportación). Un menú «Fuente» por tema permite volver a buscar, cambiar el emparejamiento o pasar a automática.

### Alineación

Lo que funcionó en el prototipo (`eval_reference.py`), pasado a Swift: los compases y pulsos de la tablatura se colocan sobre los pulsos del `BeatGrid` con un desfase global en pulsos más un ajuste fino en ms, y se corrigen por bloques de 4 compases maximizando la energía espectral del stem en la altura de cada nota. La alineación por ataques y por croma (DTW) se probó y confunde desfases de 2 negras en el rasgueo periódico; no se usa. Las notas conservan cuerda, traste y afinación de Songsterr (sin Viterbi); los tiempos de `TabScore` son los reales del tema y el tempo escrito sigue la regla de la Fase 5.

### Respaldo automático (lo que entra en TabKit)

- **Arreglo del port de Basic Pitch:** una ventana con pico por debajo de −120 dBFS no pasa por el modelo (el `.mlpackage` convirtió `divide_no_nan` en una división normal y daba notas sobre silencio digital). Hecho.
- **Puerta de silencio** a −60 dBFS (`SilenceGate`), para cualquier transcriptor. Hecho.
- **Techo de registro** en MIDI 86 para guitarras (traste 22 de la primera cuerda): quita los armónicos sobreagudos de Basic Pitch.
- **Platos de ADTOF:** series de 4 o más golpes de plato a ≤ 0,5 s pasan a charles abierto (46), salvo el primero si cae con bombo (`DrumCymbalSeries`). Hecho; Jorge lo oye mejor en El roce.
- Guitab a Core ML queda fuera: gana poco y la CQT en Swift es cara. Se reconsidera si la prueba de quitar la distorsión (RemFX) mejora mucho.

### Errores

| Caso | Qué pasa |
|---|---|
| Sin resultados | «No está en Songsterr» y se ofrece la transcripción automática |
| Bloqueo (429) o sin red | Aviso con «Reintentar»; no se insiste en bucle. Se puede seguir con la automática |
| Formato de página o de pista desconocido | Aviso «Songsterr ha cambiado su formato» y automática; la tablatura ya importada no se pierde |
| Pista con algo que `TabScore` no representa (bends, slides, armónicos) | Se importa la nota sin el adorno y se cuenta en un aviso |

### Datos

- Store, solo aditivo: en el proyecto, la fuente elegida (Songsterr con `songId` y `revisionId`, o automática) y el emparejamiento stem → pista. Las pistas crudas de Songsterr van a `cache/songsterr/` (entra en la limpieza; se pueden volver a bajar).
- Huella de las pistas importadas: `songId`, `revisionId` y versión del conversor. Las ediciones se guardan en `tab/score.json` como en la Fase 5.

### Código

| Parte | Qué | Agente |
|---|---|---|
| 1. Lector de Songsterr | En la app, un `WKWebView` oculto carga la búsqueda y la página del tema como un navegador; SourceKit extrae el estado de la página (resultados, pistas, revisión) y las URL de las pistas; descarga de las pistas. Pruebas con páginas de muestra hechas a mano, sin datos reales | `tf-implementer` |
| 2. Conversor | Pista de Songsterr → notas de `TabScore` (cuerda, traste, ritmo, ligaduras, tempo y compases, afinación; batería a piezas GM). Guía: el conversor del proyecto `Metaphysics0/songsterr-downloader` (MIT). Pruebas con pistas sintéticas | `tf-engineer` |
| 3. Alineación y emparejamiento | Port de `eval_reference.py`: colocación sobre el `BeatGrid`, ajuste por bloques, aviso de diferencias de estructura; propuesta de pareja por croma | `tf-engineer` |
| 4. Respaldo | Techo de registro en TabKit (la puerta y los platos ya están) | `tf-engineer` |
| 5. App | Hoja de Songsterr, lista de emparejamiento, menú «Fuente», avisos; rutas y campos en Store | `tf-implementer` |

Orden: 1, 2 y 4 en paralelo; 3 tras 2; 5 tras 1 y 3.

### Estimación

De 8 a 12 horas. Lo incierto: que Songsterr cambie su página o bloquee el `WKWebView`, y las diferencias de estructura entre la tablatura y la grabación.

## Interfaz de la tablatura (mini-spec de la Fase 5c)

Rama `fase-5c` desde `fase-5b`. Pendientes (a)–(d) del ADR-017 más lo que Jorge pidió el 17/11/2026 al ver la pantalla completa.

### Condición de paso (aprobada por Jorge el 17/11/2026)

En los tres temas de la 5b, juzgado por Jorge: las voces de Songsterr salen como voz en pentagrama y no hay pistas sin nombre; en «Oír transcripción» suenan let ring, slides, ligados, armónicos, notas de adorno y flams; con el teclado se ponen y se quitan P.M., bend, vibrato y slide, y el cambio se guarda; cada pista tiene mute y solo; todas las pistas pasan a stem o a transcripción de una vez; y una selección de la tablatura se reproduce en bucle. El roce es la puerta.

### Decisiones

1. **Teclas de Guitar Pro 8** (decisión de Jorge), tabla abajo.
2. **Mute y solo por pista** en la lista de pistas de Tablatura (hoy solo selecciona). Actúan sobre lo que suena de esa pista: el stem o, con «Oír transcripción», su síntesis; las pistas extra, sobre su síntesis. Comparten estado con la mezcla de Backing (`BackingController`), la misma regla de atenuación (`muted || (anySolo && !solo)`). Lo que no tiene pista en la tablatura (voz grabada, otros) sigue sonando salvo que haya un solo.
2b. **Todas a stem o a transcripción** (Jorge, 17/11/2026): sobre la lista de pistas, un selector «Stems / Transcripción» pone «Oír transcripción» en todas las pistas de una vez (las que no tienen stem suenan siempre con su síntesis). Si después se cambia una pista suelta, el selector queda en estado mixto. Las síntesis que falten se pintan en segundo plano, con progreso. Al abrir, las pistas extra (sin stem) quedan en «Oír transcripción» y el selector sale en «Stems».
3. **Bucle por selección:** clic en un pulso y ⇧clic en otro (o arrastrar) selecciona un tramo de pulsos, resaltado en la partitura; el bucle A-B de `StudyPlayer` pasa a ese tramo (del inicio del primer pulso al final del último) y la reproducción salta a su inicio. Funciona en lectura y en edición; en edición, ⇧← y ⇧→ amplían la selección. El menú de bucle muestra «Selección»; Esc o «Sin bucle» lo quitan. El clic simple sigue como hoy.
4. **Voces de Songsterr** (cambiada por Jorge el 18/11/2026): las pistas de voz pasan a un tipo de pista `vocal`: solo pentagrama, sin cuerdas ni trastes (altura MIDI), se exportan al `.gp` como pista sin tablatura. Van vinculadas al stem `vocals` por tipo de pista, no por el plan de emparejamiento: con «Stems» suena el stem y calla la síntesis; con «Transcripción» la síntesis sustituye al stem; M/S actúan sobre el stem de voz. Varias vocales comparten el stem, que se sustituye mientras alguna esté en transcripción. Sin stem de voz, la vocal es extra. La lista de emparejamiento no muestra la vocal.
   - Detección: en las cachés de los tres temas ninguna voz trae GM 52–54 (Tornado trae 67 y Aquellas 66). Se detectan por nombre: vocal(s), voice(s), voz/voces, singer, choir, coro; el 52–54 queda como criterio adicional. El roce no tiene voces.
   - Los `score.json` antiguos tienen las voces como guitarra hasta que se reimporten.
5. **Nombre vacío → instrumento:** el nombre de Songsterr si existe; si no, el del instrumento («Batería», «Bajo», «Guitarra», «Voz»), con número si se repite. En la tablatura, en la lista de emparejamiento y en el `.gp`.
6. **Las ediciones con teclado** actúan sobre la nota seleccionada o sobre todas las del tramo seleccionado, conmutan (la misma tecla pone y quita), entran en deshacer, se guardan en `tab/score.json`, se dibujan, se exportan y vuelven a sintetizar la pista si «Oír transcripción» está activo.

### Teclas (modo edición)

| Tecla | Adorno | Notas |
|---|---|---|
| P | Palm mute | |
| I | Let ring | |
| H | Ligado (hammer-on / pull-off) | Con la nota siguiente de la misma cuerda |
| S | Slide | Cicla: legato a la siguiente → shift → entrada desde abajo → entrada desde arriba → salida abajo → salida arriba → ninguno |
| B | Bend | Cicla: 1 tono → ½ tono → bend-release → ninguno |
| V | Vibrato | |
| W | Vibrato de palanca | |
| X | Nota muteada | |
| O | Ghost | |
| ; / : | Acento / acento fuerte | |
| ! | Staccato | |
| Y / ⌥Y | Armónico natural / artificial | |
| G | Nota de adorno antes del pulso | Dos trastes por debajo, ligada; el traste se cambia con los dígitos |
| ) | Tapping | |
| L | Ligadura de duración | |
| ⇧D / ⇧U | Púa abajo / arriba | |
| F (batería) | Flam | Las teclas de golpe de batería (B C H T P) se quedan como están en pistas de batería; O y ; también valen ahí |

Dígitos, flechas, ⌫, +/−, ⌘Z y espacio, como en la Fase 5.

Comportamiento aprendido en la 5c:

- Con varias notas seleccionadas, si todas tienen el adorno se quita; si no, se pone. S y B ciclan desde el estado de la primera nota; un bend o slide fuera del ciclo pasa a ninguno.
- G seguido de dígitos cambia el traste de la nota de adorno (modo adorno hasta otra tecla o cambio de selección).
- L exige una nota anterior en la misma cuerda y a altura contigua (`TabTechniques.tieDestination`, `TabEditError.noTieOrigin`). El sintetizador prolonga la nota sin nuevo ataque y la ligada hereda del origen let ring, palm mute, vibrato y bend, como el conversor. Songsterr trae `tie` y el conversor ya funde la ligada en la nota de origen, así que suena bien, pero en la partitura una nota que cruza la barra se dibuja cortada (pendiente de la fase de arreglos, ADR-019).
- Reimportar desde «Cambiar emparejamiento…» hace una petición a Songsterr (la página del tema); las pistas salen de la caché.

### Sonido de los adornos (`TabSynthRenderer`)

- **Let ring:** la nota suena hasta la siguiente de la misma cuerda o el fin del tramo let ring, con tope de 4 s.
- **Slides:** legato, glisando con pitch bend en el último tramo de la primera nota y la segunda sin ataque nuevo; shift, igual con ataque; entrada y salida, glisando corto (unos 3 trastes) al empezar o al acabar. El rango de pitch bend se amplía por RPN a lo que pida el slide más largo, con tope de 12 semitonos.
- **Ligados:** la segunda nota empieza justo al acabar la primera y con menos velocidad (sin púa).
- **Armónicos:** altura del armónico (12 → +12, 7 → +19, 5 → +24…; los artificiales, la que traiga Songsterr) con programa de armónicos o el de la pista.
- **Notas de adorno:** unos 60 ms antes del pulso (o en el pulso), con su ligado o slide si lo tienen.
- **Flam:** golpe de adorno unos 30 ms antes, con menos velocidad.

### Datos

Solo aditivo. `TabTrackKind` gana `vocal`; las técnicas que falten en `TabTechniques` (acento fuerte, tipo de slide) se añaden como opcionales. La regla de copia aislada sigue: el binario de esta rama no abre `~/Music/ToneForge`.

### Código

| Parte | Qué | Agente |
|---|---|---|
| 1. Sonido de adornos | `TabSynthRenderer`: let ring, slides, ligados, armónicos, adornos y flam, con pruebas sobre los eventos | `tf-engineer` |
| 2. Mute/solo y bucle | App: M y S por pista en Tablatura sobre `BackingController`; selector «Stems / Transcripción» para todas las pistas; selección de tramo en `tf-bridge.js` (resaltado, ⇧clic, arrastre), mensaje a Swift y bucle A-B; «Selección» en el menú de bucle | `tf-implementer` |
| 3. Voces y nombres | TabKit: tipo `vocal` en conversor, colocación, plan de importación, `AlphaTabScore` (solo pentagrama), `.gp` y programa en el sintetizador; nombre vacío → instrumento | `tf-implementer` |
| 4. Teclado | TabKit: operaciones de conmutar adornos en `TabEditor` con pruebas; App: teclas de la tabla en `handleKey` y ⇧←/⇧→ | `tf-implementer` |

Orden: 1 y 2 en paralelo; 3 y 4 en paralelo tras 1 (3 toca el sintetizador) y 2 (4 usa la selección de tramo).

### Estimación

De 6 a 9 horas. Lo incierto: que el slide legato y el ligado suenen naturales con un soundfont GM, y el arrastre para seleccionar con alphaTab sin su reproductor.


## Montaje (mini-spec de la Fase 7)

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

### Qué entra en el montaje

- De cada parte de `Project.recording`, su mejor toma. Con vídeo: recuadro y audio. Sin vídeo: solo audio. Parte sin tomas: no entra.
- **Presencia de una parte:** el tramo del tema que cubre su toma (desde `songStart`, margen incluido, hasta su final). Si la parte es solista, ese tramo cortado con las secciones de solo (`Section.isSolo`); sin secciones de solo en el proyecto no se espera solo (puede ser una versión solo de rítmicas): la solista no aparece ni suena, sin bloquear ni avisar más que con una nota en su carril (Jorge, 16/11/2026). Y al revés: con solos marcados pero sin toma de la solista, el montaje se hace igual (hacer o no el solo se decide al grabar); en el solo siguen las rítmicas y suena la guitarra original. Nada de esto bloquea la exportación.
- **Tramo del vídeo:** del inicio de presencia más temprano al final más tardío.
- **Huecos sin ninguna parte, a elegir con el conmutador «Cortar huecos sin tomas»** (Jorge, 16/11/2026; desactivado por defecto): desactivado, en el hueco se ve el fondo y suena el backing; activado, el hueco se quita y el vídeo es la concatenación de los tramos con alguna parte presente. En cada corte, el tramo que acaba sale con un compás de fundido y el siguiente entra con otro (la misma regla que al principio y al final; confirmado por Jorge el 16/11/2026). La línea de tiempo marca los huecos cortados. Con «Cortar huecos», cada tramo empieza 0,5 s antes de la presencia (la entrada del recuadro); sin cortar, no. Los tramos se cuantizan a la rejilla de fotogramas.
- **Compás** para los fundidos: del pulso de la Fase 2; sin pulso, 120 BPM y 4/4 (como en la Fase 6).

### Layouts

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

### Transiciones

- Recolocación y cambio de tamaño: curva tipo muelle (ease-in-out), 0,5 s.
- Entrada: escala del 92 al 100 %, opacidad de 0 a 1 y desenfoque que se aclara, en esos 0,5 s. Salida: lo inverso.
- La entrada empieza siempre 0,5 s antes del inicio de presencia, para que el recuadro esté completo en la primera nota (Jorge, 16/11/2026; RF9 decía 0,3 s, que lo dejaba al 74 % de opacidad); si la toma no tiene imagen tan pronto, desde su primer fotograma. La salida empieza al final de la presencia. Los bordes de las secciones ya están en el pulso (Fase 4).
- En el plano único, el cambio rítmica ↔ solista (o entre guitarras de un corte) es un fundido cruzado con la misma escala y desenfoque.
- **Toma que acaba antes que el plan:** `MontageTimeline.imageBrightness` funde de 1 a 0 en 0,5 s (`MontageStyle.endFade`) sobre el último fotograma retenido y queda en negro hasta el final. Se oscurece el recuadro entero (imagen, relleno difuminado y rótulo; `MontageBoxState.brightness`). Solo se aplica si el recuadro sigue más de 50 ms tras la última imagen (`MontageStyle.endFadeTolerance`). En plano único manda la regla de cobertura. Vista previa y exportación comparten timeline y compositor.
- Audio de cada parte: entra y sale con fundido de 80 ms en los bordes de su presencia, y la entrada y salida del vídeo (un compás) con la misma curva en la vista previa y en la exportación (`MontageAudioEnvelope`); la imagen sigue lineal. La guitarra original que sustituye se silencia con el fundido inverso mientras la parte está presente.
- El audio del montaje ignora el silencio del canal «Tú · parte» de Grabar y usa solo su volumen.

### Encuadre

- Vision (pose corporal) sobre fotogramas muestreados de la toma ya compuesta (base y punches, en tiempo del tema): muñecas, codos y torso delimitan la caja de la guitarra, con margen.
- **Fijo:** la mediana de las cajas de la toma. **Seguir:** la trayectoria de la caja, suavizada (sin temblor ni saltos) y con huecos de detección interpolados.
- El recorte de cada recuadro es la caja ampliada a la proporción del recuadro en ese instante, sin salirse del fotograma. Sin detección: el fotograma entero, centrado.
- **Rotar** (0°, 90°, 180°, 270° en sentido horario): se guarda por cámara (`VideoSettings.rotations`, como el desfase) y por toma (`Take.videoRotation`, nil = 0°); una toma nueva hereda el de su cámara. Se aplica al leer, sin recodificar: el compositor gira y cambia ancho y alto, el reproductor usa `preferredTransform` y Vision recibe la orientación (`VideoRotation`, `MontagePartVideo.rotation`). `TakeFraming.rotatedClockwise` transforma el encuadre guardado en lugar de reiniciarlo. La huella del análisis incluye el giro solo si no es 0°. Los punches usan el giro de su toma. Botón en la vista previa de Grabar (desactivado mientras se graba), en Ajustes de vídeo y en la ficha de cada toma en Montaje, junto a «Encuadre».
- Ajuste manual por toma (hoja «Encuadre»): en fijo, mover y escalar la caja sobre el fotograma; en seguir, zoom y desplazamiento sobre la trayectoria. «Restablecer» vuelve al automático.
- El análisis se guarda en `cache/framing/<takeID>.json` (regenerable, con huella de la toma y sus punches); el modo y el ajuste manual, en el proyecto.

### Compositor y vista previa

- Compositor propio (`AVVideoCompositing`, Core Image sobre Metal) que dibuja cada fotograma a partir de un plan puro: para un tiempo `t`, la lista de recuadros con su rectángulo, escala, opacidad, desenfoque y recorte, más el fundido global y el rótulo.
- Las tomas entran en una `AVMutableComposition` con su `videoOffset` y sus punches (como `TakePreview`), sin recodificar.
- Vista previa en tiempo real con `AVPlayer` sobre la misma composición y el mismo compositor, con el audio del montaje sin normalizar (stems y tomas con sus volúmenes y fundidos). Puede bajar la resolución para ir fluida.

### Exportación

- Vídeo: HEVC o H.264, resolución y fps de «Exportación por defecto» de Ajustes (30 fps si no hay), modificables en la pantalla. Contenedor MOV o MP4 (`export.container`). Fichero `video/<tema>-<layout>.<mov|mp4>` (se sobrescribe el del mismo layout) y botón «Mostrar en Finder». El audio del vídeo va en AAC (128 kbit/s por canal).
- Mezcla: stems con la mezcla de Grabar (`recording.mix`), las guitarras sustituidas silenciadas durante la presencia de su parte, y las tomas con su volumen de canal «Tú · parte» y sus fundidos. Normalizada a -14 LUFS integrados (ITU-R BS.1770-4). El techo de pico real es -1,3 dBTP, con o sin limitador: 0,3 dB de holgura para el códec AAC. Con el conmutador «Limitador» (activado por defecto; Jorge, 16/11/2026), un limitador con anticipación sujeta los picos al techo y la mezcla llega a -14 LUFS; desactivado, si la ganancia llevara el pico real por encima del techo se frena la ganancia y se informa de los LUFS que quedan (en las pruebas, ~-16,3). Opción de no normalizar (el limitador solo actúa al normalizar). Con material muy brillante, el AAC puede subir el pico hasta +0,49 dB, más que la holgura; aceptado.
- WAV por pista (opcional), en `video/<tema>-<layout>-pistas/`: `backing.wav` (lo que suena del tema, sin tus tomas), uno por parte (`<parte>.wav`, con sus fundidos) y `mezcla.wav` (la normalizada). Todos con la duración del vídeo y alineados; 24 bits a la frecuencia del proyecto.
- Rótulo opcional: título y debajo artista, abajo a la izquierda, sobre placa oscura translúcida, 5 s con fundido de entrada y salida.
- Progreso con cancelar; cancelar borra los ficheros a medias.

### Interfaz

**Pantalla Montaje** (boceto `docs/design/Edit.dc.html`), ya en la barra lateral; «Ir al montaje» de Grabar se activa. Cabecera con tema, número de tomas y «Exportar vídeo». Tres columnas: Layout (los cinco, con miniatura), Vista previa (reproductor con play y posición; en portrait limitada a 440 pt para que la línea de tiempo quepa sin scroll) y Exportación, compacta y sin scroll (contenedor, formato, resolución, fps, -14 LUFS con «Limitador», rótulo, «Nombre de cada parte», «Mantener aspect ratio de vídeo», WAV por pista). La lista informativa «Transiciones» va en un popover tras el botón (i) junto a la cabecera. Debajo, la línea de tiempo: secciones y un carril por parte (cabecera de 270 pt) con su presencia (barra llena = en pantalla), el tramo del vídeo y los fundidos marcados; clic para mover la vista previa; los carriles se arrastran para reordenar los recuadros. En layouts de plano único, un carril «Plano» con los cortes. En cada carril, el nombre de la parte (sin partir ni truncar) y los botones «Encuadre» (hoja con fotograma, caja, conmutador «Seguir la guitarra», zoom, «Restablecer») y «Rotar». Sin tomas con vídeo: estado vacío con enlace a Grabar.

### Datos (Store, aditivo, sin subir `schemaVersion`)

- `Project.montage: MontageState?`: `layout` (`side`, `grid`, `stack`, `single`, `singleLandscape`), `singleRhythmPartID`, `singleCuts`, `caption`, `cutGaps`, `partOrder`, `showPartLabels`, `keepVideoAspect`, `export` (copia editable de `VideoExportDefaults` más `normalize`, `limiter`, `trackWAVs` y `container`), `framing: [takeID: TakeFraming]`.
- `TakeFraming`: `mode` (`fixed`, `follow`), `manualBox` (rectángulo normalizado, para fijo), `followZoom`, `followOffset`; `rotatedClockwise(quarterTurns:)`.
- `RecordingState.partMix`: fader «Tú · parte» de Grabar, restaurado al reabrir. `Take.videoRotation` y `VideoSettings.rotations`.
- `ProjectLayout`: `framingCacheURL(takeId:)`, `montageVideoURL(layout:)`, `montageTracksDirectory(layout:)`. `Library.saveMontage`.
- Copias de seguridad de `project.json`: `project.json.bak-AAAAMMDD` (7 días) y `project.json.lost-<fecha-hora>` cuando una escritura pierde una sección de primer nivel (`losesData` compara todas las claves, también `tabSource`) o el vídeo de una toma. Perder `videoRotation` dentro de una toma no crea `.lost`.
- Todo aditivo; `schemaVersion` sigue en 2 (decisión de Jorge).
- Tipos nuevos en fichero nuevo (`Montage.swift`); en `Models.swift`, `Files.swift` y `Library.swift` solo se añade (la Fase 5 también toca Store).

### Código

VideoKit sigue sin depender de AudioKit ni de Store: recibe un `MontagePlan` con tipos propios y la app hace de puente.

| Pieza | Paquete | Agente |
|---|---|---|
| `GuitarFramer` (Vision; caja fija y trayectoria), `MontagePlan` (entrada: lienzo, fps, layout, tramo, compás, partes con presencia, ficheros, desfases, punches y encuadre, pistas de audio con volumen y tramos, rótulo), `MontageLayout` (geometría), `MontageTimeline` (estado de los recuadros en `t`), `MontageCompositor`, `MontageBuilder` (composición + compositor + mezcla de audio de la vista previa → `AVPlayerItem`), `MontageExporter` (vídeo con `AVAssetReader`/`AVAssetWriter` y el WAV de la mezcla ya normalizada), `MontageAudioEnvelope` (fundidos de audio), `VideoRotation` (giro al leer), `tf-video frame` y `tf-video montage` (desarrollo) | VideoKit | `tf-engineer` |
| `LoudnessMeter` (BS.1770-4 integrado y pico real), `MontageMixer` (mezcla fuera de línea de stems y tomas con volúmenes, tramos con fundidos y fundido global; normalización; WAV por pista) | AudioKit | `tf-implementer` |
| `MontageState`, `TakeFraming`, rutas, `Library.saveMontage` | Store | `tf-implementer` |
| Pantalla Montaje, hoja «Encuadre», `MontageController` (puente Store → `MontagePlan` y `MontageMixer`, análisis de encuadre, exportación con progreso), datos simulados y `--screen montage` en DEBUG | App | `tf-implementer` |

La geometría de los layouts va con el compositor (mismo paquete y mismos tipos) aunque el plan la asigne a Sonnet. Reparto: primera tanda en paralelo, VideoKit (`tf-engineer`), AudioKit y Store (`tf-implementer`); segunda, la app; después `tf-qa` y capturas revisadas por el orquestador.

### Pruebas

- Puerta (sin hardware): tomas sintéticas (color liso distinto por parte, con `VideoTakeWriter`), una rítmica entera, otra parcial y una solista con dos solos. Se exporta en landscape y en portrait y se comprueba: dimensiones, fps y duración (tramo del vídeo); en instantes dados, el color esperado en el centro de cada recuadro (solista solo en los solos, completa en la primera nota; la parcial fuera al acabar su toma); fundidos de un compás al principio y al final; pista de audio presente.
- `MontageLayout` y `MontageTimeline`: rectángulos sin solapes dentro del lienzo, continuidad en las transiciones, 0,5 s de anticipación y recuadro completo en la primera nota.
- `GuitarFramer`: suavizado y huecos con poses sintéticas; caja dentro del fotograma y con la proporción pedida.
- `LoudnessMeter`: contra el `ebur128` del ffmpeg embebido, diferencia menor de 0,1 LU en tonos y ruido; `MontageMixer`: -14 ± 0,2 LUFS, tope de -1,3 dBTP, fundidos de 80 ms, pistas con la misma duración.
- Store: `montage` se guarda y se lee; un proyecto anterior se abre igual; copias `.bak` y `.lost` (`ProjectBackupTests`, `testWriteLosingTabSourceCreatesLostCopy`); rotación (`VideoRotationTests`).
- Cobertura y giro (VideoKit): `MontageSingleCoverageTests` (plano único), `MontageCompositionCoverageTests` (fundido a negro), `MontageOptionsTests`, `MontageFrameGridTests`, `MontageAudioFadeTests`, `VideoRotationTests`.
- Interfaz: capturas revisadas por el orquestador (Montaje en los cinco layouts, hoja Encuadre).

Límites conocidos: la app no tiene target de tests (sin cubrir `MontagePlanning.build`, la limpieza al cancelar, `BarTiming.sectionStop` ni los retoques de `RecordController` y `BackingController`); `limiterOutOfTolerance` sin test determinista; el solo del canal «Tú · parte» no se guarda; el ffmpeg embebido no trae `ebur128` y la medida de referencia usa el de Homebrew; el iPhone con Continuidad en vertical está sin probar; un fichero con transformación propia se gira según su tamaño natural.

### Lo que comprueba Jorge

1. Hoja «Encuadre» sobre tomas reales: la caja automática coge la guitarra, en fijo y siguiendo.
2. Vista previa: transiciones y entrada de la solista a la vista.
3. Exportar el mismo tema en landscape y en portrait y verlos; abrir los WAV por pista en un DAW.

### Estimación y condición de paso

De 6 a 10 horas, como en el plan.

Condición de paso: vídeo final exportado en portrait y en landscape, visto por Jorge; y el test de la puerta.

Cumplida el 18/11/2026 (ADR-018): Jorge probó a mano la app («todo correcto»), con el vídeo exportado en portrait y en landscape, y `MontageGateTests` es el test de la puerta.

## Retoques de interfaz (mini-spec de la Fase 7b)

Rama `fase-7b` desde `main` (Fases 5c y 7 ya cerradas allí). Lista de Jorge del 17/11/2026 (`docs/plan.md`, «Fase 7b»), numerada como allí. Decidido con Jorge el 17/11 y, las dudas de la mini-spec, el 18/11/2026.

### Condición de paso

Los diez puntos comprobados por Jorge en la app (con una copia de los proyectos), `Tools/test.sh` en verde y las capturas de Biblioteca (las dos vistas, el popup con resultados y con error), barra lateral con tema seleccionado, página del tema, Grabar con el visor de toma y Ajustes revisadas por el orquestador.

### Biblioteca

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

### Backing track

**7. Alargar o encoger una sección en el modo expandido.** Arrastrar un borde de sección con los acordes expandidos tiene que comportarse igual que plegado: el borde sigue al puntero, con el mismo imán, las reglas del punto 8 y se guarda al soltar. Lo primero es reproducir el fallo y explicar la causa (coordenadas del gesto en la vista expandida, vista que se rehace durante el arrastre, gesto que compite con el de la franja…), y dejar una prueba que falle antes del arreglo. Para que se pueda probar, la cuenta del arrastre (posición → tiempo en cada modo, borde inicial, imán, límites) sale de las vistas a un tipo puro, que usan los dos modos, con pruebas en su paquete.

**8. Sin secciones dentro de otras; empujar encoge a la vecina.** Reglas en `SectionEditor` (Store), que aplican el arrastre, las teclas (`nudgeEdge`) y el marcado:
- **Crear** (arrastre en la franja o «Marcar»): solo en hueco libre. No se puede crear una sección dentro de otra (Jorge, 18/11): si el arrastre empieza dentro de una sección no se crea nada; si empieza en un hueco y entra en una sección, se queda en su borde. Más corta que `minLength` → nada. Un rango igual al de una existente sigue alternando su solo. `mark` deja de partir secciones.
- **Empujar:** al llevar el borde de A contra B, el borde de B que toca se mueve con él y B se encoge, hasta `minLength`; ahí el arrastre se para. Solo se encoge la vecina inmediata, no hay cascada. Si B es un solo, el arrastre se para en su borde (decidido el 17/11). Un solo sí empuja y encoge a una sección normal: se está modificando de forma directa.
- **Separar:** al retirar el borde de A de B, B no le sigue; queda un hueco (Jorge, 18/11).
- Pruebas (`SectionEditorTests`): crear en hueco; crear empezando dentro → nada; crear cruzando una vecina → recortada a su borde; empujar encoge a la vecina; empujar hasta `minLength` → para; empujar contra un solo → para en su borde; un solo empuja a una normal; sin cascada a la tercera; separar deja hueco; teclas con las mismas reglas; ningún resultado con solapes ni secciones anidadas (propiedad comprobada en todas las pruebas).

### Grabar

**9. Ver las tomas hechas.** Cada toma de la lista de tomas de Grabar gana ▶ «Ver toma», que abre un visor con su vídeo y su audio procesado sincronizados (`TakePreview` de la Fase 6: `processed.wav`, vídeo con su desfase y punches), con reproducir/pausa, barra de posición y cerrar.
- El visor es una vista reutilizable (`TakeViewer`), que usan Grabar y la página del tema (punto 6).
- Suena con el backing, con un botón para silenciarlo (Jorge, 18/11): se reutiliza el camino del montaje (un plan de una sola parte en plano único, sin fundidos ni rótulo) para que audio, backing y vídeo vayan juntos por construcción.
- En el visor, las mismas acciones que ya tiene la fila (marcar como mejor y eliminar) para reevaluarla sin cerrarlo; sin «Descartar» (Jorge, 18/11: `Take.discarded` sigue siendo solo de la limpieza).
- No se abre grabando; al abrirlo se para el transporte de Grabar. Toma sin vídeo: solo audio, con el recuadro en negro.
- Pruebas: captura del visor; la sincronía la juzga Jorge en una toma real.

### Ajustes

**10. «Biblioteca» sin guitarras.** El apartado «Biblioteca y equipo» pasa a «Biblioteca» y pierde las guitarras del perfil de equipo.
- Fuera de la interfaz (`SettingsView` guitarras, `GuitarDraft`, `GuitarEditor`; `AppModel.upsertGuitar`/`deleteGuitar`) y del modelo de datos (`OwnedGuitar`, `PickupType`, `EquipmentProfile.guitars`, `Take.guitarId`), decidido el 17/11. Lo de audio del perfil (dispositivos, canales, latencia, master, frecuencia) no se toca.
- Migración: los ficheros viejos se siguen leyendo (la clave sobrante se ignora) y se escriben sin ella al guardar. Sin subir `currentSchemaVersion`: quitar un opcional no rompe a un binario anterior.
- Pruebas: un `profile.json` con guitarras se lee y se reescribe sin ellas, con audio intacto; un `project.json` con `guitarId` en las tomas se abre y se guarda sin él; captura de Ajustes.
- La fila «Biblioteca y equipo» de «Ajustes» en esta spec se corrige al cerrar la fase. Si la Etapa 2 necesita guitarras (calibración del DI por guitarra), vuelven allí con su propio diseño.

### Datos

Solo se quita lo del punto 10; lo demás no toca el formato. La regla de copia aislada sigue: la app de esta rama se prueba con `--projects-folder` y `--support-dir` sobre copias, nunca con `~/Music/ToneForge`. Con `--support-dir` apuntando a una copia sin `.env`, la clave sale del directorio de soporte por defecto (el orden del punto 4).

### Código

| Parte | Puntos | Qué | Agente |
|---|---|---|---|
| A. Secciones | 7, 8 | `SectionEditor` y sus pruebas; tipo puro del arrastre; `SectionBoxes`, `SectionGridBoxes`, `BackingTimeline`, `StudySession` | `tf-engineer` |
| B. Biblioteca y Spotify | 1–6 | SourceKit: `ImportQuery`, `DotEnv`, `SpotifyCredentials`, `SpotifyTokenProvider`, `SpotifySearchClient` con pruebas; Store: `LibraryFilter` y agrupado por artista; App: `LibraryView`, popup de importar, `LinkImportSheet`, `RootView` (tarjeta del tema), `ProjectDetailView` (grabaciones), `AppModel` (selección) | `tf-implementer` |
| C. Ver tomas | 9, grabaciones del 6 | App: `TakeViewer` (visor sobre `TakePreview`/plan de montaje de una parte), `ProjectRecordingsView`, `RecordView`, `RecordController` | `tf-implementer` |
| D. Ajustes | 10 | Store: `EquipmentProfile`, `Take` y pruebas de migración; App: `SettingsView`, `SettingsTab`, funciones de guitarras de `AppModel` | `tf-implementer` |

Las cuatro en paralelo: no comparten ficheros salvo `AppModel.swift` (B toca la selección; D solo borra las dos funciones de guitarras) y el paquete Store (ficheros distintos). Después, `tf-qa` una vez y capturas revisadas por el orquestador.

### Lo que comprueba Jorge

1. Biblioteca: buscador, dos vistas, Seleccionar/Mostrar en Finder, tarjeta de la barra con un título largo (desplazamiento al pasar el ratón), página del tema.
2. Popup: un enlace de YouTube, uno de Spotify, una búsqueda con ▶ (se oye en Spotify) y «Elegir»; y, quitando la clave del `.env` de la copia, que avisa y el enlace sigue funcionando.
3. Backing: alargar, encoger y empujar secciones expandido y plegado, también contra un solo; intentar crear una dentro de otra.
4. Grabar: ver una toma con vídeo y comprobar la sincronía de imagen, toma y backing.
5. Ajustes: «Biblioteca» sin guitarras y el audio igual que antes.

### Estimación

De 6 a 9 horas. Lo incierto: la causa del fallo del arrastre en el modo expandido (ya ha fallado más de una vez) y el desplazamiento al pasar el ratón en SwiftUI sin que la barra salte.

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
