import CoreGraphics
import Foundation

/// Geometría de los layouts (mini-spec Fase 7, tabla de «Layouts»), en unidades del lienzo con **origen arriba a la
/// izquierda**. Recuadros iguales, con `MontageStyle.margin` alrededor y `MontageStyle.gap` entre ellos; el orden es
/// el de las partes.
///
/// - `side`: una fila de columnas iguales.
/// - `grid`: 1 completo; 2 apilados con el tamaño de celda del 2 × 2 y centrados en horizontal (Jorge, 17/11/2026;
///   la tabla de la spec decía lado a lado); 3 dos arriba y uno centrado abajo; 4 en 2 × 2. Con más de 4 (la spec no
///   lo fija): `⌈√n⌉` columnas y la última fila centrada, que generaliza los casos 3 y 4.
/// - `stack`: una columna de filas iguales.
/// - `single`, `singleLandscape`: cada recuadro a pantalla completa, sin margen (en el plano único solo hay uno,
///   salvo en el fundido cruzado).
public enum MontageLayout {
    public static func rects(_ kind: MontageLayoutKind, count: Int, canvas: CGSize,
                             margin: Double = MontageStyle.margin, gap: Double = MontageStyle.gap) -> [CGRect] {
        guard count > 0 else { return [] }
        let inner = CGRect(x: margin, y: margin, width: canvas.width - 2 * margin, height: canvas.height - 2 * margin)
        switch kind {
        case .single, .singleLandscape:
            return Array(repeating: CGRect(origin: .zero, size: canvas), count: count)
        case .side:
            return grid(inner, columns: count, rows: 1, count: count, gap: gap)
        case .stack:
            return grid(inner, columns: 1, rows: count, count: count, gap: gap)
        case .grid where count == 2:
            // Apilados con el tamaño de celda del 2 × 2, centrados en horizontal (petición de Jorge del 17/11/2026):
            // las celdas de la columna izquierda del 2 × 2 desplazadas media celda a la derecha.
            let cells = grid(inner, columns: 2, rows: 2, count: 4, gap: gap)
            return [cells[0], cells[2]].map { $0.offsetBy(dx: inner.midX - $0.midX, dy: 0) }
        case .grid:
            let cols = Int(Double(count).squareRoot().rounded(.up))
            let rows = (count + cols - 1) / cols
            return grid(inner, columns: cols, rows: rows, count: count, gap: gap)
        }
    }

    /// `count` celdas por filas de `columns`; la última fila, si está incompleta, centrada.
    static func grid(_ r: CGRect, columns: Int, rows: Int, count: Int, gap: Double) -> [CGRect] {
        let w = (r.width - Double(columns - 1) * gap) / Double(columns)
        let h = (r.height - Double(rows - 1) * gap) / Double(rows)
        var out: [CGRect] = []
        for i in 0..<count {
            let row = i / columns, col = i % columns
            let inRow = min(columns, count - row * columns)
            let shift = Double(columns - inRow) * (w + gap) / 2
            out.append(CGRect(x: r.minX + shift + Double(col) * (w + gap), y: r.minY + Double(row) * (h + gap), width: w, height: h))
        }
        return out
    }
}
