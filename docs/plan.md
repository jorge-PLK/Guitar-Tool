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

- [Fase 0 · Pruebas de riesgo](plan/fase-0.md)

- [Fase 1 · Base y biblioteca](plan/fase-1.md)

- [Fase 2 · Herramienta de estudio (RF7, RF10)](plan/fase-2.md)

- [Fase 2b · Fuentes externas (ADR-008)](plan/fase-2b.md)

- [Fase 3 · Audio con el dispositivo (RF1)](plan/fase-3.md)

- [Fase 4 · Guitarras y secciones (RF6, parte de RF5)](plan/fase-4.md)

- [Fase 5 · Tablatura (parte de RF2, RF11)](plan/fase-5.md)

- [Fase 5b · Calidad de la transcripción de guitarra](plan/fase-5b.md)

- [Fase 5c · Interfaz de la tablatura (rama desde `fase-5b`)](plan/fase-5c.md)

- [Fase 6 · Grabación con vídeo (RF8, parte de RF9)](plan/fase-6.md)

- [Fase 7 · Montaje (RF9)](plan/fase-7.md)

- [Fase 7b · Retoques de interfaz (rama desde `fase-7`)](plan/fase-7b.md)

- [Fase 7c · Port a Windows (cerrada el 24/11/2026 en la rama `pcx64tests`)](plan/fase-7c.md)

- [Fase 7d · Actualizaciones automáticas (sin rama aún; rama `fase-7d` desde `main` después de la migración de la interfaz a Flutter)](plan/fase-7d.md)

- [Fase 7e · Editor de layouts propio (sin rama aún)](plan/fase-7e.md)

- [Fase 7f · Interfaz única en Flutter (rama `fase-7f` desde `fase-7c`)](plan/fase-7f.md)

## Etapa 2 · Igualado de tono (fases 8a, 8 y 9)

Empieza cuando la Etapa 1 está en uso. Antes de la Fase 8 se hacen las pruebas P1, P3 y P5 de la Fase 0 y, en paralelo con ellas, la Fase 8a.

- [Fase 8a · DI guiado (parte de RF2)](plan/fase-8a.md)

- [Fase 8 · Análisis del tono (RF4)](plan/fase-8.md)

- [Fase 9 · Igualado en la pedalera (RF3, RF5)](plan/fase-9.md)

- [Fase 10 · Ampliaciones (v2)](plan/fase-10.md)

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
| 6 | Fase 7f · Interfaz única en Flutter | Fase 7c (rama desde `fase-7c`) | Solo en la pasada de Jorge | Opus | Sonnet (`tf-flutter`: pantallas, stores, `core/`; `tf-implementer`: `AppCoreFFI`, fixtures, desvíos) · Haiku (`tf-flutter-mech`: tokens, ARB, DTO) |
| 7 | Fase 7d · Actualizaciones automáticas | Fase 7f (rama desde `main`) | No | Opus | Sonnet (UpdateKit, diálogo, Ajustes, script de release, investigación) |
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
| 7f. Interfaz única en Flutter | Opus (orquesta y valida; no implementa) | Sonnet (`tf-flutter`) para pantallas, stores Riverpod, `CustomPainter`, `core/` y tests; Sonnet (`tf-implementer`) para `AppCoreFFI`, canal de píxeles, fixtures, códigos de mensaje y desvíos de núcleo; Haiku (`tf-flutter-mech`) para tokens, iconos, ARB y DTO desde fixtures; `tf-auditor` para revisar cada pantalla contra su ficha; `tf-qa` y `tf-docs` al cerrar cada ola. Ningún agente Opus como mano de obra (decisión de Jorge) | Trabajo guiado por fichas y por un contrato con fixtures; lo delicado (hilos FFI, reloj de vídeo, foco del WebView) se decide en P9 y lo corta el orquestador |
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
