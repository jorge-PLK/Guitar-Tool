# Ficha de pantalla · <Nombre>

Ola: <n>. Área del puente: `<prefijo>`. Destino: `FlutterApp/lib/features/<área>/`.

## 1. Qué es

Dos o tres frases: para qué sirve la pantalla y desde dónde se llega.

## 2. Referencia visual (SwiftUI)

| Elemento | Fichero:línea | Notas de composición |
| --- | --- | --- |

Medidas literales que haya en el código (anchos, altos, paddings, radios, tamaños de fuente) y tokens `TF.*` que usa cada elemento. Colores sueltos fuera de `TF` (hex y dónde).

## 3. Árbol de widgets propuesto

Lista jerárquica: widget Flutter → qué vista SwiftUI reproduce. Marcar los que son del kit compartido (`Tf…`) y los que necesitan `CustomPainter`.

## 4. Estados

Cada estado visible: vacío, cargando, con datos, error, deshabilitado, variantes (p. ej. grabando, punch armado). Para cada uno, qué cambia en pantalla y qué dato del núcleo lo decide.

## 5. Contrato que usa

| Acción del usuario o momento | Método / evento del puente | DTO (Swift, fichero:línea) | Cómo lo usa hoy `WinApp/Web` (fichero:línea) |
| --- | --- | --- | --- |

## 6. Interacción

Teclado (atajos, teclas modificadoras), arrastres, soltar ficheros, menús contextuales, foco. Lo que en SwiftUI depende de `NSEvent`, `.onDrag`, `.keyboardShortcut` o AppKit, con fichero:línea.

## 7. Hojas y popovers

Una subsección por hoja con los apartados 2 a 6 resumidos.

## 8. Textos

Tabla clave ARB propuesta → texto literal en español (copiado de SwiftUI, con fichero:línea). Incluir mensajes de error y de confirmación.

## 9. Desvíos detectados

Lo que SwiftUI hace y `AppCore` no ofrece, o hace distinto. Por cada uno: evidencia en SwiftUI (fichero:línea), qué falta en `AppCore`, y si es hueco claro (el comportamiento de SwiftUI lo define) o exige decisión de Jorge. Si no hay ninguno, decirlo.

## 10. Partes de trabajo sugeridas

Corte en encargos que no se pisen (un agente por parte): ficheros Dart que crea cada una, tamaño (S/M/L) y agente (`tf-flutter` Sonnet; `tf-flutter-mech` Haiku para lo mecánico).

## 11. Criterios de aceptación

Lista comprobable: capturas de referencia a igualar (estado → nombre del PNG), tests de store y de widgets que deben existir, y pasos manuales para Jorge si hay hardware o criterio de oído o vista.
