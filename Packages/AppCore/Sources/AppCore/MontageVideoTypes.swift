import VideoKit

// `VideoKit` y `AudioKit` definen cada uno su `MontageSpan`, y `VideoKit` y `Store` su `MontageLayoutKind`; además el
// enum `VideoKit` tapa el nombre del módulo. Estos alias viven en un fichero que solo importa VideoKit para poder
// nombrar sus tipos sin ambigüedad desde los ficheros que importan los tres (mismo truco que `StudyBridge`).
typealias VideoSpan = MontageSpan
typealias VideoLayoutKind = MontageLayoutKind
