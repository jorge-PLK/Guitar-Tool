# Montaje · diferencias con la referencia SwiftUI

Las capturas de esta carpeta son de la app SwiftUI; las de Flutter salen de `--mock` (`--screen montage [--state <x>] --project 00000000-0000-0000-0000-000000000001`). Estas son las diferencias visibles que se aceptan (orquestador, 27/11/2026, a falta del visto bueno de Jorge). Estados: `aceptada` · `aceptada sin ref`.

| Estado | Diferencia | Motivo | Aceptada por |
| --- | --- | --- | --- |
| aceptada | Las casillas de exportación van en accent; en SwiftUI son grises. | Componente del kit `TfCheckbox`. | orquestador, 27/11/2026 |
| aceptada | Los pickers de menú del kit son algo más bajos y con un chevron menor que el de macOS. | Componente del kit. | orquestador, 27/11/2026 |
| aceptada | Los iconos `.fill` (play, check de «exportado») se dibujan con trazo. | Decisión de `docs/flutter/decisiones-interfaz.md`, «Iconos: trazo o relleno». | orquestador, 27/11/2026 |
| aceptada | El deslizador de la hoja «Encuadre» tiene el tramo en accent; en SwiftUI es gris. | Componente del kit `TfSlider`. | orquestador, 27/11/2026 |
| aceptada | Las capturas no llevan barra de título y la vista previa está vacía (negra). | `--mock` no entrega fotogramas. | orquestador, 27/11/2026 |
| aceptada | La «→» del popover «Transiciones» sale como un cuadro en el golden. | Fuente de test sin ese glifo. Pendiente de comprobar en la app real. | orquestador, 27/11/2026 |
| aceptada | La lista de temas del selector va ordenada por título, como la Biblioteca de Flutter; SwiftUI la ordena por `createdAt` descendente (`AppModel.swift:520`). | `library.list` no trae un `createdAt` ordenable. | orquestador, 27/11/2026 |
| aceptada | El porcentaje de la banda «Exportando» queda a la derecha de la barra de 320, aunque el tramo vacío no se vea. | 1:1 con `MontageView.swift:172-176`. | orquestador, 27/11/2026 |
| aceptada | Las opciones de exportación (MO12) vienen de `export.options`: enseña la resolución guardada aunque no esté en la lista y en Windows solo ofrece H.264. | Mejora respecto a SwiftUI; ver MO12 en `docs/flutter/desvios.md`. | Jorge, 27/11/2026 |
| aceptada sin ref | Faltan las referencias de exportando, exportado, fallo, `encuadre-seguir` y `corte-menu`. Se validan contra la ficha y la captura vecina; las sustituyen los goldens `montage_screen_*`, `encuadre-*` y `montage_cut_menu`. | No se capturaron en SwiftUI. | Jorge, 27/11/2026 |

Nota: `sin-tomas.png` está mal nombrada. Es un estado listo con 3 carriles y vídeos de color. El estado «sin tomas» se valida contra la ficha (`MontageView.swift:225-236`).
