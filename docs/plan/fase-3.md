# Fase 3 · Audio con el dispositivo (RF1)

- [x] Selector de dispositivo de entrada y de salida y de canales (guitarra y backing), guardado en el perfil de equipo, sin nada cableado a la Flex Prime
- [x] Calibración de latencia con un pulso (bucle de cable)
- [x] Apartado Audio de Ajustes: dispositivos, canales, frecuencia de muestreo y calibración de latencia
- [x] Envío del backing al dispositivo elegido
- [x] Grabación de la señal procesada
- [x] Alinear la toma con el backing usando la latencia medida y el retardo del rig de cada toma
- [x] A/B de tu guitarra contra la original dentro de la mezcla (en directo y última toma)

Condición de paso: toma grabada alineada con el backing con error menor de 1 ms. *Cumplida el 15/11/2026 (0,010 ms en una toma de comprobación de 60 s recién calibrada, con `tf-audio verify`; ADR-013). Límite conocido: la latencia de la Flex Prime se acorta a escalones de 12 muestras (0,25 ms) que el HAL no refleja; Jorge lo acepta y no hay corrección.*

El DI (canal, nivel, DI seco) y el reamp salieron de esta fase el 15/11/2026 (ADR-012).
