# Audio con el dispositivo (mini-spec de la Fase 3)

Elegir dispositivo y canales, calibrar la latencia, mandar el backing al dispositivo, grabar la señal procesada y alinearla con el backing (RF1, parte de RF7). Estado: implementada y cerrada el 15/11/2026 (ADR-013).

Decidido por Jorge el 15/11/2026:

- **Nada cableado a la Flex Prime.** La app trabaja con cualquier pedalera o interfaz: se elige entre todas las entradas y salidas del sistema y se asigna cada canal a mano. Ninguna lógica mira el nombre del dispositivo.
- **Entrada y salida pueden ser dispositivos distintos**, con corrección de deriva.
- **El DI sale de la Etapa 1.** En esta fase no hay canal de DI, ni calibración de su nivel, ni grabación del DI seco: la app no pide nada sobre el DI. Todo ello pasa a la Etapa 2 (Fase 8a), y allí irá oculto al usuario. Esto cambia las casillas de la Fase 3 del plan y la pista de DI de la Fase 6: va en un ADR nuevo.
- **A/B:** en directo y con la última toma.

## Dispositivo y canales

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

## Calibración de latencia

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

## DI: fuera de esta fase

Pasa a la Fase 8a, junto con el DI guiado (ADR-010): el canal del DI, la calibración de su nivel (queda apuntado para entonces lo hablado: pico entre −12 y −3 dBFS tocando fuerte, por guitarra), la grabación del DI seco y «Usar la última toma como DI». La salida de reamp tampoco se incluye: ni en Ajustes ni en el perfil, hasta la Etapa 2 o hasta que Jorge lo indique. También sale de la Fase 6 la pista de DI del multipista. Lo único que queda aquí es el canal de referencia interno de la calibración, que la app encuentra sola y usa solo para medir el retardo del rig. En la Etapa 2 nada de esto se le pide al usuario de forma directa. El pendiente «Calibración del nivel de entrada del DI» sigue abierto. El boceto de Ajustes muestra «Entrada DI» y «Calibrar nivel del DI»: no se construyen.

## Grabación

- Botón «Grabar» de la pantalla Backing. Graba desde la posición actual hasta que se pulsa parar, con el backing sonando por `backingOut`.
- **Fichero:** `takes/<id>/processed.wav` (mono o estéreo, según `guitarIn`), WAV float32 a la frecuencia del proyecto.
- **Se guarda ya alineado:** la muestra 0 corresponde al instante `songStart` del tema. Quien lo lea después no necesita saber nada de latencias.
- **`Take` gana campos opcionales**, todos aditivos: `songStart` (segundos), `sampleRate`, `latencySamples`, `rigDelaySamples`, `rigDelayReliable`, `latencyCalibrated`, `calibrationKey` y `clock` (`single` o `aggregate`). `processedFile` ya existe; `diFile` se queda vacío hasta la Etapa 2. `schemaVersion` sigue en 2 y no hay migración, como pasó con `origin`.

## Alineado con el backing

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

## A/B dentro de la mezcla

Panel «Comparar en la mezcla» de Backing, sobre el stem de guitarra (con la Fase 4 se podrá elegir cuál).

- **A · Original:** el stem de guitarra suena.
- **B · Tú en directo:** el stem se silencia y te oyes por la monitorización del dispositivo. La app no controla ese volumen, así que no compensa: enseña la diferencia de nivel en dB (RMS de tu procesada en los últimos 3 s frente al del stem en ese tramo, con su fader) para que la ajustes en el aparato.
- **B · Última toma:** el stem se silencia y suena tu toma procesada, alineada, por la misma cadena que los stems (sigue la velocidad). Se iguala en sonoridad al stem de forma automática: RMS con ponderación K sobre el tramo de la toma, sin contar silencios, con tope de ±12 dB; la ganancia aplicada se enseña. La toma aparece como canal «Tú» en el mezclador.
- La medida de diferencia de tono («Diferencia en directo» del boceto) es de la Etapa 2; aquí solo nivel.

## Ajustes · Audio

Como el boceto, con los cambios de arriba: grupo Dispositivo (entrada, salida, frecuencia), grupo Canales (entrada de guitarra y salida del backing, con medidores de entrada) y grupo Calibración (estado y fecha de la latencia y el botón «Calibrar latencia», con su hoja: instrucciones, progreso, resultado en números). Nada de DI.

## Código

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

## Medidas con hardware (las hace Jorge)

Con la Flex Prime: USB Mode **Live**, 48 kHz, búfer 512. Montaje real usado (ADR-013): rig silenciado y `--guitar 3`, es decir, midiendo por el canal seco, porque el bucle a través del rig oscila. Cable de jack de la salida principal izquierda (o de auriculares) a la entrada de guitarra, con el volumen de salida a un tercio. En Ajustes: entrada y salida «HeadRush Flex Prime», backing 1 y 2, guitarra 1 y 2. Con otro aparato, lo mismo con sus canales.

1. `tf-audio latency --restarts 5`: latencia en ms, dispersión y variación entre reinicios.
2. `tf-audio verify`: error de alineado máximo y pendiente. Esto es la condición de paso.
3. Repetir 2 con entrada y salida en dispositivos distintos, para ver qué deja la corrección de deriva.
4. Quitar el cable, cargar un rig real y grabar una toma tocada: oír el A/B.

## Reglas propias de esta fase (aprobadas por Jorge el 15/11/2026)

- Solo se graba a velocidad del 100 % y con el bucle desactivado; con otra velocidad, el botón se desactiva y dice por qué.
- Sin cuenta atrás ni margen previo en esta fase: llegan con la pantalla de grabación (Fase 6) y el DI guiado (Fase 8a).
- Búfer fijo de 512, sin selector.
- El aviso y el botón de frecuencia descritos arriba.
- La latencia sin calibrar no bloquea la grabación: avisa, marca la toma y la corrige al calibrar.

## Estimación y condición de paso

De 4 a 6 horas, frente a las 2 a 4 del plan. La diferencia: dispositivos genéricos en lugar de la Flex Prime fija, entrada y salida en dispositivos distintos y el A/B con la toma grabada; quitar el DI resta cerca de una hora. Fila para el plan: «3. Audio con el dispositivo · 4 a 6 · marca el ritmo las pruebas de latencia y niveles con el hardware».

Condición de paso: toma grabada alineada con el backing con error menor de 1 ms, medido con la toma de comprobación de Jorge.
