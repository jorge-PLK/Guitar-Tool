# Ajustes · diferencias con la referencia SwiftUI

Biblioteca e Idioma: ver ola 1.

## Audio y vídeo (ola 3)

Aceptadas por Jorge el 25/11/2026 («me parece correcto»).

| Estado | Diferencia | Motivo | Aceptada por |
| --- | --- | --- | --- |
| aceptada | Los controles nativos (checkbox, slider, switch) salen grises en la referencia. | La ventana estaba inactiva al capturar. | Jorge, 25/11/2026 |
| aceptada | `TfSegmented` seleccionado en naranja; en macOS es gris nativo. | Diferencia de componente. | Jorge, 25/11/2026 |
| aceptada | `audio-sin-calibrar.png` muestra en realidad el estado desconectado. | La referencia se capturó con `--state disconnected`; no hay captura de «sin calibrar». | Jorge, 25/11/2026 |

## Cómo se rehace cada captura

| Captura | Comando |
| --- | --- |
| `audio-calibracion.png` | `--mock --screen calibration-sheet --state success` |
| `video-simulada.png` | `--mock --screen settings` con `--state simulated` (pestaña Vídeo) |
| `audio-dispositivos.png` | pestaña Audio, estado por defecto |
| `audio-sin-calibrar.png` | pestaña Audio con `--state disconnected` |

Todas con `--snapshot-delay 8` si hay spinner. `biblioteca.png` es de la ola 1.
