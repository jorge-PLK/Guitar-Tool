# P4 · Modelos de separación, acordes y pulso

Fecha: 2026-11-15 · Fase 0 · Rama `fase-0`

Este informe cubre la separación de stems, el reconocimiento de acordes (BTC), el pulso (Beat This!) y la transcripción de batería (ADTOF). Veredicto de oído de Jorge sobre la batería (15/11/2026): aprobado.

## Objetivo

Decidir qué modelo separa los temas en stems (bajo, batería, otros, voz, guitarra, piano) y por qué vía corre en el Mac. Preguntas:

1. ¿Qué modelo separa mejor la guitarra?
2. ¿Qué vía de ejecución (Core ML, ONNX, GGML, PyTorch) cumple fidelidad, velocidad y memoria?
3. ¿Se puede separar un tema en local, de principio a fin?

## Audios de prueba

Tres multitracks de Cambridge MT, de uso educativo y fuera de git (ver `Probes/testaudio/README.md`). La mezcla es la suma exacta de los stems de referencia (error 3e-8), sin máster.

| Tema | Obra | Género y contenido | Duración |
|---|---|---|---|
| T1 | Ale Lak, «Nosso Mundo Deixou De Existir» | Rock, 9 guitarras | 3:05 |
| T2 | Chris Coltraine, «Heather Jane» | Guitarras limpias y crunch | 4:11 |
| T3 | Robert Hammon, «The Elephant» | Con piano y sintetizadores | 4:57 |

Equipo: MacBook Pro M3 Pro, 18 GB, macOS 26.6.2.

## Criterios (aprobados por Jorge)

| Eje | Bien | Aceptable | Falla |
|---|---|---|---|
| Fidelidad frente al original PyTorch | ≥ 35 dB (igual) | 25–35 dB si no se oye | < 25 dB |
| Velocidad | ≤ 1× tiempo real | ≤ 2× | > 2× |
| Memoria | — | — | > 8 GB |

Regla añadida por Jorge: fallar rápido. Cada vía se prueba con T1 en una pasada; si incumple, se descarta sin seguir.

## Modelo

BS-RoFormer SW de 6 stems (bass, drums, other, vocals, guitar, piano). Checkpoint `BS-Rofo-SW-Fixed` de jarredou (cuenta borrada; se usó el espejo de enerjazzer, con SHA-256 verificado). 174,7 M de parámetros. Licencia de los pesos «unknown»: válido para uso personal, no redistribuir.

## Separación: vías probadas

Tiempos por minuto de audio; «×» es múltiplo del tiempo real.

| Vía | Resultado | Veredicto |
|---|---|---|
| PyTorch oficial (trozo de 13,35 s) | CPU ~2× tiempo real, 4–5 GB. MPS sin memoria | Solo referencia |
| Conversión Core ML propia | 3 intentos fallidos por entorno (numpy 2.5 incompatible con coremltools 9.0; se fijó numpy 2.3.5) y por un error del envoltorio (rango 6); ninguno por operaciones no soportadas. Un 4.º intento con trozo largo y compilación para Neural Engine colgó el Mac (reinicio por watchdog a las 11:11) | No hizo falta retomarla |
| ONNX propio (trozo largo) | Sin memoria (hasta 48 GB) | Descartado |
| ONNX publicado (elicwhite, trozo de 4 s), CPU | 143–151 s por minuto (2,4–2,5×), 8,3–8,7 GB | Descartado con T1. Proveedor CoreML sin probar (reserva) |
| **Core ML publicado `gridshiftstudio/bs-roformer-sw-coreml` (trozo largo, FP16, CPU+GPU)** | 21,4–22,2 s por minuto (0,37×), pico 5,1–6,1 GB por tema, 353 MB. Fidelidad 57–68 dB en los stems principales (45–55 dB en piano y other, casi silenciosos). SDR frente a la referencia idéntico a PyTorch | **Elegida** |
| Core ML publicado `sunnymeadsound` (trozo de 3 s, macOS 14+, SHA-256 verificado), CPU+GPU | 17,9–18,0 s por minuto (0,30×), 2,6–3,8 GB. Pierde 0,3–1,4 dB | Descartado |
| `sunnymeadsound` en Neural Engine (`cpu_ne`) | ~7× más lento que en GPU (5,6 s frente a 0,8 s por trozo; compilación ANE 53 s). Con `.all` se abortó tras más de 3,5 min compilando | Descartado |
| BSRoformer.cpp (GGML, MIT; ggml `3af5f576`, repo `a7b9625f`) con GGUF q8_0 de FractalSurfer (188 MB), Metal | 29,9–30,7 s por minuto (0,51×), 1,95–2,5 GB. SDR igual a PyTorch (±0,02 dB) | Respaldo (exige integrar C++) |
| HTDemucs 6s (PyTorch MPS, sin convertir) | 3,5 s por minuto, 5,2–6,3 GB, 55 MB | Comparación de calidad; no se convierte |

## Calidad frente a la referencia real

SDR en dB frente a los stems reales del multitrack, BS-RoFormer (Core ML gridshift) / HTDemucs 6s.

| Tema | Guitarra | Bajo | Batería | Voz | Piano |
|---|---|---|---|---|---|
| T1 | 8,23 / 6,89 | 13,32 / 12,77 | 13,33 / 10,98 | 14,26 / 11,85 | — |
| T2 | 11,03 / 7,90 | 15,58 / 11,92 | 17,19 / 14,24 | 16,98 / 13,23 | — |
| T3 | 4,38 / 3,03 | 10,09 / 6,63 | 13,14 / 10,75 | 13,76 / 10,63 | 7,85 / 2,87 |

Guitarra de `sunnymeadsound`: 7,73 / 10,34 / 3,70 (T1 / T2 / T3). Tabla completa en `Probes/P4-modelos/bs_roformer_sw/out/results/sdr_table.csv` y `.json`.

Error = 10^(−SDR/10) de la energía del original; parecido = 100 − error. BS-RoFormer (gridshift):

| Stem | Error | Parecido |
|---|---|---|
| Guitarra T1 | 15 % | 85 % |
| Guitarra T2 | 7,9 % | 92 % |
| Guitarra T3 | 36 % | 64 % (se confunde con piano y sintetizadores) |
| Voz | 2–4 % | 96–98 % |
| Batería | 2–5 % | 95–98 % |
| Bajo | 3–10 % | 90–97 % |
| Piano T3 | 16 % | 84 % |

BS-RoFormer supera a HTDemucs en todos los stems y temas. La guitarra es el stem más débil y depende del tema.

Pruebas extra sobre la guitarra:

- Guitarra «por inversión» (mezcla menos la suma de los otros 5 stems): 8,22 / 10,93 / 4,23 dB. Igual o peor, porque los stems ya suman la mezcla (diferencia de −30 a −32 dB).
- Media de las guitarras de gridshift y HTDemucs: 8,21 / 10,07 / 4,24 dB. No mejora.
- Retención de memoria: modelo cargado una vez y T1 separado 3 veces en el mismo proceso, RSS 4,24 / 4,27 / 4,27 GB. Core ML no retiene memoria; lo que crecía antes era el script de medida al acumular temas.

Búsqueda de modelos dedicados a guitarra:

- BS-RoFormer SW lidera la tabla de guitarra de MVSep (9,05 dB).
- Candidatos sin métricas publicadas: MVSep Mega 53 guitarra (lumabeat, MIT, 77 MB, MLX) y `becruily/mel-band-roformer-guitar` (sin licencia).
- `htdemucs-6s-guitar-ft` mejora solo 0,3 dB sobre HTDemucs.
- Decidido por Jorge: se prueban en la Fase 4. Referencia a batir: BS-RoFormer SW con 8,23 / 11,03 / 4,38 dB de SDR en guitarra (T1 / T2 / T3).

## Escucha a ciegas

Guitarra, 30 s, igualada a −16 LUFS. Sin igualar, los separados sonaban 0,4–1 dB por debajo de la referencia.

| Tema | Preferencia de Jorge |
|---|---|
| T1 | Indiferente |
| T2 | BS-RoFormer |
| T3 | BS-RoFormer |

Nunca prefirió HTDemucs.

## Incidencias

- numpy 2.5 es incompatible con coremltools 9.0: se fijó numpy 2.3.5.
- La conversión propia a Core ML falló por un error del envoltorio (rango 6), no por operaciones no soportadas.
- El 4.º intento de conversión (trozo largo, compilación para Neural Engine) colgó el Mac; reinicio por watchdog a las 11:11.
- Compilar para Neural Engine con trozo largo no termina (`.all` abortado tras más de 3,5 min) y con trozo corto es más lento que la GPU.
- ONNX propio con trozo largo agota la memoria (hasta 48 GB).
- Los separados salen 0,4–1 dB por debajo de la referencia en nivel; la escucha se hizo igualada.

## Decisión

- Separación superada.
- Separador: BS-RoFormer SW, Core ML publicado de gridshift, unidades `CPU+GPU`.
- Neural Engine prohibido con este modelo: cuelga el Mac con trozo largo y es más lento con trozo corto.
- Respaldo: BSRoformer.cpp con GGUF q8_0 en Metal.
- HTDemucs no se convierte; el plan B no hace falta.
- Condición de paso «tema separado en local» cumplida: stems de T1 en `Probes/P4-modelos/bs_roformer_sw/out/stems/T1/`.

## Contrato del modelo elegido

Para `StemKit` (Fase 1).

| Aspecto | Valor |
|---|---|
| Audio | WAV estéreo, 44,1 kHz |
| Trozo | 588 800 muestras, 2 solapes (paso 294 400), fundido lineal del 10 % |
| Relleno de la canción | `reflect`, 294 400 muestras a cada lado |
| STFT | `n_fft` 2048, hop 512, Hann periódica, `center` con relleno `reflect`, 1025 bins |
| Entrada `spec` | `[1, 2050, 1151, 2]` float32. Canales intercalados por bin (índice 2·f + canal); re/im en el último eje |
| Salida `permute_97` | `[1, 6, 2050, 1151, 2]` FP16: máscara compleja |
| Postproceso (Swift) | Producto complejo con el espectro, bin 0 a cero, iSTFT y suma con solape |
| Orden de stems | bass, drums, other, vocals, guitar, piano |
| Tamaño | 353 MB (zip 328 MB) |

## Implicaciones para la Fase 1

- STFT e iSTFT en Swift con Accelerate.
- `MLModelConfiguration.computeUnits = .cpuAndGPU`.
- Procesar trozo a trozo escribiendo a disco.
- Caso de prueba: 3 temas seguidos sin que la memoria crezca más de ~200 MB por tema.
- Un tema de 4 min debe separarse en ~1,5 min.
- Fijar el origen de descarga del modelo (repo de gridshift) y comprobar el SHA-256 del zip: `faa91950a15ce4a4deb2692f367ec416dd6420e74cbfb490e851ded111208e7f`, según su manifest.
- La frecuencia de trabajo de 44,1 kHz es la nativa del modelo y la pedalera la admite (ver P2).

## Acordes (BTC)

Modelo: BTC de `jayg996/BTC-ISMIR19` (commit 2682317), pesos `test/btc_model_large_voca.pt` (170 acordes). Código MIT; los pesos son no comerciales según la spec: uso personal, no redistribuir.

Criterios aprobados: fidelidad frente a PyTorch ≥ 99 % de fotogramas, ≤ 15 s por tema, falla con más de 8 GB. Entrada principal: stems sin voz ni batería (suma de bass + guitar + other + piano de BS-RoFormer Core ML gridshift); comparativa: mezcla.

| Vía | Fidelidad (T1 / T2 / T3) | Tiempo por tema | Pico |
|---|---|---|---|
| PyTorch CPU | referencia | 1,1–1,4 s | 0,8–1,6 GB |
| Core ML FP16 GPU, stems | 99,95 / 100 / 99,97 % | 0,7–0,9 s | 0,8–1,6 GB |
| Core ML FP16 GPU, mezcla | 99,95 / 100 / 100 % | 0,7–0,9 s | 0,8–1,6 GB |
| Core ML FP16 ANE, stems | 99,90 / 99,96 / 99,84 % | 0,6–0,7 s (inferencia 13–19 ms) | 0,8–1,6 GB |
| Core ML FP16 ANE, mezcla | 100 / 99,93 / 100 % | 0,6–0,7 s | 0,8–1,6 GB |

El modelo pesa 6,2 MB y se convirtió a la primera; ONNX no hizo falta.

Stems frente a mezcla (PyTorch, informativo, sin cifrado de referencia): coinciden el 73,1 / 92,8 / 78,8 % de los fotogramas.

Incidencias:

- Código de 2019 con PyYAML 6, `np.float` y `torch.load` con `weights_only`: se arregló sin modificar el repo.
- Máscaras de atención `-inf` cambiadas a `-1e4` para FP16/ANE (en FP32 la diferencia es 0).

Decisión: Core ML FP16 en Neural Engine (modelo pequeño, deja la GPU a la separación). CPU+GPU es una alternativa equivalente.

Contrato para `ChordKit`:

| Aspecto | Valor |
|---|---|
| Entrada `cqt` | `[1, 108, 144]` f32 = (log(\|CQT\|+1e-6) − (−2,2279879)) / 1,7191329 |
| CQT | estilo librosa, 22 050 Hz mono, hop 2048, 144 bins, 24 por octava |
| Salida `logits` | `[1, 108, 170]`; argmax por fotograma |
| Ventana | 108 fotogramas (10 s; 0,0926 s por fotograma, 10,8 fps), sin solape; la última se rellena con ceros |
| Vocabulario | índice = raíz × 14 + calidad (min, maj, dim, aug, min6, maj6, min7, minmaj7, maj7, 7, dim7, hdim7, sus2, sus4); 168 = X, 169 = N |

Portar a Swift: suma de stems, mono y remuestreo 44,1 → 22,05 kHz; CQT compatible con librosa (lo único con trabajo real, validar contra librosa); normalización, relleno, argmax y escritura `.lab`.

Repetir: `Tools/py/.venv/bin/python Probes/P4-modelos/btc/run_all.py`.

## Pulso y batería

### Pulso (Beat This!)

Criterios: tempo dentro de ±1 BPM de T1 125, T2 74 y T3 110 (Readme de Cambridge MT); fidelidad ≥ 99 % de pulsos a ±20 ms frente a PyTorch; ≤ 10 s por tema; memoria < 8 GB; compases informativos.

Cambio de criterio aprobado por Jorge: el tempo se calcula con la media de los intervalos entre pulsos (dentro de ±20 % de la mediana), no con la mediana. A 50 fps la mediana avanza a saltos de 20 ms (27 tramas = 111,1 BPM, 28 = 107,1), así que a 110 BPM nunca cae en ±1. Con la mediana T3 daba 111,11: fallo de medida, no del modelo.

Modelo: Beat This! (`CPJKU/beat_this` commit b95c8ab, código y pesos MIT), checkpoint `final0`, postproceso oficial «minimal» (sin DBN). El servidor oficial de pesos dio HTTP 500; se usó `final0.ckpt` de los espejos `teamup-tech/Beat-This-weights` y `Audante/beat-this-final0`, con el mismo SHA-256 (8c328b45…8331).

El Core ML comunitario previsto (`schism-audio/beat-this-coreml`) no existe (401). Se usó `jessengatai/supracut-beat-this` (MIT, commit 33fe1a5): `BeatThis.mlmodelc` compilado de 79 MB del checkpoint `final0`, con diferencia de logits frente a PyTorch de 8,8e-5 como máximo. Jorge decidió usarlo en vez de una conversión propia, así que no hubo conversión ni ONNX. Corre en FP32 y sin ANE: el README avisa de que en FP16 la atención da ruido.

| Tema | Tempo (media) | Tempo (mediana) | Compases de 4 pulsos |
|---|---|---|---|
| T1 | 124,99 | 125,00 | 93 % |
| T2 | 74,00 | 73,17 | 99 % |
| T3 | 110,02 | 111,11 | 93 % |

Fidelidad de Core ML frente a PyTorch: 100 % en pulsos y en downbeats.

| Vía | Tiempo (T1 / T2 / T3) | Pico |
|---|---|---|
| PyTorch CPU | 2,55 / 3,36 / 3,69 s | 0,84–1,10 GB |
| Core ML | 0,46 / 0,60 / 0,67 s (+ 1,7–2,0 s de carga del modelo) | 1,06–1,26 GB |

Decisión: Beat This! `final0`, `mlmodelc` comunitario, CPU+GPU.

Contrato para `BeatKit`:

| Aspecto | Valor |
|---|---|
| Entrada `spect` | `[1, 1500, 128]` f32, tamaño fijo |
| Salidas | `beat` y `downbeat`, `[1, 1500]`, logits; 50 fps |
| Troceado | 1500 tramas (30 s), borde de 6: primer trozo con 6 de relleno a la izquierda, solape de 6, último trozo alineado al final; en el solape manda el anterior; por debajo de 30 s se rellena |
| Postproceso «minimal» | máximo local en ventana de 7, logit > 0, se funden picos adyacentes, downbeat al pulso más cercano |
| Preproceso | mono por media, 22 050 Hz, STFT 1024 hop 441 Hann centrada (`reflect`), módulo / sqrt(n_fft) = / 32, mel Slaney 128 bandas 30–11000 Hz sin normalizar, log1p(1000·x) |

El banco mel está en `musetric/beat-this-onnx/mel-filterbank.bin`.

Corrección de la Fase 2 (ADR-009): el módulo se divide por sqrt(n_fft) = 32, como el código oficial, no por sqrt(Σ win²) como decía esta tabla. Con el relleno a 1500 tramas, en los temas de menos de 30 s los pulsos coinciden en torno al 96 %.

Portar a Swift: remuestreo (`AVAudioConverter`), log-mel con vDSP, troceado, postproceso y tempo por media.

Repetir: `Tools/py/.venv/bin/python Probes/P4-modelos/beat_this/run_all.py` (`--all` prueba todas las vías). Las escuchas con clics están en `beat_this/out/listen/`; Jorge decidió no escucharlas, no hacía falta.

### Batería (ADTOF)

Criterios aprobados: F-measure a ±50 ms (`mir_eval`) frente a golpes de referencia sacados de las pistas sueltas de Cambridge MT. Falla si bombo o caja < 0,7 en T1; charles informativo; falla con más de 8 GB. La decisión final es de oído, de Jorge: bombo, caja y charles reconocibles en 30 s.

Modelo: ADTOF (Zehren et al.), puerto `xavriley/ADTOF-pytorch` commit 85c192e. El original es CC BY-NC-SA 4.0 (uso personal); el puerto no declara licencia: no redistribuir. Omnizart se descartó antes.

Referencia: pistas y stem alineados a 0 ms por correlación. Onsets en banda filtrada, fugas descartadas por nivel (valle del histograma por pista) y comparando con micros vecinos, con suelo de envolvente porque las pistas llevan puerta. La primera versión perdía unos 170 bombos en T1; se detectó y corrigió mirando la pista, no ajustando al modelo. Golpes bombo / caja / charles: T1 432 / 237 / 187, T2 281 / 107 / 320, T3 418 / 278 / – (T3 sin pista de charles). Plausibilidad: caja con moda de 2 golpes por compás, bombo 3–4, y 74–100 % de golpes sobre la rejilla de Beat This!.

Resultados P / R / F (Core ML idéntico a PyTorch):

| Tema | Bombo | Caja | Charles |
|---|---|---|---|
| T1 | 0,99 / 0,99 / 0,99 | 0,98 / 1,0 / 0,99 | 0,90 / 0,66 / 0,76 |
| T2 | 1,0 / 1,0 / 1,0 | 0,60 / 0,94 / 0,73 | 0,58 / 1,0 / 0,73 |
| T3 | 0,91 / 1,0 / 0,95 | 1,0 / 1,0 / 1,0 | sin medir |

T1 pasa. La caja de T2 es ambigua: 54 golpes quedan justo bajo el umbral de la referencia (probable aro o golpes suaves); contándolos, F = 0,90.

| Vía | Tiempo (T1 / T2 / T3) | Pico |
|---|---|---|
| PyTorch | 2,1 / 2,7 / 3,0 s | 3,6–5,6 GB |
| Core ML | 2,6 / 2,5 / 2,6 s (modelo 0,35 s en T1) | 1,2–1,7 GB |

Vía elegida: Core ML FP32 con GRU nativa de MIL (`gru_native.py`, requiere macOS 15), unidad `CPU_ONLY`, 1,8 MB. Fidelidad frente a PyTorch: 100 % de golpes a ±10 ms en las 5 clases y los 3 temas (diferencia de activación 5e-7). Descartes: la conversión estándar con la GRU en `while_loop` es 40–70× más lenta (52–143 s por tema); FP16 desvía la GRU (0,52 en GPU, 0,013 en CPU); la GPU calcula mal la GRU nativa, de ahí CPU. DrumSep no hizo falta (solo se probaba si ADTOF fallaba en caja o charles).

Contrato para `DrumKit`:

| Aspecto | Valor |
|---|---|
| Preproceso | mono 44,1 kHz; STFT 2048 hop 441 Hann (`np.hanning`), `center=True` con relleno constante; \|X\|[0:1024]; banco logarítmico estilo madmom (12 bandas por octava, 20 Hz–20 kHz, bins únicos, triangulares normalizados) → 84 bandas; log10(1+x) |
| Entrada `spec` | `[1, T, 84, 1]` f32, T entre 100 y 60 000, 100 fps |
| Salida `act` | `[1, T, 5]`, sigmoide; notas MIDI: bombo 35, caja 38, tom 47, charles 42, platos 49 |
| Picos | umbrales 0,22 / 0,24 / 0,32 / 0,22 / 0,30; media móvil (10 antes, 1 después) restada; máximo local (2 antes, 1 después); golpes a < 2 tramas se combinan |

Portar a Swift: STFT y banco de filtros (Accelerate), Core ML `.cpuOnly`, detector de picos (unas 40 líneas), exportación MIDI por el canal 10.

Escuchas: `adtof/out/listen/T{1,2,3}_{a_stem,b_render,c_overlay}.wav` (c: stem a la izquierda, render a la derecha), 30 s desde T1 1 s, T2 107 s y T3 243 s. Todas a −25,65 LUFS común: Jorge aprobó bajar todas por igual en vez de −16 LUFS, porque a −16 los picos llegaban a +8,6 dBFS (pico máximo ahora −1,0 dBFS). El render es de muestras sintetizadas y no incluye toms ni platos.

**Veredicto de oído de Jorge (15/11/2026): aprobado. Bombo, caja y charles reconocibles en T1–T3; fallan algunos platos, pero para un fichero Guitar Pro de estudio está perfecto.**

La duda de la caja de T2 (54 golpes bajo el umbral de la referencia) no cambia la decisión.

Repetir: `Tools/py/.venv/bin/python Probes/P4-modelos/adtof/run_all.py --convert`.

Entorno: `Tools/py/requirements.txt` fija ahora `soxr==1.1.0`, `mir_eval==0.8.2`, `pyloudnorm==0.1.1`, `future==1.0.0` y `mido==1.3.3` (aprobado por Jorge).

## Pendiente

- Fase 4: probar los modelos dedicados a guitarra (MVSep Mega 53 de lumabeat y `becruily/mel-band-roformer-guitar`) frente a BS-RoFormer SW (8,23 / 11,03 / 4,38 dB).
- Proveedor CoreML de ONNX Runtime, sin probar (reserva).

## Cómo repetirla

1. Tener los temas en `Probes/testaudio/` (ver su README) y el entorno `Tools/py/.venv` (Python 3.12, `Tools/py/requirements.txt`).
2. Scripts en `Probes/P4-modelos/{bs_roformer_sw,bsroformer_cpp,htdemucs,btc,beat_this,adtof,common}/`.
3. Usar siempre el vigilante de memoria `common/guard.py` (límite 10 GB), con un proceso por tema.
4. Resultados de separación en `Probes/P4-modelos/bs_roformer_sw/out/results/`; los de acordes, pulso y batería en `{btc,beat_this,adtof}/out/results/` (`.csv` y `.json`).
5. Acordes, pulso y batería: `Tools/py/.venv/bin/python Probes/P4-modelos/{btc,beat_this,adtof}/run_all.py` (batería con `--convert` la primera vez). Dependencias nuevas fijadas en `Tools/py/requirements.txt`.
6. Las stems de entrada de BTC salen de la separación de BS-RoFormer (paso 4).
