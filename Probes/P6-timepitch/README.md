# P6 · Calidad de la velocidad: Apple TimePitch frente a Rubber Band

Compara el estiramiento de `AVAudioUnitTimePitch` (overlap 8 y 32, render offline en AVAudioEngine) con
Rubber Band (CLI 4.0, `--realtime`, motores R2 y R3). Casos por clip: velocidad 50 %, 70 % y +2 semitonos a 100 %.

## Lanzar

    brew install rubberband          # una vez
    Probes/P6-timepitch/run.sh Probes/testaudio/out/clips/*.wav
    Probes/P6-timepitch/run.sh --synth   # prueba de la cadena con una señal sintética de 10 s

`run.sh` compila `AppleRender/` (SwiftPM), y lanza `p6.py` con `uv run --python 3.12` (dependencias inline).

## Salidas (`out/`, ignoradas por git)

- `blind/<clip>_<caso>_A..D.wav`: los 4 motores barajados (semilla fija); casos `v50`, `v70`, `p2`.
- `key.json`: clave fichero -> motor. No abrir hasta puntuar.
- `sheet.md`: tabla para puntuar 1-5 cada fichero.
- `metrics.json` y tabla en consola: error de duración, deriva de afinación (cents), ataques conservados (%), CPU por segundo de audio.
- `render/<clip>/<caso>_<motor>.wav` (con nombre de motor), `log.txt`, `build.log`.

## Notas sobre las métricas

- Duración: tramo con señal (> -60 dB del pico) frente a lo esperado; así no cuenta la cola que añade el render de Apple.
- Afinación: pyin (resolución de 5 cents; con 1-2 cents el Viterbi falla con la salida de Apple), mediana de las notas estables. Con +2 st se compara con +200 cents.
- Ataques: media de la fuerza de onset (librosa) en los picos detectados, en % del original. Al ralentizar, un ataque fiel también se alarga, así que el valor baja aunque no haya fallo; comparar entre motores, no con 100 %. `onsets` = nº de picos detectados / original (>1 indica pre-eco o ataques fantasma).
- CPU: Apple, tiempo de CPU del proceso solo en el bucle de render; Rubber Band, CPU del proceso hijo completo (incluye E/S WAV). Dividido por la duración del fichero de salida.
