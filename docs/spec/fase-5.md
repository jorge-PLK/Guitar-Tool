# Tablatura (mini-spec de la Fase 5)

Parte de RF2 (tablatura con cursor, editable) y RF11 (bajo y batería, un único Guitar Pro). Rama `fase-5` desde `fase-4`, en un worktree: la Fase 6 va en paralelo y toca App y Store, así que esta fase añade ficheros nuevos y toca lo compartido lo mínimo. El DI guiado (grabar y validar la toma) es de la Fase 8a: la pantalla no lleva el panel «Entrada» ni «Última toma» del boceto `Tab.dc.html`, ni «Grabar toma».

## Decisiones de Jorge (16/11/2026)

1. **Cuándo:** se transcribe al abrir Tablatura por primera vez, con progreso, y se guarda. Si cambian las guitarras (L y R, tramos de solo), se rehace el pase de las pistas afectadas.
2. **Una entrada por pista:** cada pista de guitarra que exista según `GuitarSettings` (una pista, o L y R, más la solista si hay tramos de solo) es una pista de la tablatura y del Guitar Pro, con el nombre de `Guitar.name`; más bajo y batería. Los stems vacíos no generan pista.
3. **Sonido:** por defecto suenan los stems reales con el reproductor de estudio (velocidad, bucle, mezcla) y el cursor sigue al audio. Un conmutador por pista, «Oír transcripción», sustituye el stem de esa pista por la transcripción sintetizada.
4. **Edición completa básica:** guitarras y bajo: cambiar traste, pasar la nota a otra cuerda con la misma altura, borrar, añadir en la posición del cursor y cambiar duración. Batería: poner o quitar golpe por pieza en la rejilla. Deshacer y rehacer.
5. **Afinación por pista:** estándar por defecto (EADGBE; bajo EADG), con selector por pista: medio tono abajo, un tono abajo y drop D. Cambiarla reasigna cuerdas y trastes conservando las alturas, y va al Guitar Pro.

## Recorrido

1. Jorge abre un tema separado y entra en Tablatura. Si no hay transcripción o alguna pista está desfasada, se transcriben esas pistas con una barra de progreso por pista; las demás se cargan al momento.
2. Pestañas de pista (p. ej. «Guitarra izq.», «Guitarra der.», «Solo», «Bajo», «Batería»), cada una con su afinación (guitarras y bajo) y su «Oír transcripción».
3. La tablatura (alphaTab) muestra la pista elegida; el cursor sigue a la reproducción. Clic en una nota la selecciona y lleva el cursor; «Editar notas» activa el teclado de edición.
4. Barra de transporte como en Backing: volver al inicio, reproducir, velocidad 50–200 %, metrónomo y bucle (sección o compases seleccionados).
5. «Exportar a Guitar Pro» guarda un único `.gp` con todas las pistas (diálogo de guardar; nombre por defecto «Artista - Título.gp»).

## Transcripción

- **Guitarras:** `BasicPitchTranscriber` (TabKit, Fase 4) sobre el WAV de cada pista de guitarra. Notas polifónicas.
- **Bajo:** Basic Pitch sobre `stems/bass.wav`, reducido a una nota a la vez (la de más amplitud en cada ataque), 4 cuerdas.
- **Batería:** ADTOF Core ML FP32, `.cpuOnly`, con el contrato de `docs/probes/P4-modelos.md` (preproceso, entrada `[1, T, 84, 1]`, salida `[1, T, 5]`, umbrales y picos). Cinco piezas: bombo 35, caja 38, tom 47, charles 42, platos 49 (MIDI de percusión GM). Modelo embebido en la app como BTC y Basic Pitch (1,8 MB; licencia CC BY-NC-SA, uso personal, no se redistribuye la app).
- **Rejilla:** compases y pulsos de `BeatGrid` (StudyKit). Cada pulso se divide en semicorcheas o en tresillos de corchea, lo que menos error dé con los ataques de ese pulso. Ataques al punto más cercano; la duración llega hasta el final de la nota o el siguiente ataque de la misma pista, cuantizada; huecos como silencios. Todos los tempos escritos son enteros (BPM de negra): el tempo base de un tramo es la mediana del tempo real de sus 4 primeros compases (o los que queden), redondeada al entero más cercano. Un cambio de tempo por compás cuando la duración del compás se aleja más de un 2 % del tempo real vigente, o cuando el inicio escrito de un compás (sumando duraciones a los tempos enteros) se separa del real más de 20 ms (`maxWrittenDrift`): ese compás lleva el entero que más reduce la deriva a su final y el siguiente vuelve al tempo base entero. A tempo real no entero constante hay correcciones periódicas (dos cambios cada pocos compases); a tempo real entero constante, ninguna. Así el Guitar Pro no se desincroniza del tema; los tiempos de `TabScore` (cursor, sintetizado) son siempre los reales.
- **Cuerdas y trastes:** Viterbi sobre la secuencia de acordes y notas: cada nota en una cuerda distinta, trastes 0–24, coste por apertura de la mano dentro del acorde (más de 4 trastes muy penalizado), por salto de posición entre acordes y una preferencia leve por trastes bajos y cuerdas al aire. Acordes de más notas que cuerdas: se quitan las de menos amplitud. Notas fuera del registro de la afinación: se suben o bajan una octava y se cuentan en un aviso.
- **Desfase por pista:** cada pista guarda una huella de su origen (ruta, tamaño y fecha del WAV, versión del modelo y de los parámetros). Si no coincide al abrir, esa pista se rehace y sus ediciones se pierden; un aviso dice qué pistas se rehicieron. La afinación no forma parte de la huella: cambiarla reasigna cuerdas sin transcribir de nuevo.

## Partitura, sonido y exportación

- **Modelo propio en TabKit (`TabScore`, Codable):** pistas (nombre, tipo guitarra / bajo / batería, afinación), compases (inicio en segundos, compás, tempo), pulsos con su subdivisión, y notas (altura MIDI, cuerda, inicio y duración en la rejilla) o golpes (pieza). Las operaciones de edición y el deshacer viven aquí y se prueban sin interfaz. Se guarda en `tab/score.json` dentro de la carpeta del proyecto (no es caché: lleva las ediciones).
- **alphaTab** (versión fijada, embebida en la app, sin CDN; MPL-2.0) dentro de un `WKWebView`: renderiza a partir de `TabScore` y exporta con su exportador de Guitar Pro 7. La forma de pasarle la partitura (alphaTex, MusicXML o construir el `Score` en JS) la decide la prueba inicial.
- **Riesgo conocido:** las baterías que exporta alphaTab no suenan en Guitar Pro 8 con RSE. Se comprueba al principio con un `.gp` de prueba (guitarra, bajo y batería) que Jorge abre en Guitar Pro; si falla, se busca el ajuste del instrumento de percusión que lo arregle, y si no lo hay, se acepta que la batería se lea pero no suene con RSE.
- **Transcripción sintetizada:** se renderiza fuera de tiempo real a un WAV por pista (`AVAudioUnitSampler` con el soundfont GM de alphaTab; batería en el banco de percusión) en `cache/tab/`, y entra al reproductor de estudio como una pista más; «Oír transcripción» silencia el stem y activa la sintetizada, así sigue velocidad, bucle y sincronía sin un segundo reloj. Se vuelve a renderizar tras editar (con rebote).
- **Cursor:** la posición del reproductor se convierte a compás y pulso con los tiempos de `TabScore` y se envía a alphaTab.

## Datos

- Store, solo aditivo y sin subir `schemaVersion` (la Fase 6 también toca Store): rutas en `ProjectLayout` (`tab/score.json`, `cache/tab/`). `tab/` no entra en la limpieza; `cache/tab/` sí. `TabScore` es de TabKit; Store no depende de TabKit y la app hace de puente.

## Código

| Parte | Qué | Agente |
|---|---|---|
| 0. Prueba de alphaTab | Embeber alphaTab y su soundfont en la app; desde una partitura de prueba (guitarra, bajo, batería) renderizar y exportar un `.gp` a `Temp/p5/`, que Jorge abre en Guitar Pro; elegir el formato de entrada | `tf-implementer` |
| 1. ADTOF en la app | `.mlpackage` FP32 con GRU nativa embebido (zip en `App/Resources/Models/`), entrada en `ModelCatalog`, fixture con activaciones y golpes de referencia de Python | `tf-ml` |
| 2. TabKit: partitura | `TabScore`, rejilla y cuantización, cuerdas y trastes con afinaciones, reducción del bajo, edición y deshacer, conversión tiempo ↔ posición, huellas | `tf-engineer` |
| 3. TabKit: batería | `DrumTranscriber`: STFT y banco logarítmico con Accelerate, Core ML, picos; paridad con el fixture | `tf-engineer` |
| 4. Sintetizado | Render fuera de tiempo real de una pista de `TabScore` a WAV con el soundfont, alineado con el tema | `tf-engineer` |
| 5. App | Pantalla Tablatura, puente con alphaTab, orquestación de la transcripción por pista, cursor, edición, «Oír transcripción», exportación; rutas en Store | `tf-implementer` |

Orden: 0, 1 y 2 en paralelo; 3 tras 1; 4 tras 2; 5 tras 0 y 2, integrando 3 y 4.

## Pruebas

- Cuantización: ataques sintéticos sobre una rejilla con tempo variable caen en su subdivisión; un pulso con ataques en tresillo elige tresillos; los tiempos de compás de `TabScore` reproducen los del `BeatGrid` (error < 1 ms).
- Cuerdas y trastes: escalas y acordes abiertos conocidos (Mi, La, Re, power chords) salen en su digitación habitual; ninguna nota comparte cuerda en un acorde; cambiar de afinación conserva las alturas; notas fuera de registro se cuentan.
- Bajo: entrada polifónica sale con una nota por ataque.
- Edición: cada operación y su deshacer devuelve la partitura idéntica; pasar de cuerda conserva la altura y se niega si el traste sale de 0–24.
- Batería: activaciones y golpes de `DrumTranscriber` frente al fixture de Python (diferencia de activación < 1e-4; golpes a ±10 ms); pesado con `TF_MODEL_TESTS=1` bajo `guard.py` si hace falta el modelo.
- Huellas: cambiar el WAV de una pista marca solo esa pista como desfasada.
- Sintetizado: un golpe en el pulso N suena en el tiempo del pulso N del tema (error < 1 ms).
- Exportación: el `.gp` se genera y alphaTab lo vuelve a leer con el mismo número de pistas, compases y notas. La apertura en Guitar Pro la comprueba Jorge.
- Interfaz: capturas revisadas por el orquestador.

## Estimación y condición de paso

De 6 a 10 horas, como en el plan; lo incierto es la calidad de la transcripción de guitarras distorsionadas y la batería en Guitar Pro.

Condición de paso: tablatura de un tema con guitarras, bajo y batería exportada y abierta en Guitar Pro (Jorge).

## Lo aprendido al cerrar la fase (16/11/2026, ADR-016)

- alphaTab 1.9.0 exporta la batería a Guitar Pro 7 y suena con RSE en Guitar Pro 8 sin parche (incluye el arreglo #2467/#2468); `patchDrumGpif` queda sin uso. La partitura se pasa como JSON propio v1 y el `Score` se construye en JS (`tf-bridge.js`).
- ADTOF FP32 con GRU nativa y `.cpuOnly` da paridad exacta con Python (1117/1117 golpes en T1); se trocea con 30 s de contexto.
- Con tempos escritos enteros, la deriva máxima del `.gp` es de unos 50 ms; cursor y sintetizado usan los tiempos reales. El sintetizado queda con precisión < 0,07 ms.
- Calidad según Jorge: bajo muy bueno; batería buena, pero ADTOF etiqueta mucho charles (probablemente abierto) como crash o ride; guitarras pésimas (en El roce, 256 notas fuera de registro movidas de octava y 72 quitadas). Pasa a la Fase 5b.
- Los compases irregulares (3/4, 2/4) en intros vienen del `BeatGrid`.
- No hay modelo publicado probado en guitarra eléctrica distorsionada ni en stems. Candidatos: Guitab (`danmor/guitab`, 6,2 M, CC BY-NC-SA, fácil a Core ML) y MuScriptor small (autorregresivo, CC BY-NC, difícil a Core ML); plan B, TabCNN con SynthTab y reentreno.
- Sin probar a fondo por Jorge: teclado de edición y «Oír transcripción» con reproducción real; calidad del soundfont por valorar.
