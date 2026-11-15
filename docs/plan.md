# ToneForge · Plan de implementación

Fuente de verdad del plan desde el 15/11/2026 (ADR-002); antes, copia de la pestaña «Plan» del doc de spec (rev 50).
Spec completa: [spec.md](spec.md). Bocetos de pantallas: [design/](design/).

Once fases (0 a 10) en dos etapas: primero la herramienta de estudio y la grabación con vídeo; después el igualado de tono en la pedalera. Cada fase termina en algo que se puede probar y tiene una condición de paso. Sin fechas: la duración depende de lo que salga en la Fase 0.

## Forma de trabajo

- Spec primero: cada fase empieza con una mini-spec de sus módulos (entradas, salidas, casos de prueba) antes de escribir código.
- Un paquete Swift por módulo, con sus tests: AudioKit propio (E/S y reproducción), StemKit (separación), StudyKit (acordes, pulso, bucles), AnalysisKit (huella y distancia), MatchKit (optimizador), HeadRushKit, Tone3000Kit, TabKit, VideoKit y Store (archivo de proyecto e índice en SwiftData).
- Audios de prueba fijos en el repositorio: 3 temas cortos, 3 DI propios y sus resultados esperados, para probar análisis y distancia sin hardware.
- Lo que depende de la pedalera va detrás de una interfaz con una versión simulada, así el resto avanza aunque la Flex Prime no esté conectada.
- Una rama por fase; la fase se cierra cuando cumple su condición de paso y la spec queda actualizada con lo aprendido.

## Etapa 1 · Estudio y grabación (fases 0 a 7)

La pedalera se usa solo como interfaz de audio, con el rig que esté cargado: no hace falta controlar su editor ni TONE3000.

### Fase 0 · Pruebas de riesgo

Seis pruebas cortas e independientes, en scripts sueltos (Python o Swift), que deciden el resto del plan. Para la Etapa 1 solo hacen falta P2, P4 y P6; P1, P3 y P5 se dejan para el comienzo de la Etapa 2.

- [ ] P1 Remote Editor: capturar el tráfico navegador ↔ pedalera y documentar cómo listar rigs, leer un rig, cambiar un parámetro, cargar un rig y subir un NAM o un IR. Anotar la versión de firmware. *Etapa 2.*
- [x] P2 Audio USB: qué canales de entrada y salida expone la Flex Prime, si da el DI seco, si acepta reamp, a qué frecuencia de muestreo trabaja y si el retorno procesado incluye lo que se le envía por USB (el backing). *Superada, sin plan B; ver `docs/probes/P2-audio-usb.md`.*
- [ ] P3 TONE3000: obtener clave, iniciar sesión, buscar en el catálogo por marca y modelo y descargar un .nam y un IR. Anotar límites de uso. *Etapa 2.*
- [x] P4 Modelos: convertir BS-RoFormer SW y BTC a Core ML y comprobar que dan el mismo resultado que el original y a buena velocidad; el que no funcione bien pasa a ONNX Runtime como respaldo. Comparar la separación con HTDemucs 6 stems en 3 temas y medir tiempos. Elegir el modelo de pulso y el de transcripción de batería. *Elegidos BS-RoFormer SW (Core ML publicado, CPU+GPU), BTC, Beat This! y ADTOF; ver `docs/probes/P4-modelos.md`.*
- [ ] P5 Velocidad del bucle: medir cuánto tarda la pedalera en aplicar un cambio de parámetro, en cambiar de bloque y en cargar un NAM, para estimar cuánto dura un igualado. *Etapa 2.*
- [x] P6 Velocidad: comparar la calidad al 50 % de AVAudioUnitTimePitch y de Rubber Band. *Gana `AVAudioUnitTimePitch` con overlap 8; Rubber Band no hace falta; ver `docs/probes/P6-timepitch.md`.*

Condición de paso: para la Etapa 1, audio grabado por USB y un tema separado en local; para la Etapa 2, un parámetro cambiado desde script y un reamp grabado. *Etapa 1 cumplida (audio grabado por USB en P2; tema separado en local en `Probes/P4-modelos/bs_roformer_sw/out/stems/T1/`), confirmada por Jorge el 15/11/2026. Etapa 2 pendiente.*

Si falla: P1 → el igualado termina en una guía visual y el rig se carga a mano o por USB Transfer. P2 → interfaz de audio externa. P4 → HTDemucs como separador.

### Fase 1 · Base y biblioteca

- [ ] Proyecto Xcode (macOS 15+), paquetes vacíos, permisos de cámara, micrófono y red local
- [ ] Modelo de datos: tema, stem, guitarra, sección, rig, toma, vídeo, perfil de equipo; guardado en un archivo por proyecto dentro de su carpeta, con SwiftData solo como índice de la biblioteca
- [ ] Carpeta por proyecto en disco y limpieza de lo que se puede regenerar
- [ ] Importar WAV, FLAC o MP3 y convertir a la frecuencia de trabajo
- [ ] Descarga de modelos la primera vez y separación en 6 stems con progreso
- [ ] Pantalla de biblioteca
- [ ] Sección de Ajustes en la barra lateral (icono de engranaje), con el apartado Biblioteca y equipo: carpeta de proyectos, modelos descargados, espacio en disco, limpieza y perfil de equipo

Condición de paso: un tema importado y separado, con sus stems en disco.

### Fase 2 · Herramienta de estudio (RF7, RF10)

- [ ] Reproductor de stems sincronizados con volumen, silenciar y solo
- [ ] Velocidad del 50 al 200 %, transposición, afinación fina y capo virtual
- [ ] Detección de pulso, tempo, compases y tonalidad
- [ ] Detección de acordes, tira de acordes con diagramas y corrección a mano
- [ ] Secciones del tema, bucles ajustados al pulso y metrónomo
- [ ] Pantalla de backing track

Condición de paso: tocar encima de un tema sin guitarras, en bucle y al 70 %.

### Fase 3 · Audio con la pedalera (RF1)

- [ ] Selector de dispositivo y canales, guardado en el perfil de equipo
- [ ] Calibración de latencia con un pulso y de nivel de entrada del DI
- [ ] Apartado Audio de Ajustes: dispositivo, canales, frecuencia de muestreo y las dos calibraciones
- [ ] Envío del backing a la pedalera para escucharlo en sus auriculares
- [ ] Grabación simultánea del DI seco y de la señal procesada
- [ ] Alinear las pistas grabadas con el backing usando la latencia medida
- [ ] A/B de tu guitarra contra la original dentro de la mezcla

Condición de paso: toma grabada alineada con el backing con error menor de 1 ms.

### Fase 4 · Guitarras y secciones (RF6, parte de RF5)

- [ ] Separar la pista de guitarras en A y B por panorama estéreo
- [ ] Clasificar pasajes en rítmica o solista con Basic Pitch
- [ ] Nombrar las guitarras, marcar o corregir secciones a mano y mostrar la confianza
- [ ] Añadir las guitarras separadas al mezclador de la Fase 2
- [ ] Probar modelos dedicados a guitarra frente a BS-RoFormer SW (8,23 / 11,03 / 4,38 dB): MVSep Mega 53 guitarra de lumabeat (MIT, 77 MB, MLX) y becruily/mel-band-roformer-guitar (sin licencia). Decidido por Jorge en la Fase 0.

Condición de paso: Robe y Uoho en pistas distintas en 3 temas de prueba.

### Fase 5 · Tablatura y DI guiado (RF2, RF11)

- [ ] Transcribir las guitarras con Basic Pitch y asignar cuerdas y trastes; transcribir también el bajo (4 cuerdas) y la batería (modelo aparte: bombo, caja y charles como mínimo)
- [ ] Tablatura con alphaTab, cursor, edición y exportación a un único archivo de Guitar Pro con guitarras, bajo y batería, comprobado en Guitar Pro
- [ ] Grabar la toma con cuenta atrás y validarla: afinación, timing y clipping
- [ ] Guardar la toma como DI para el igualado de la Etapa 2

Condición de paso: toma válida a la primera en riffs sencillos.

### Fase 6 · Grabación con vídeo (RF8, parte de RF9)

- [ ] Captura de cámara (webcam o iPhone) con el mismo reloj que el audio
- [ ] Calibración del retardo de la cámara
- [ ] Apartado Cámara y vídeo de Ajustes: cámara por defecto, resolución, fotogramas por segundo, retardo y exportación por defecto
- [ ] Grabación multipista: backing, DI, procesada y micro
- [ ] Multitoma: partes, tomas por parte, mejor toma y punch-in (el rig recomendado para cada parte llega con la Etapa 2)
- [ ] Pantalla de grabación

Condición de paso: 3 tomas grabadas y alineadas a menos de 1 fotograma.

### Fase 7 · Montaje (RF9)

- [ ] Encuadre automático de la guitarra con Vision y ajuste manual
- [ ] Layouts landscape y portrait, y plano único para una rítmica y una solista
- [ ] Aparición de la solista solo en los solos, a partir de las secciones
- [ ] Compositor propio con las transiciones y vista previa en tiempo real
- [ ] Exportación: vídeo, mezcla a -14 LUFS, rótulo y WAV por pista
- [ ] Pantalla de montaje

Condición de paso: vídeo final exportado en portrait y en landscape.

## Etapa 2 · Igualado de tono (fases 8 y 9)

Empieza cuando la Etapa 1 está en uso. Antes de la Fase 8 se hacen las pruebas P1, P3 y P5 de la Fase 0.

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

La Etapa 1 no depende del Remote Editor ni de TONE3000. La tablatura (5) depende de las fases 3 y 4; la grabación (6), también de la 3 y la 4; el montaje (7), de la 6. En la Etapa 2, el igualado (9) depende de P1 y de la fase 8.

### Orden de ejecución

Mismo número de orden: se pueden hacer en paralelo o en cualquier orden entre sí. Las dependencias de las fases 5, 6, 7 y 9 y de las pruebas de la Etapa 2 son las del párrafo anterior; las demás están deducidas de lo que necesita cada tarea. Los modelos son los de «Modelos por fase».

| Orden | Qué | Va después de | Pedalera | Orquestador | Agentes |
|---|---|---|---|---|---|
| 1 | P4 · Modelos a Core ML | Nada | No | Opus | Opus |
| 1 | P6 · Calidad al 50 % | Nada | No | Opus | Sonnet |
| 1 | P2 · Audio USB | Nada | Sí | Opus | Sonnet |
| 2 | Fase 1 · Base y biblioteca | P4 | No | Opus | Sonnet |
| 3 | Fase 2 · Herramienta de estudio | Fase 1, P6 | No | Opus | Opus (pulso, acordes) · Sonnet (reproductor, pantalla) |
| 4 | Fase 3 · Audio con la pedalera | P2, Fase 2 | Sí | Opus | Opus (latencia, alineado) · Sonnet (selector, Ajustes de audio) |
| 4 | Fase 4 · Guitarras y secciones | Fase 2 | No | Opus | Opus (separación A/B, clasificación) · Sonnet (interfaz) |
| 5 | Fase 5 · Tablatura y DI guiado | Fases 3 y 4 | Sí | Opus | Opus (cuerdas y trastes, batería) · Sonnet (alphaTab, validación) |
| 5 | Fase 6 · Grabación con vídeo | Fases 3 y 4 | Sí | Opus | Opus (reloj común) · Sonnet (multitoma, pantalla) |
| 6 | Fase 7 · Montaje | Fase 6 | No | Fable | Opus (compositor, encuadre) · Sonnet (layouts, exportación, pantalla) |
| 7 | P1 · Remote Editor | Etapa 1 en uso | Sí | Fable | Opus (análisis del tráfico) · Sonnet (scripts) |
| 7 | P3 · TONE3000 | Etapa 1 en uso | No | Fable | Sonnet |
| 7 | P5 · Velocidad del bucle | P1 | Sí | Fable | Sonnet |
| 8 | Fase 8 · Análisis del tono | P3, Fase 5 | Sí | Fable | Opus (huella, distancia) · Sonnet (TONE3000, pantalla) |
| 9 | Fase 9 · Igualado en la pedalera | P1, Fase 8 | Sí | Fable | Opus (HeadRushKit, optimizador) · Sonnet (catálogo, knobs) |
| 10 | Fase 10 · Ampliaciones (v2) | Fase 9 | Otro hardware | Sin definir | Sin definir |

Sin pedalera se puede avanzar con P4, P6 y las fases 1, 2 y 4. La primera vez que hace falta conectarla es P2, que bloquea la Fase 3 pero nada de lo anterior. P4, P6 y P2 comparten una sesión orquestadora; P1, P3 y P5, otra.

## Estimación de tiempos

Entre 48 y 79 horas de trabajo con Claude Code: de 31 a 51 la Etapa 1 y de 17 a 28 la Etapa 2. Recalibrada con experiencia real (tareas estimadas en 1 o 2 semanas han llevado 5 o 6 horas). Marca el ritmo lo que solo se puede hacer con la pedalera y de oído. No incluye una posible versión de Windows.

| Fase | Horas | Acumulado | Qué marca el ritmo |
|---|---|---|---|
| 0. Pruebas P2, P4 y P6 | 3 a 5 | 3 a 5 | Probar el USB y convertir modelos |
| 1. Base y biblioteca | 2 a 3 | 5 a 8 | Descarga de modelos y primera separación |
| 2. Herramienta de estudio | 4 a 6 | 9 a 14 | Revisar acordes y pulso en temas reales |
| 3. Audio con la pedalera | 2 a 4 | 11 a 18 | Pruebas de latencia y niveles con la Flex Prime |
| 4. Guitarras y secciones | 3 a 5 | 14 a 23 | Escuchar si la separación A/B convence |
| 5. Tablatura (guitarras, bajo y batería) y DI guiado | 7 a 12 | 21 a 35 | Corregir transcripciones; la batería es lo más incierto |
| 6. Grabación con vídeo | 4 a 6 | 25 a 41 | Sincronía de cámara y pruebas de tomas |
| 7. Montaje | 6 a 10 | 31 a 51 | Ajustar transiciones y encuadre a la vista |
| Pruebas P1, P3 y P5 | 4 a 6 | 35 a 57 | Capturar el tráfico del Remote Editor |
| 8. Análisis del tono | 5 a 7 | 40 a 64 | Reamp y validar de oído la medida de parecido |
| 9. Igualado en la pedalera | 8 a 15 | 48 a 79 | Catálogo de bloques y afinar el bucle con hardware real |

En calendario, con unas 10 horas a la semana: la Etapa 1 en 3 a 5 semanas y todo en 5 a 8.

La mayor incertidumbre no es de horas sino de resultado: si el Remote Editor no se deja controlar (P1), la Fase 9 cambia de forma, no de duración.

## Modelos por fase

Cada fase la lleva una sesión orquestadora que escribe la mini-spec, reparte el trabajo en agentes de modelo igual o menor y revisa lo que devuelven. El orquestador no programa las partes: decide, integra y comprueba la condición de paso. Reparto propuesto el 15/11/2026, sin datos medidos todavía en este proyecto: se ajusta con lo que salga en la Fase 0.

| Fase | Orquestador inicial | Agentes | Por qué |
|---|---|---|---|
| 0. Pruebas P2, P4 y P6 | Opus | Opus para la conversión a Core ML (P4); Sonnet para los scripts de P2 y P6 | Scripts cortos e independientes; lo difícil es solo la conversión |
| 1. Base y biblioteca | Opus | Sonnet para paquetes, modelo de datos, importación y pantallas | APIs de Apple documentadas y trabajo guiado por la spec |
| 2. Herramienta de estudio | Opus | Opus para pulso y acordes; Sonnet para reproductor y pantalla | Integrar modelos es lo delicado; el resto es interfaz |
| 3. Audio con la pedalera | Opus | Opus para latencia y alineado; Sonnet para selector y Ajustes de audio | La precisión de 1 ms pide cuidado, no un modelo mayor |
| 4. Guitarras y secciones | Opus | Opus para la separación A/B y la clasificación; Sonnet para la interfaz | Procesado de señal acotado |
| 5. Tablatura y DI guiado | Opus | Opus para cuerdas y trastes y para la batería; Sonnet para alphaTab y validación de la toma | Fase larga pero de piezas conocidas |
| 6. Grabación con vídeo | Opus | Opus para el reloj común de audio y vídeo; Sonnet para multitoma y pantalla | La sincronía es el único punto fino |
| 7. Montaje | Fable | Opus para el compositor y el encuadre; Sonnet para layouts, exportación y pantalla | Compositor propio fotograma a fotograma, poco documentado |
| Pruebas P1, P3 y P5 | Fable | Opus para analizar el tráfico capturado; Sonnet para los scripts | Ingeniería inversa de un protocolo sin documentar |
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
