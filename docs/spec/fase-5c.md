# Interfaz de la tablatura (mini-spec de la Fase 5c)

Rama `fase-5c` desde `fase-5b`. Pendientes (a)–(d) del ADR-017 más lo que Jorge pidió el 17/11/2026 al ver la pantalla completa.

## Condición de paso (aprobada por Jorge el 17/11/2026)

En los tres temas de la 5b, juzgado por Jorge: las voces de Songsterr salen como voz en pentagrama y no hay pistas sin nombre; en «Oír transcripción» suenan let ring, slides, ligados, armónicos, notas de adorno y flams; con el teclado se ponen y se quitan P.M., bend, vibrato y slide, y el cambio se guarda; cada pista tiene mute y solo; todas las pistas pasan a stem o a transcripción de una vez; y una selección de la tablatura se reproduce en bucle. El roce es la puerta.

## Decisiones

1. **Teclas de Guitar Pro 8** (decisión de Jorge), tabla abajo.
2. **Mute y solo por pista** en la lista de pistas de Tablatura (hoy solo selecciona). Actúan sobre lo que suena de esa pista: el stem o, con «Oír transcripción», su síntesis; las pistas extra, sobre su síntesis. Comparten estado con la mezcla de Backing (`BackingController`), la misma regla de atenuación (`muted || (anySolo && !solo)`). Lo que no tiene pista en la tablatura (voz grabada, otros) sigue sonando salvo que haya un solo.
2b. **Todas a stem o a transcripción** (Jorge, 17/11/2026): sobre la lista de pistas, un selector «Stems / Transcripción» pone «Oír transcripción» en todas las pistas de una vez (las que no tienen stem suenan siempre con su síntesis). Si después se cambia una pista suelta, el selector queda en estado mixto. Las síntesis que falten se pintan en segundo plano, con progreso. Al abrir, las pistas extra (sin stem) quedan en «Oír transcripción» y el selector sale en «Stems».
3. **Bucle por selección:** clic en un pulso y ⇧clic en otro (o arrastrar) selecciona un tramo de pulsos, resaltado en la partitura; el bucle A-B de `StudyPlayer` pasa a ese tramo (del inicio del primer pulso al final del último) y la reproducción salta a su inicio. Funciona en lectura y en edición; en edición, ⇧← y ⇧→ amplían la selección. El menú de bucle muestra «Selección»; Esc o «Sin bucle» lo quitan. El clic simple sigue como hoy.
4. **Voces de Songsterr** (cambiada por Jorge el 18/11/2026): las pistas de voz pasan a un tipo de pista `vocal`: solo pentagrama, sin cuerdas ni trastes (altura MIDI), se exportan al `.gp` como pista sin tablatura. Van vinculadas al stem `vocals` por tipo de pista, no por el plan de emparejamiento: con «Stems» suena el stem y calla la síntesis; con «Transcripción» la síntesis sustituye al stem; M/S actúan sobre el stem de voz. Varias vocales comparten el stem, que se sustituye mientras alguna esté en transcripción. Sin stem de voz, la vocal es extra. La lista de emparejamiento no muestra la vocal.
   - Detección: en las cachés de los tres temas ninguna voz trae GM 52–54 (Tornado trae 67 y Aquellas 66). Se detectan por nombre: vocal(s), voice(s), voz/voces, singer, choir, coro; el 52–54 queda como criterio adicional. El roce no tiene voces.
   - Los `score.json` antiguos tienen las voces como guitarra hasta que se reimporten.
5. **Nombre vacío → instrumento:** el nombre de Songsterr si existe; si no, el del instrumento («Batería», «Bajo», «Guitarra», «Voz»), con número si se repite. En la tablatura, en la lista de emparejamiento y en el `.gp`.
6. **Las ediciones con teclado** actúan sobre la nota seleccionada o sobre todas las del tramo seleccionado, conmutan (la misma tecla pone y quita), entran en deshacer, se guardan en `tab/score.json`, se dibujan, se exportan y vuelven a sintetizar la pista si «Oír transcripción» está activo.

## Teclas (modo edición)

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

## Sonido de los adornos (`TabSynthRenderer`)

- **Let ring:** la nota suena hasta la siguiente de la misma cuerda o el fin del tramo let ring, con tope de 4 s.
- **Slides:** legato, glisando con pitch bend en el último tramo de la primera nota y la segunda sin ataque nuevo; shift, igual con ataque; entrada y salida, glisando corto (unos 3 trastes) al empezar o al acabar. El rango de pitch bend se amplía por RPN a lo que pida el slide más largo, con tope de 12 semitonos.
- **Ligados:** la segunda nota empieza justo al acabar la primera y con menos velocidad (sin púa).
- **Armónicos:** altura del armónico (12 → +12, 7 → +19, 5 → +24…; los artificiales, la que traiga Songsterr) con programa de armónicos o el de la pista.
- **Notas de adorno:** unos 60 ms antes del pulso (o en el pulso), con su ligado o slide si lo tienen.
- **Flam:** golpe de adorno unos 30 ms antes, con menos velocidad.

## Datos

Solo aditivo. `TabTrackKind` gana `vocal`; las técnicas que falten en `TabTechniques` (acento fuerte, tipo de slide) se añaden como opcionales. La regla de copia aislada sigue: el binario de esta rama no abre `~/Music/ToneForge`.

## Código

| Parte | Qué | Agente |
|---|---|---|
| 1. Sonido de adornos | `TabSynthRenderer`: let ring, slides, ligados, armónicos, adornos y flam, con pruebas sobre los eventos | `tf-engineer` |
| 2. Mute/solo y bucle | App: M y S por pista en Tablatura sobre `BackingController`; selector «Stems / Transcripción» para todas las pistas; selección de tramo en `tf-bridge.js` (resaltado, ⇧clic, arrastre), mensaje a Swift y bucle A-B; «Selección» en el menú de bucle | `tf-implementer` |
| 3. Voces y nombres | TabKit: tipo `vocal` en conversor, colocación, plan de importación, `AlphaTabScore` (solo pentagrama), `.gp` y programa en el sintetizador; nombre vacío → instrumento | `tf-implementer` |
| 4. Teclado | TabKit: operaciones de conmutar adornos en `TabEditor` con pruebas; App: teclas de la tabla en `handleKey` y ⇧←/⇧→ | `tf-implementer` |

Orden: 1 y 2 en paralelo; 3 y 4 en paralelo tras 1 (3 toca el sintetizador) y 2 (4 usa la selección de tramo).

## Estimación

De 6 a 9 horas. Lo incierto: que el slide legato y el ligado suenen naturales con un soundfont GM, y el arrastre para seleccionar con alphaTab sin su reproductor.
