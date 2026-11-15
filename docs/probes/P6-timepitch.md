# P6 · Time-stretch y transposición

Fecha: 2026-11-15 · Fase 0 · Rama `fase-0`

## Objetivo

Decidir qué motor de time-stretch y pitch-shift usa la app para velocidad 50–200 % y transposición. Pregunta: ¿`AVAudioUnitTimePitch` (Apple) suena lo bastante bien al 50 % frente a Rubber Band? Criterio aprobado: Apple se queda si al 50 % queda a ≤ 1 punto de Rubber Band en la escucha a ciegas.

## Montaje

- Mac: M3 Pro, macOS 26.6.2.
- Herramienta: `Probes/P6-timepitch/` (`run.sh`, `p6.py`, `AppleRender/`; README en esa carpeta).
- Motores:
  - `AVAudioUnitTimePitch` renderizado con `AVAudioEngine` en modo manual, overlap 8 (por defecto, `apple_o8`) y 32 (`apple_o32`).
  - Rubber Band 4.0.0 (brew) por CLI en modo tiempo real (`--realtime`), motores R2 (`rb_r2`) y R3 (`rb_r3`).
- Casos: 50 %, 70 % y +2 semitonos a velocidad 100 %.
- Tramos de 30 s, 44,1 kHz estéreo, de `Probes/testaudio/out/clips/` (ver `Probes/testaudio/README.md`):
  - `mix_dense`: T1, mezcla completa.
  - `backing_noguitar`: T1 sin guitarras.
  - `gtr_rhythm`: T1, stem de guitarras.
  - `gtr_lead`: T3 «The Elephant», ElecGtr3 desde 144,5 s. Repetitivo, pero Jorge lo dio por válido.
- Escucha a ciegas: ficheros A–D barajados por tramo (semilla fija). La clave está en `Probes/P6-timepitch/out/key.json`.
- Métricas: `Probes/P6-timepitch/out/metrics.json`.

## Resultados

### Escucha (Jorge, a ciegas)

- Al 50 % no encontró diferencias que le hicieran preferir ningún motor en ninguno de los 4 tramos.
- Favorito global: `mix-dense_p2_B`, que es Apple overlap 8 en el caso +2 st.
- Con +2 st todo suena más agudo y con menos cuerpo que el original. Es lo esperable al transponer sin conservar formantes; no es un fallo de la herramienta.

### Métricas al 50 %

Ataques: porcentaje frente al original. Ratio de picos: picos de onset detectados frente al original. CPU en segundos por segundo de audio.

| Tramo | Motor | Error de duración | Ataques % | Ratio de picos | CPU s/s |
|---|---|---|---|---|---|
| `backing_noguitar` | Apple o8 | 0,07 % | 51 | 0,96 | 0,0035 |
| `backing_noguitar` | Apple o32 | 0,07 % | 58 | 0,95 | 0,0131 |
| `backing_noguitar` | RB R2 | 0,00 % | 85 | 1,21 | 0,0114 |
| `backing_noguitar` | RB R3 | 0,00 % | 74 | 0,88 | 0,0473 |
| `gtr_lead` | Apple o8 | 0,05 % | 53 | 1,16 | 0,0028 |
| `gtr_lead` | Apple o32 | 0,05 % | 60 | 1,26 | 0,0103 |
| `gtr_lead` | RB R2 | 0,00 % | 69 | 1,68 | 0,0093 |
| `gtr_lead` | RB R3 | 0,00 % | 45 | 1,60 | 0,0368 |
| `gtr_rhythm` | Apple o8 | 0,19 % | 28 | 4,5 | 0,0031 |
| `gtr_rhythm` | Apple o32 | 0,17 % | 33 | 5,0 | 0,0119 |
| `gtr_rhythm` | RB R2 | 0,03 % | 33 | 19,8 | 0,0119 |
| `gtr_rhythm` | RB R3 | 0,03 % | 82 | 0,5 | 0,0470 |
| `mix_dense` | Apple o8 | 0,07 % | 56 | 0,98 | 0,0033 |
| `mix_dense` | Apple o32 | 0,07 % | 72 | 0,95 | 0,0127 |
| `mix_dense` | RB R2 | 0,00 % | 91 | 1,51 | 0,0138 |
| `mix_dense` | RB R3 | 0,00 % | 84 | 0,79 | 0,0509 |

Lectura:

- Duración: todos los motores quedan por debajo del 0,2 % de error en los 4 tramos.
- CPU: Apple o8 ronda 0,003 s por s de audio; Apple o32 y R2, ~0,01; R3, 0,04–0,05.
- RB R2 en `gtr_rhythm` genera ~20× picos de onset fantasma (19,8).
- Salvo en ese caso, los ratios de picos no separan los motores de forma consistente.

Advertencias sobre las métricas:

- La métrica de ataques baja al ralentizar aunque no haya fallo. Solo sirve para comparar motores entre sí, no como valor absoluto.
- La deriva de afinación medida sobre mezclas no es fiable. En `gtr_rhythm` el caso +2 st da −300 cents en todos los motores: es un artefacto de la medida.

### Equilibrio espectral al 50 %

Diferencia por banda frente al original, una vez igualado el nivel.

| Motor | Espectro | Estéreo |
|---|---|---|
| Apple o8 / o32 | Dentro de ±0,5 dB en todas las bandas (20 Hz–20 kHz) | Misma anchura |
| RB R3 | Pierde ~2–3 dB por encima de 2 kHz | Abre la imagen: lateral/central de −17 a −8 dB en `backing_noguitar` y de −11 a −6 dB en `mix_dense` |
| RB R2 | Pierde ~1–1,5 dB por encima de 2 kHz | Abre algo la imagen |

## Decisión

- P6 superada.
- Se queda `AVAudioUnitTimePitch` con overlap 8, conforme al criterio aprobado (≤ 1 punto de Rubber Band al 50 %).
- Motivos: calidad indistinguible a oído al 50 %, mejor equilibrio espectral y estéreo medidos, y el menor coste de CPU (~0,003 s por s de audio, frente a ~0,01 de Apple o32 y R2 y ~0,04–0,05 de R3).
- Rubber Band no entra en la app. Se evita la dependencia C++/GPL.

## Implicaciones para fases siguientes

- **Fase 2:** velocidad 50–200 % y transposición con `AVAudioEngine` + `AVAudioUnitTimePitch` (overlap 8).
- **Pendiente opcional (Fase 2):** si la transposición suena sin cuerpo, valorar Rubber Band con conservación de formantes solo para transponer, porque Apple no la ofrece.
- Los casos 70 % y +2 st no se puntuaron por separado. Se acordó puntuar solo el 50 % y ampliar si no bastara.

## Cómo repetirla

1. Instalar Rubber Band 4.0.0 (`brew install rubberband`; se usó en esta prueba, aunque no entra en la app) y tener los tramos en `Probes/testaudio/out/clips/`.
2. Ejecutar `Probes/P6-timepitch/run.sh Probes/testaudio/out/clips/*.wav` (ver su README). Genera los ficheros ciegos, `out/key.json` y `out/metrics.json`.
3. Escuchar los ficheros A–D de cada tramo sin mirar la clave y anotar preferencias.
4. Abrir `out/key.json` y comparar con las métricas.
