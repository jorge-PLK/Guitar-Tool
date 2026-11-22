# Guitarras y secciones (mini-spec de la Fase 4)

Separar la pista de guitarras en una pista por guitarra, clasificar sus pasajes en rítmica o solista, nombrarlas y llevarlas al mezclador (RF6, parte de RF5). Va en paralelo con la Fase 3, en la rama `fase-4` (worktree aparte). Decidido por Jorge el 15/11/2026: la condición de paso se comprueba solo de oído con 3 temas de Extremoduro; la prueba de modelos de guitarra va primero y falla rápido; la separación propone izquierda, derecha y centro y descarta la que salga vacía.

## Opciones de guitarras y tramos de solo (revisión de Jorge, 15/11/2026; manda sobre lo que contradiga más abajo)

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

## Prueba de modelos de guitarra (primero)

- Candidatos: MVSep Mega 53 guitarra (lumabeat, MIT, MLX) y `becruily/mel-band-roformer-guitar` (sin licencia: uso personal, no redistribuir). Referencia a batir: BS-RoFormer SW con 8,23 / 11,03 / 4,38 dB de SDR en guitarra (T1 / T2 / T3), con la misma métrica y entrada que P4.
- Falla rápido: cada candidato se prueba con T1 en su runtime original; si no supera 8,23 dB se descarta sin seguir.
- Se adopta solo si la media de T1–T3 mejora en más de 1 dB y se puede pasar a Core ML (CPU+GPU). Si se adopta, entra como paso extra solo para la guitarra y su integración se decide con Jorge en un ADR. Si no, la Fase 4 trabaja sobre `stems/guitar.wav` de BS-RoFormer SW.
- Resultados en `docs/probes/P4-modelos.md`, apartado «Fase 4: modelos de guitarra». Scripts en `Probes/P4-modelos/guitar_models/`.

## Separación por panorama

- Entrada: `stems/guitar.wav` (estéreo, a la frecuencia de trabajo). Salida: hasta tres pistas estéreo en `stems/guitar_L.wav`, `stems/guitar_C.wav` y `stems/guitar_R.wav` (regenerables, como el resto de `stems/`).
- Método: STFT con Accelerate, índice de panorama por bin a partir de las magnitudes de L y R, y máscaras suaves por canal. La pista izquierda sale del canal L, la derecha del R y la de centro de los dos; en cada bin las máscaras suman 1. Así la suma de las pistas es la pista de guitarras, y con todas a 0 dB la mezcla no cambia. La misma máscara en los dos canales se probó y queda unos 7 dB peor con guitarras abiertas (T1, 15/11/2026). Los parámetros (anchura del centro, estrecha por defecto, y suavidad de la transición) son constantes con nombre, ajustables desde los tests.
- Pista vacía: se descarta la que cumpla `StemLevelMeter.isEmpty` (RMS < −60 y pico < −30 dBFS; el pico era −40 hasta el 21/11/2026, ver ADR-009 D11) o quede muy por debajo de la pista de guitarras (ver propuestas). Una pista descartada no aparece en el mezclador ni se guarda en disco.
- Confianza por pista (alta, media o baja): mezcla de cuánta energía de la pista cae lejos de las zonas de transición y de cuánto se parecen las envolventes de las pistas que quedan. Dos guitarras dobladas que tocan lo mismo dan media o baja (riesgo «rítmicas dobladas»); una guitarra sola con foco, alta; una entrada mono, baja. La correlación L/R de la entrada se descartó como criterio: daba baja a una guitarra sola paneada. Los umbrales se calibran con T1–T3, que tienen las guitarras por separado (`guitar_parts/`).
- **Descartado (ADR-014, 16/11/2026): toda esta sección de panorama y su puerta del centro; ninguna anchura sonó bien.** Queda como historia de la decisión. Centro con puerta (Jorge, 15/11/2026): la pista central solo existe en los pasajes de solo. Fuera de ellos C vale 0 y L y R se quedan cada una con su canal entero, sin que C les robe nada; dentro, el centro es más ancho (anchura elegida por Jorge de oído en el barrido de Platero). Fundidos de unos 100 ms en los bordes. La puerta sale de los tramos que el usuario marca en el editor «Aislar solo». La detección automática solo propone un tramo cuando su confianza es alta: en Platero, el clasificador sobre la C de una primera pasada marcaba solista el 74 % del tema. Sin tramos marcados no hay pista central. Excepción: una entrada casi mono (una sola guitarra) se queda en C, sin puerta. Al aplicar el editor, las pistas se rehacen en segundo plano. Parámetros de partida dentro del tramo: centro 0,30 y suelo de coherencia 0,15, los mejores del barrido del 15/11/2026. Jorge no dio por buena ninguna anchura de oído: aislar el solo de verdad pide un modelo de solista frente a rítmica, pendiente para la Etapa 2.
- Límite medido el 15/11/2026: con máscaras de panorama, parte del solo sigue en L y R, y quedan restos de L en R y de R en L. ADRess (cancelación por azimut) se probó y se descartó: gana en T1 pero pierde en T2. La guía por notas de Basic Pitch quita 3,2 dB de solo de L y R en el banco con referencia, pero Jorge sigue oyendo el solo; queda en StemKit como opción (`centerNotes`), sin conectar.
- Corre en el proceso de la app, tras la separación y la medida de niveles, como el análisis. Proyectos ya separados: se hace al abrirlos si falta. Se rehace si cambia `stems/guitar.wav`.

## Clasificación rítmica o solista

- Basic Pitch con su modelo Core ML oficial, embebido en la app como BTC (lo valida `tf-ml` frente a la versión de Python). El envoltorio vive en TabKit, que lo reutiliza en la Fase 5.
- Se transcribe cada pista de guitarra propuesta. Por ventanas de un compás (pulso de la Fase 2) se mide la polifonía media, la fracción de tiempo con 3 notas o más, la densidad de notas y el registro. Acordes o power chords repetidos = rítmica; línea de notas sueltas = solista; sin notas = sin guitarra.
- Solista es solo un solo de verdad. Arpegios, arreglos y adornos cortos de una guitarra de acompañamiento cuentan como rítmica: mismo tono en RF5 y sin cambio de plano en RF9 (Jorge, 15/11/2026). Por eso la clasificación usa también el contexto de la pista: una pista que calla casi todo el tema y entra con una línea melódica es un solo; una que suena todo el tema con notas sueltas es acompañamiento, es decir, rítmica.
- Banco de referencia, «El roce de tu cuerpo» (Platero y Tú), según Jorge: L rítmica; R acompañamiento (arpegios, arreglos, adornos), rítmica para la app; C el solo de mitad de canción.
- Ventanas iguales seguidas se unen en pasajes de 2 compases como mínimo. Cada pasaje lleva su papel y una confianza (margen de la puntuación).
- Lo detectado va a la caché de análisis (`cache/`, regenerable). Las correcciones a mano van en `project.json` y sobreviven a un nuevo análisis, como los overrides de acordes.

## Interfaz

- Pantalla Backing (boceto `docs/design/Backing.dc.html`): si hay guitarras separadas, el canal «Guitarras» del mezclador se sustituye por un canal por guitarra propuesta, con volumen, silencio y solo. Nombre por defecto «Guitarra izq.», «Guitarra centro» y «Guitarra der.», editable en el canal (p. ej. Robe y Uoho). Insignia de confianza en el canal.
- Línea de tiempo: un carril por guitarra bajo el de secciones, con sus pasajes coloreados por papel y la confianza en la opacidad. A mano: cambiar el papel, mover los bordes (imán al pulso), partir y unir pasajes.
- Si una pista tiene confianza baja, el aviso de la spec: «Cuando dos guitarras tocan lo mismo puede quedar algo de una en la otra pista».
- **Descartado (ADR-014): el editor «Aislar solo» y los carriles de pasajes; mandan las cajas de secciones.** Editor «Aislar solo» (pedido por Jorge el 15/11/2026, entra en esta fase). Se abre desde un pasaje de solo del carril de C, o arrastrando un tramo nuevo. Tiene dos vistas del tramo, con un interruptor, que editan la misma selección:
  - Espectrograma (tiempo × frecuencia): se arrastra la franja de frecuencias del solo.
  - Mapa de panorama × frecuencia, donde cada guitarra se ve como una mancha: se dibuja un rectángulo, que fija el rango de panorama y la misma franja de frecuencias.
  - Escucha en bucle de C, L y R mientras se ajusta, y botones «Restablecer» y «Aplicar».
  La selección (tramo, franja de frecuencias y rango de panorama) se guarda en `project.json` por tramo de solo y sustituye a la puerta automática en ese tramo. Las pistas siguen sumando la pista de guitarras. Lo que queda fuera de la selección, dentro del tramo, vuelve a L y R por canal.

## Datos

- Cambios aditivos en Store, sin subir `schemaVersion` (la Fase 3 también toca Store; así no chocan): `Guitar` se rellena con `side` (`L`, `C` o `R`) y el fichero de su pista; pasajes corregidos por guitarra; mezcla por guitarra (`StemMix` admite una guitarra además de un `StemKind`). Un proyecto v2 sin guitarras se lee igual que hoy.
- Protocolo nuevo en Store (`GuitarSplitting`, o como encaje con `StudyAnalyzing`) que implementa la app, para que la cola de la biblioteca haga separación → niveles → panorama → análisis.

## Código

| Paquete | Qué | Agente |
|---|---|---|
| `Probes/P4-modelos/guitar_models/` | Prueba de modelos de guitarra | `tf-ml` |
| ModelKit + recurso de la app | Basic Pitch Core ML embebido, validado frente a Python | `tf-ml` |
| StemKit | `PanSplitter` (máscaras, pistas, vacías, confianza) y sus tests | `tf-engineer` |
| TabKit | Envoltorio de Basic Pitch y `PassageClassifier`, con sus tests | `tf-engineer` |
| Store | Modelo de datos aditivo, protocolo y paso en la cola | `tf-implementer` |
| App | Canales por guitarra, carriles de pasajes, nombres y confianza | `tf-implementer` |

## Pruebas

- `PanSplitter`: tres señales sintéticas paneadas a izquierda, centro y derecha salen en su pista con diafonía < −20 dB; la suma de las pistas reproduce la entrada (error < 1e-5); una entrada mono deja solo el centro y descarta izquierda y derecha. Con 12 s de T1 se informa la diafonía frente a `guitar_parts/` (medida, sin umbral).
- Basic Pitch: notas del Core ML frente a la referencia de Python en un fixture (test pesado con `TF_MODEL_TESTS=1`, bajo `guard.py`).
- `PassageClassifier`: listas de notas sintéticas (acordes → rítmica, línea → solista, vacío → sin guitarra), unión de ventanas y mínimo de 2 compases.
- Store: guitarras, pasajes corregidos y mezcla por guitarra se guardan y se leen; un proyecto v2 anterior se abre igual; las correcciones sobreviven a un nuevo análisis.
- Interfaz: capturas revisadas por el orquestador.

## Lo aprendido al cerrar la fase (16/11/2026, ADR-014)

- Modelo lead/rhythm adoptado: Mel-Band RoFormer anónimo (openrail) en Core ML FP16, `num_overlap` 2, `MaskModelContract.leadRhythm`. Con «Guitarras en L y R», Robe y Uoho salen en pistas distintas en 3 temas de Extremoduro (de oído).
- Los modelos dedicados de guitarra (Mega 53, 7,58 dB; becruily, 5,81 dB) no superan a BS-RoFormer SW (8,23 dB en T1). La puerta del centro y `PanSplitter` quedan sin uso; el solo se cuela algo en la rítmica y un modelo solista frente a rítmica mejor queda para la Etapa 2.
- Backing no lleva grabación ni A/B (canal «Tú», «Comparar en la mezcla», botón de grabar): el código de la Fase 3 se conserva para la Fase 6. Tampoco A/B por guitarra.
- La Etapa 2 sale de la UI: «Igualar tono», la pestaña «Pedalera y TONE3000» y los rigs en Biblioteca; «Tablatura y DI» pasa a «Tablatura».
- Secciones editables en Backing (popover, asas, ◀ ▶, Supr, colores `TF.sectionPalette`); el mezclador no muestra stems vacíos.

## Propuestas confirmadas por Jorge el 15/11/2026

1. Descartar también una pista que quede más de 24 dB por debajo de la pista de guitarras, aunque no llegue a «vacía»: sin esto, la de centro de un tema con dos guitarras abiertas sale casi siempre con restos.
2. Ventana de clasificación de un compás y pasajes de 2 compases como mínimo.
3. En el mezclador, las guitarras separadas sustituyen al canal «Guitarras»: no se muestran a la vez, para que no se sumen dos veces.
4. Los nombres por defecto «Guitarra izq.», «Guitarra centro» y «Guitarra der.».

## Estimación y condición de paso

De 3 a 5 horas, como en el plan; la prueba de modelos puede añadir 1 si un candidato pasa a Core ML.

Condición de paso: en 3 temas de Extremoduro elegidos por Jorge, Robe y Uoho quedan en pistas distintas, juzgado de oído por Jorge en la app.
