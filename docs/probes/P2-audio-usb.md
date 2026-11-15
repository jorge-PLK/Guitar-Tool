# P2 · Audio por USB con la HeadRush Flex Prime

Fecha: 2026-11-15 · Fase 0 · Rama `fase-0`

## Objetivo

Comprobar que la Flex Prime sirve como interfaz de audio de la Etapa 1 sin interfaz externa. Tres preguntas:

1. ¿Se puede grabar a la vez el DI seco y el procesado por USB?
2. ¿El backing enviado por USB llega a los auriculares sin volver contaminado en la grabación?
3. ¿El reamp por USB reproduce el tono en vivo, y con qué latencia?

## Montaje

- Mac: M3 Pro, macOS 26.6.2.
- Dispositivo: «HeadRush Flex Prime», class-compliant, sin driver en macOS. 4 entradas y 4 salidas USB.
- Firmware de la pedalera: 5.2.0 (confirmado por Jorge). Referencia: manual de usuario v5.2.0 (secciones 4.15.2, 4.15.3 y 4.19.7).
- Frecuencia: 48 kHz en la prueba. La pedalera admite 44,1 / 48 / 96 kHz (Global Settings → USB Audio). Para cambiarla: USB Audio Off, cambiar, On y reiniciar la app.
- Búfer: 512 muestras (rango 15–4096).
- Nombres de canal: los genéricos de macOS, no informativos.
- Herramienta: `Probes/P2-audio-usb/`, ejecutable `p2`. El guion está en su README o en el código.
- USB In Level de la pedalera: rango −60 a +12 dB.

## Enrutado

Según el manual v5.2.0 y confirmado con las medidas de abajo.

| Sentido | Canal | Contenido |
|---|---|---|
| Pedalera → Mac | ch1 / ch2 | Procesado L/R con todos los efectos |
| Pedalera → Mac | ch3 | DI seco, mono |
| Pedalera → Mac | ch4 | Copia de ch3 |
| Mac → pedalera | ch1 / ch2 | Directo a salidas principales y auriculares, sin pasar por el rig (aquí va el backing) |
| Mac → pedalera | ch3 | Entrada del rig, solo en USB Mode Reamp |
| Mac → pedalera | ch4 | Sin uso |

USB Mode:

| Modo | Comportamiento |
|---|---|
| Live | Al Mac y a las salidas |
| DAW | Solo al Mac, salidas apagadas |
| Reamp | Mac → rig → Mac, salidas apagadas |

## Resultados

| Prueba | Medida | Veredicto |
|---|---|---|
| Toma en vivo (Live, 20 s, rig con drive), ch1 | RMS −25,6 dBFS, pico −12,2 | Procesado |
| Toma en vivo, ch2 | RMS −26,6 dBFS, pico −12,9 | Procesado |
| Toma en vivo, ch3 y ch4 | RMS −31,6 dBFS, pico −9,2; factor de cresta 22,5 dB frente a 13,4 dB del procesado | ch3 es el DI seco |
| Correlación ch3–ch4 | 1,00 | Idénticos |
| Desfase procesado frente a DI | 85 muestras (1,8 ms) | Latencia del rig en vivo |
| Backing en el retorno (Live, barrido 20 Hz–20 kHz a −12 dBFS por USB 1/2, sin tocar), niveles en las 4 entradas respecto a lo enviado | −65,5 / −70,5 / −84,4 / −84,4 dB; barrido no detectado en ninguna; umbral −60 dB | El retorno USB no incluye el backing. Jorge confirmó que lo oyó en los auriculares |
| Latencia ida y vuelta (Reamp, rig limpio sin puerta, chirp por USB 3 → ch1, búfer 512, 10 repeticiones) | 2415,85 muestras = 50,33 ms, desviación 0,00 | Estable, pero declarada 1200 muestras (25 ms): la declarada no es fiable |
| Reamp (Reamp, rig con drive, DI de la toma en vivo por USB 3, 20 s), ch1 / ch2 | −25,6 / −12,2 y −26,6 / −12,9 dBFS (RMS / pico) | Mismos niveles que en vivo |
| Reamp, ch3 / ch4 | Copia de lo enviado | Esperado |
| Correlación procesado reamp frente a procesado en vivo | 1,00 | Rig determinista: el reamp reproduce exactamente el tono en vivo |
| Alineado del reamp | Se recortaron 55,33 ms (valor pasado a mano, no el medido). El cruce con la toma en vivo da 2358 muestras = 49,1 ms, frente a 50,3 ms con el rig limpio | La latencia varía ~1,2 ms según el rig |
| DI devuelto por ch3 en reamp | 2273 muestras (47,35 ms) tras el envío; el procesado, 85 muestras después | Coherente con la toma en vivo |
| Soak 5 min, 48 kHz, búfer 512 | 0 sobrecargas, 0 huecos, 28 125 callbacks | Estable |
| Deriva del reloj de la pedalera frente al del Mac | 26,08 ppm, residuo máx 0,06 ms | Medida; ver Fase 6 |
| Ruido en el soak | ch1/ch2 en cero digital (noise gate del rig); ch3 −65,1 dBFS, estable por minuto | Aceptable |

## Decisiones

- P2 superada.
- La Flex Prime sirve como interfaz de la Etapa 1 sin interfaz externa: DI seco y procesado por USB, backing por USB 1/2 a los auriculares sin contaminar el retorno, reamp por USB 3.
- No hace falta el plan B (backing por el Mac con mezcla externa).
- Primera mitad de la condición de paso de la Fase 0 cumplida: audio grabado por USB.

## Implicaciones para fases siguientes

- **Fase 1:** la frecuencia de trabajo está por decidir. La pedalera puede ir a 44,1 kHz, la nativa de los modelos de separación.
- **Fase 3:** calibrar la latencia con un pulso, porque la declarada no vale. El reamp debe alinearse midiendo en cada pasada o por correlación, no con una cifra fija (depende del rig). Grabar DI (ch3) y procesado (ch1/ch2) a la vez ya viene alineado internamente, salvo los 1,8 ms del rig.
- **Fase 6:** 26 ppm equivale a ~1 fotograma a 30 fps cada ~21 min al mezclar con el reloj de la cámara o del Mac.
- **Etapa 2:** el reamp por USB 3 hace innecesaria la caja de reamp.

## Cómo repetirla

1. Conectar la Flex Prime por USB y fijar 48 kHz y búfer 512 en la pedalera.
2. Poner USB Mode en Live para la toma en vivo y el backing, y en Reamp para la latencia y el reamp.
3. Ejecutar `p2` siguiendo el guion de `Probes/P2-audio-usb/`.
4. Anotar el firmware de la pedalera (en esta ejecución, 5.2.0).
