# Ronda de validación de la Fase 7c en el PC x64

Guion para Claude Code en el PC Windows x64 de Jorge (NVIDIA). Objetivo: terminar la Fase 7c validándola en máquina nativa y
cerrarla si todo sale bien. Rama `pcx64tests` (sale de `fase-7c`); en paralelo Jorge avanza Flutter en el Mac y luego se juntan.
Contexto del Mac: `Tools/win/eval/HANDOFF-PC.md`. Reglas generales: `CLAUDE.md`. Fase: `docs/plan.md`, «Fase 7c» (sobre todo
«Condición de cierre de la 7c» y «Ola 2, trabajo ya identificado»).

## Ficheros que trae Jorge (pídeselos cuando toque, de uno en uno y diciendo para qué)

- `ToneForge-pcx64tests.bundle`: el repo (ya clonado si estás leyendo esto).
- `pc-bundle.zip` (~6 GB): ONNX Runtime con DirectML, WebView2 SDK, yt-dlp/deno/ffmpeg, modelos y 3 temas de prueba. Se extrae en la
  raíz del clon con `tar -xf <zip> -C <clon>`; deja `Vendor\win\{ort,webview2}`, `Vendor\helpers-win\x64`, `Vendor\models-win`,
  `Temp\qa-7c\evalB\projects` y `PC-BUNDLE.txt`.
- `remix-2004.zip` (~0,5 GB): audio de «2004 Remix» y stems de piano/otros de la VM y del Mac (punto 6b). Extraer en `Temp\remix\`.

## Reglas de la ronda

- La pedalera (HeadRush), la cámara y el oído son de Jorge: tú le guías y recoges números; nunca decides si algo suena bien.
- Partes A y B: no arregles código; si algo falla, recoge la evidencia y sigue. Al final, un fallo = una propuesta de arreglo, y
  preguntas antes de tocar nada.
- Nada de push. Commits solo en `pcx64tests`, en inglés, imperativo, sin `Co-Authored-By`. El hook commit-gate bloquea commits con
  Swift cambiado sin suite verde: en este PC la suite es la parte «tests» de `pass.ps1`; si hay que arreglar Swift, pásala verde
  y pide OK a Jorge para `SKIP_TEST_GATE=1`.
- Scripts y mediciones nuevas en `Temp\` (no se versiona). Nunca los proyectos reales de Jorge: siempre copias de los de prueba.
- No instales CUDA ni onnxruntime-gpu (otra sesión, después de DirectML).

## Parte A · Pase automático

1. `C:\tf` no debe existir antes del primer pase (el pase crea ahí una unión al clon). `C:\ToneForge\x64` lo borra y recrea el pase.
2. Desde la raíz del clon, en segundo plano (compila y separa audio, tarda), vigilando `Temp\win\pass\`:
   `powershell -NoProfile -ExecutionPolicy Bypass -File Tools\win\eval\pass.ps1 -With directml`
   Si el preflight falla, dice qué falta. Si una parte falla, el pase sigue. Audio y cámara en simulado. Nada pesado mientras corre.
3. Enseña `summary.txt`, `f3-timing.txt` y, de cada FALLO o TIMEOUT, las líneas relevantes de su `.out` (FAIL, ERROR, TIMEOUT,
   Exception; 15 como mucho). Ojo con `montage-full`: en la VM falló `salida.preview-viva` (ningún fotograma tras saltar a 125 s).

## Parte B · Mediciones que solo valen en máquina nativa

4. Separación DirectML frente a CPU: tabla de s de proceso por minuto de audio, separación principal y de guitarras (sale del
   pase con `-With directml`). Referencias: VM x64 en CPU emulada 510-622 s/min; Mac con Core ML 19,6-22 s/min.
5. F3 (arena de ONNX Runtime): resume `f3-timing.txt` (desglose con `TF_SEPARATE_TIMING=1`,
   `Packages/StemKit/Sources/StemKit/SeparationTiming.swift`) y propón 2-3 arreglos con su coste. Decide Jorge.
6. Puente bajo carga: app en simulado con copia de un tema de prueba; lanza una separación y, mientras dura, llama a
   `library.list` y `study.snapshot` cada 2 s desde un eval (mira `Tools\win\eval\*.js` y los lanzadores). Peor, mediana y p95 en ms,
   y en qué % de la separación. VM: en reposo peor 32 ms; bajo carga una llamada sin respuesta en 15 s (límite de
   `WinApp/Web/bridge.js:7`) al 41 %.
6b. Fuga de piano/otros en «2004 Remix» (`HANDOFF-PC.md`, sección «2004 Remix»): en el Mac con Core ML no hay fuga; en la VM con ONNX
   en CPU sí. Separa `song.wav` con `tf-separate` dos veces, CPU y DirectML, y mide RMS y pico (dBFS, definición de
   `StemLevelMeter`) de piano y otros, y las ventanas de 50 ms por encima de −50 dBFS en 71,3 s y 73,7 s (piano) y 317,5-318,3 s
   (otros, último trozo). ¿Fuga en CPU, en DirectML o en ambos? ¿Sigue la cola del final? Eso separa «kernel de ONNX» de
   «troceado/relleno del último trozo en Windows». Propón el arreglo; no lo apliques sin OK.

## Parte C · Con la HeadRush y la cámara (Jorge la conecta cuando se lo pidas; guíale paso a paso)

7. Grabar real en Windows: calibración con cancelación, vúmetro, toma corta, punch-in y `takeview.openOffset`. App con audio real;
    dile qué pulsar; recoge latencia en ms, desfase y log. Si va mal: número y plan B, no opinión.
8. Cámara por Media Foundation y «Rotar»; `tf-webdev --camera real` si aplica en Windows. Lista de comprobación y capturas.

## Parte D · Lo que falta probar desde la página (tú miras las capturas; Jorge mira y oye)

9. `plan.md`, «Sin probar desde la página»: limpieza real de la Biblioteca («Limpiar…»), borrado real de toma con recarga de
    Backing con el tema abierto, soltar ficheros, selector múltiple, «Sin artista» al final, ajuste del bucle por arrastre,
    metrónomo con rejilla de Songsterr (oído de Jorge), «Oír transcripción» y vuelta a Backing (oído de Jorge).
    La caja de sección sin acorde entero NO se valida (decisión de Jorge: queda obsoleta con Flutter).

## Parte E · Cierre

10. Comprime `Temp\win\pass\` y tus mediciones en `pass-results.zip` en el Escritorio.
11. Si A-D salen bien (o los fallos quedan arreglados con OK de Jorge, o anotados y él acepta dejarlos), cierra la 7c con
    `/phase-close` en `pcx64tests`: `tf-docs` (CODEMAP, «Estado actual» de CLAUDE.md, casillas de plan.md, números de esta ronda,
    ADR) con la lista de `HANDOFF-PC.md`, y commit. «Audio y cámara reales del Mac por AppCore» NO bloquea el cierre (se valida con
    Flutter). Antes de commitear el cierre, enseña el resumen y espera el OK de Jorge.
