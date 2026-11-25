# Grabar · diferencias con la referencia SwiftUI

Las capturas de esta carpeta son de la app SwiftUI; las de Flutter salen de `--mock`. Estas son las diferencias visibles que se aceptan (Jorge, 25/11/2026, «me parece correcto»). Estados: `aceptada` · `aceptada sin ref`.

| Estado | Diferencia | Motivo | Aceptada por |
| --- | --- | --- | --- |
| aceptada | Títulos, partes y tomas distintos a los del proyecto de la referencia; la etiqueta de vídeo dice «640×360 · 30 fps» y no «1080p · 30 fps». | Los datos son los del `MockCore`; la etiqueta es el `label` del núcleo simulado. | Jorge, 25/11/2026 |
| aceptada | El medidor de entrada de guitarra está vacío. | El mock no emite señal. | Jorge, 25/11/2026 |
| aceptada | El mezclador con un solo canal deja un hueco debajo. | El mock trae un solo canal. | Jorge, 25/11/2026 |
| aceptada | El botón de toma lleva un chevron en Flutter y no en SwiftUI. | Diferencia de componente (`TfSecondaryButton`/botón de toma de Flutter). | Jorge, 25/11/2026 |
| aceptada sin ref | La hoja «Ajustar desfase» no tiene referencia válida: `desfase.png` es una copia de `preparado.png`. | No se capturó la hoja en SwiftUI. | Jorge, 25/11/2026 |
| aceptada | Falta la barra de scroll nativa de macOS. | Flutter pinta su propio scroll. | Jorge, 25/11/2026 |
| aceptada | Pie de la barra lateral con la tarjeta de dispositivo (ola 3) y la tarjeta de tema (ola 1). | Son de olas distintas; la referencia solo tiene la del dispositivo. | Jorge, 25/11/2026 |
| aceptada | El spinner de «preparado» se ve distinto según el retardo de captura. | El snapshot espera 2 s fijos; las capturas usan `--snapshot-delay 8`. | Jorge, 25/11/2026 |
| aceptada | Suavizado de texto distinto. | Motor de render de Flutter. | Jorge, 25/11/2026 |

## Cómo se rehace cada captura

Base: `--mock --screen record --state <x> --snapshot-delay 8`.

| Captura | Estado |
| --- | --- |
| `selector-temas.png` | selector sin proyecto (sin tema elegido) |
| `preparado.png` | `preparado` |
| `preparado-min.png` | `preparado-min`, a 1100 de ancho |
| `cuenta-atras.png` | `cuenta-atras` |
| `mezclador-expandido.png` | `--state mixer-expanded` |
| `desfase.png` | `--state adjusting` (sin referencia válida) |
