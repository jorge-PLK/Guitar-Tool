# Calidad de la tablatura (mini-spec de la Fase 5b)

Rama `fase-5b` desde `fase-5`. Condición de paso aprobada por Jorge el 16/11/2026: tablatura de 3 temas reconocible en la app (rítmicas, solos y batería con los platos corregidos), juzgado por Jorge. El primer tema, «El roce de tu cuerpo», es la puerta: los otros dos solo se prueban si pasa.

## Lo medido (16/11/2026, solo El roce)

- **Referencia:** la tablatura de Songsterr del tema, alineada al audio (`Probes/P5b-guitarra/eval_reference.py`; datos en `Temp/`, sin versionar). Basic Pitch sobre el bajo da F1 0,46 con ella, que comprueba la alineación.
- **Transcripción automática de guitarra:** F1 por nota (altura exacta, ataque ±50 ms) de 0,21 a 0,40 en el mejor caso. Guitab E25 gana a Basic Pitch en todos los stems (0,35–0,39 frente a 0,27–0,30); acordes BTC con los ataques de Guitab ganan en lo rasgueado y dan 0,00 en los riffs; el híbrido (acordes donde se rasguea, Guitab en los riffs) no generaliza a la otra guitarra; la limpieza del solo sube 0,21 → 0,24. Jorge: «ninguna termina de parecerse». MuScriptor small no se probó (pesos con licencia que hay que aceptar a mano).
- **Conclusión:** la transcripción automática no llega a reconocible con guitarra distorsionada separada. La tablatura de Songsterr pasa a ser la fuente por defecto y la automática queda de respaldo.

## Decisiones de Jorge (16/11/2026)

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

## Lo aprendido al cerrar la fase (17/11/2026, ADR-017)

- La URL de la página con pistas es `…/song-tab-s<id>`; `song-s<id>` da 404. Songsterr rechaza el acceso automatizado y varias descargas seguidas, por lo que la elección la hace Jorge.
- El desfase global necesita un rango ampliado por la diferencia de duración entre la tablatura y la grabación. El ajuste por bloques de 4 compases lleva una penalización por pulso para no cambiar de bloque sin motivo. La rejilla se pliega a doble o mitad de tempo, y se rellenan o quitan pulsos contra el periodo.
- Los solos se distinguen por altura exacta (`soloSalience`); en El roce, Solo 1 → Uoho con margen 0,72. El emparejamiento por croma sirve para las pistas rítmicas.
- Songsterr llama `upStroke` al rasgueo hacia abajo. alphaTab 1.9 lee `bendPoints[3]`, por lo que se duplica la cima del bend-release; el `.gp` admite 4 puntos como máximo.
- Suenan en «Oír transcripción»: palm mute, staccato, muteadas, ghost, acentos, bends, palanca y vibrato. No suenan aún: let ring, slides, ligados, armónicos, adornos y flam (Fase 5c).
- Respaldo: la puerta de silencio, el arreglo del port y el techo de registro MIDI 86 limpian Basic Pitch, pero la automática sigue sin ser reconocible con guitarra distorsionada.
- Voces de Songsterr: entran como pista `vocal` desde la Fase 5c (mini-spec «Interfaz de la tablatura»).
- Condición de paso cumplida con tres temas: «El roce de tu cuerpo», «Tornado Of Souls» y «Aquellas Cosas Que Solíamos Hacer». Jorge: «todo perfecto».
- Ramas atrasadas: el binario de `fase-5b` borró `recording`, `montage` y el vídeo de El roce al guardar `project.json`. Se prueba con copia aislada.

## Recorrido

1. Jorge abre Tablatura en un tema separado sin fuente elegida. La app busca en Songsterr con el artista y el título del proyecto (progreso «Buscando en Songsterr…»).
2. Hoja «Tablatura de Songsterr»: el primer resultado marcado, con artista, título y la lista de pistas (nombre, instrumento, afinación), más otros resultados y un campo para pegar un enlace. Botones «Usar esta», «Transcribir automáticamente» y «Cancelar».
3. Al usar una: se descargan sus pistas, se alinean con el audio y se propone el emparejamiento en una lista (stem → pista de Songsterr o «Transcripción automática»), con la confianza de cada pareja. «Aceptar» crea la tablatura.
4. Si la alineación encuentra diferencias de estructura (pulsos de más o de menos, repeticiones que faltan), un aviso dice en qué compases.
5. La pantalla sigue como en la Fase 5 (pestañas, cursor, edición, «Oír transcripción», exportación). Un menú «Fuente» por tema permite volver a buscar, cambiar el emparejamiento o pasar a automática.

## Alineación

Lo que funcionó en el prototipo (`eval_reference.py`), pasado a Swift: los compases y pulsos de la tablatura se colocan sobre los pulsos del `BeatGrid` con un desfase global en pulsos más un ajuste fino en ms, y se corrigen por bloques de 4 compases maximizando la energía espectral del stem en la altura de cada nota. La alineación por ataques y por croma (DTW) se probó y confunde desfases de 2 negras en el rasgueo periódico; no se usa. Las notas conservan cuerda, traste y afinación de Songsterr (sin Viterbi); los tiempos de `TabScore` son los reales del tema y el tempo escrito sigue la regla de la Fase 5.

## Respaldo automático (lo que entra en TabKit)

- **Arreglo del port de Basic Pitch:** una ventana con pico por debajo de −120 dBFS no pasa por el modelo (el `.mlpackage` convirtió `divide_no_nan` en una división normal y daba notas sobre silencio digital). Hecho.
- **Puerta de silencio** a −60 dBFS (`SilenceGate`), para cualquier transcriptor. Hecho.
- **Techo de registro** en MIDI 86 para guitarras (traste 22 de la primera cuerda): quita los armónicos sobreagudos de Basic Pitch.
- **Platos de ADTOF:** series de 4 o más golpes de plato a ≤ 0,5 s pasan a charles abierto (46), salvo el primero si cae con bombo (`DrumCymbalSeries`). Hecho; Jorge lo oye mejor en El roce.
- Guitab a Core ML queda fuera: gana poco y la CQT en Swift es cara. Se reconsidera si la prueba de quitar la distorsión (RemFX) mejora mucho.

## Errores

| Caso | Qué pasa |
|---|---|
| Sin resultados | «No está en Songsterr» y se ofrece la transcripción automática |
| Bloqueo (429) o sin red | Aviso con «Reintentar»; no se insiste en bucle. Se puede seguir con la automática |
| Formato de página o de pista desconocido | Aviso «Songsterr ha cambiado su formato» y automática; la tablatura ya importada no se pierde |
| Pista con algo que `TabScore` no representa (bends, slides, armónicos) | Se importa la nota sin el adorno y se cuenta en un aviso |

## Datos

- Store, solo aditivo: en el proyecto, la fuente elegida (Songsterr con `songId` y `revisionId`, o automática) y el emparejamiento stem → pista. Las pistas crudas de Songsterr van a `cache/songsterr/` (entra en la limpieza; se pueden volver a bajar).
- Huella de las pistas importadas: `songId`, `revisionId` y versión del conversor. Las ediciones se guardan en `tab/score.json` como en la Fase 5.

## Código

| Parte | Qué | Agente |
|---|---|---|
| 1. Lector de Songsterr | En la app, un `WKWebView` oculto carga la búsqueda y la página del tema como un navegador; SourceKit extrae el estado de la página (resultados, pistas, revisión) y las URL de las pistas; descarga de las pistas. Pruebas con páginas de muestra hechas a mano, sin datos reales | `tf-implementer` |
| 2. Conversor | Pista de Songsterr → notas de `TabScore` (cuerda, traste, ritmo, ligaduras, tempo y compases, afinación; batería a piezas GM). Guía: el conversor del proyecto `Metaphysics0/songsterr-downloader` (MIT). Pruebas con pistas sintéticas | `tf-engineer` |
| 3. Alineación y emparejamiento | Port de `eval_reference.py`: colocación sobre el `BeatGrid`, ajuste por bloques, aviso de diferencias de estructura; propuesta de pareja por croma | `tf-engineer` |
| 4. Respaldo | Techo de registro en TabKit (la puerta y los platos ya están) | `tf-engineer` |
| 5. App | Hoja de Songsterr, lista de emparejamiento, menú «Fuente», avisos; rutas y campos en Store | `tf-implementer` |

Orden: 1, 2 y 4 en paralelo; 3 tras 2; 5 tras 1 y 3.

## Estimación

De 8 a 12 horas. Lo incierto: que Songsterr cambie su página o bloquee el `WKWebView`, y las diferencias de estructura entre la tablatura y la grabación.
