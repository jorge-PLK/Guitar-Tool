# Fase 1 · Base y biblioteca

- [x] Proyecto Xcode (macOS 15+), paquetes vacíos, permisos de cámara, micrófono y red local *`Tools/test.sh` verde.*
- [x] Modelo de datos: tema, stem, guitarra, sección, rig, toma, vídeo, perfil de equipo; guardado en un archivo por proyecto dentro de su carpeta, con SwiftData solo como índice de la biblioteca *`StoreTests`.*
- [x] Carpeta por proyecto en disco y limpieza de lo que se puede regenerar *`ProjectCleaner` en `StoreTests`.*
- [x] Importar WAV, FLAC o MP3 y convertir a la frecuencia de trabajo *`AudioImporterTests`.*
- [x] Descarga de modelos la primera vez y separación en 6 stems con progreso *`ModelStoreTests`, `HeavyModelTests` y la prueba en la app (ADR-007).*
- [x] Pantalla de biblioteca *Capturas revisadas por el orquestador.*
- [x] Sección de Ajustes en la barra lateral (icono de engranaje), con el apartado Biblioteca y equipo: carpeta de proyectos, modelos descargados, espacio en disco, limpieza y perfil de equipo *Capturas revisadas por el orquestador.*

Condición de paso: un tema importado y separado, con sus stems en disco. *Cumplida el 15/11/2026: T1 importado en la app y separado con un directorio de soporte vacío, 6 stems a 44,1 kHz en `Temp/p7/projects/mix/stems/` (ADR-007).*
