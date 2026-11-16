import AppKit
import Store
import StudyKit
import SwiftUI

/// Rejilla de acordes por compases (mini-spec Fase 2 §2 y «Ajustes de Jorge tras probar (P8)»).
struct ChordGridLayout {
    struct Cell {
        var time: Double
        var end: Double
        /// Posición en `effectiveChords` del tramo que suena en este pulso; nil si no hay ninguno.
        var chord: Int?
        /// `ChordLabel.index` sin transponer.
        var label: Int
        /// El acorde cambia respecto al pulso anterior.
        var isChange: Bool
    }

    struct Bar {
        var number: Int
        var start: Double
        var end: Double
        var cells: [Cell]
    }

    /// El acorde de un pulso se toma un poco después del pulso: los cambios detectados llegan algo tarde.
    static let probeFraction = 0.35

    var bars: [Bar]

    init?(grid: BeatGrid?, chords: [ChordSegment], duration: Double) {
        guard let grid, !grid.downbeats.isEmpty, !grid.beats.isEmpty else { return nil }
        let beats = grid.beats, downs = grid.downbeats
        let beatDur = grid.bpm.map { 60 / $0 } ?? 0.5
        var bars: [Bar] = []
        var j = 0
        var previous: Int?
        var chordPointer = 0
        for (n, start) in downs.enumerated() {
            let end = n + 1 < downs.count ? downs[n + 1] : max(beats.last! + beatDur, start + beatDur)
            while j < beats.count, beats[j] < start - 1e-6 { j += 1 }
            var times: [Double] = []
            while j < beats.count, beats[j] < end - 1e-6 { times.append(beats[j]); j += 1 }
            guard !times.isEmpty else { continue }
            var cells: [Cell] = []
            for (k, t) in times.enumerated() {
                let e = k + 1 < times.count ? times[k + 1] : end
                let probe = t + Self.probeFraction * (e - t)
                while chordPointer + 1 < chords.count, chords[chordPointer + 1].start <= probe { chordPointer += 1 }
                var seg: Int?
                if chordPointer < chords.count, chords[chordPointer].start <= probe, probe < chords[chordPointer].end {
                    seg = chordPointer
                }
                let label = seg.map { chords[$0].index } ?? ChordLabel.noChordIndex
                cells.append(Cell(time: t, end: e, chord: seg, label: label, isChange: label != previous))
                previous = label
            }
            bars.append(Bar(number: n + 1, start: start, end: end, cells: cells))
        }
        guard !bars.isEmpty else { return nil }
        self.bars = bars
    }

    /// Índice del compás que contiene `time` (el primero antes de empezar).
    func barIndex(at time: Double) -> Int {
        var lo = 0, hi = bars.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if bars[mid].start <= time + 1e-6 { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    func rows(perRow n: Int) -> [[Bar]] {
        stride(from: 0, to: bars.count, by: n).map { Array(bars[$0..<min($0 + n, bars.count)]) }
    }
}

/// Medidas de la rejilla, compartidas por el dibujo y por el hit-test (una sola fuente de verdad).
/// Todo en el espacio de coordenadas "grid" (el contenido del ScrollView, con origen en su esquina superior izquierda).
struct ChordGridGeometry {
    let width: CGFloat
    let perRow: Int

    var barWidth: CGFloat { (width - ChordGridView.labelWidth) / CGFloat(perRow) }
    /// Ancho dibujado de un compás (sin el hueco de la derecha).
    var drawnBarWidth: CGFloat { barWidth - ChordGridView.barGap }
    var rowPitch: CGFloat { ChordGridView.sectionGutter + ChordGridView.rowHeight + ChordGridView.rowSpacing }

    func cellFrame(row: Int, col: Int, beat: Int, beatCount: Int) -> CGRect {
        let w = drawnBarWidth / CGFloat(beatCount)
        return CGRect(x: ChordGridView.labelWidth + CGFloat(col) * barWidth + CGFloat(beat) * w,
                      y: CGFloat(row) * rowPitch + ChordGridView.sectionGutter, width: w, height: ChordGridView.rowHeight)
    }

    /// Punto → (fila, compás dentro de la fila, pulso dentro del compás). Fuera de la rejilla se ajusta al más cercano.
    func hit(_ p: CGPoint, rows: [[ChordGridLayout.Bar]]) -> (row: Int, col: Int, beat: Int)? {
        guard !rows.isEmpty else { return nil }
        let r = min(max(Int((p.y / rowPitch).rounded(.down)), 0), rows.count - 1)
        let x = max(p.x - ChordGridView.labelWidth, 0)
        let col = min(max(Int((x / barWidth).rounded(.down)), 0), rows[r].count - 1)
        let n = rows[r][col].cells.count
        let frac = min(max((x - CGFloat(col) * barWidth) / drawnBarWidth, 0), 0.999_999)
        return (r, col, min(Int(frac * CGFloat(n)), n - 1))
    }
}

/// Posición medida de cada celda de la rejilla (clave: tiempo del pulso), para la comprobación DEBUG.
struct GridCellFrames: PreferenceKey {
    static var defaultValue: [Double: CGRect] { [:] }
    static func reduce(value: inout [Double: CGRect], nextValue: () -> [Double: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Rejilla expandida: filas de 4 compases (8 si cabe el ancho), con autoscroll al compás actual.
struct ChordGridView: View {
    let session: StudySession
    let ctl: BackingController
    let time: Double
    let edit: Bool
    let shown: (Int) -> ChordLabel
    @Binding var editing: Double?
    let selection: SectionSelection
    @Environment(AppModel.self) private var model

    @State private var measured: [Double: CGRect] = [:]
    @State private var layout: ChordGridLayout?
    @State private var dragRange: ClosedRange<Double>?

    static let labelWidth: CGFloat = 84
    static let rowHeight: CGFloat = 46
    static let rowSpacing: CGFloat = 4
    /// Franja sobre cada fila para el nombre de las cajas de sección (mini-spec Fase 4, «Interfaz»).
    static let sectionGutter: CGFloat = 18
    static let barGap: CGFloat = 4
    /// Ancho mínimo de un compás para pasar de 4 a 8 por fila.
    static let minBarWidthFor8: CGFloat = 112
    static let visibleRows: CGFloat = 4
    /// Un clic es un gesto que se mueve menos de esto (puntos).
    static let clickSlop: CGFloat = 4
    static var height: CGFloat { visibleRows * (sectionGutter + rowHeight) + (visibleRows - 1) * rowSpacing }

    private var chords: [ChordSegment] { session.effectiveChords }

    var body: some View {
        GeometryReader { geo in
            let perRow = (geo.size.width - Self.labelWidth) / 8 >= Self.minBarWidthFor8 ? 8 : 4
            let width = geo.size.width
            if let layout {
                let rows = layout.rows(perRow: perRow)
                let currentBar = layout.barIndex(at: time)
                let currentRow = currentBar / perRow
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: Self.rowSpacing) {
                            ForEach(rows.indices, id: \.self) { r in
                                row(rows[r], width: width, perRow: perRow).id(r)
                            }
                        }
                        .frame(width: width)
                        .overlay(alignment: .topLeading) {
                            GridSectionBoxes(session: session, ctl: ctl, rows: rows,
                                             geometry: ChordGridGeometry(width: width, perRow: perRow), selection: selection)
                        }
                        .coordinateSpace(name: "grid")
                        .contentShape(Rectangle())
                        .gesture(dragGesture(rows: rows, geometry: ChordGridGeometry(width: width, perRow: perRow)),
                                 including: edit ? .subviews : .all)
                    }
                    .onChange(of: currentRow) { _, r in withAnimation { proxy.scrollTo(r, anchor: .center) } }
                    .onChange(of: perRow) { _, _ in proxy.scrollTo(currentBar / perRow, anchor: .center) }
                    .onAppear { proxy.scrollTo(currentRow, anchor: .center) }
                    .onPreferenceChange(GridCellFrames.self) { measured = $0 }
                    #if DEBUG
                    .task {
                        guard model.options.gridHitSelftest else { return }
                        try? await Task.sleep(for: .seconds(2.5))
                        selfTest(rows: rows, geometry: ChordGridGeometry(width: width, perRow: perRow))
                    }
                    #endif
                }
            } else {
                Text("Sin rejilla de compases todavía.").font(TF.body(13)).foregroundStyle(TF.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: Self.height)
        .onAppear(perform: rebuild)
        .onChange(of: session.effectiveChords) { rebuild() }
        .onChange(of: session.beats) { rebuild() }
    }

    private func rebuild() {
        layout = ChordGridLayout(grid: session.beats, chords: chords, duration: ctl.duration)
    }

    // MARK: Filas

    private func row(_ bars: [ChordGridLayout.Bar], width: CGFloat, perRow: Int) -> some View {
        let barWidth = (width - Self.labelWidth) / CGFloat(perRow)
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("c. \(bars.first?.number ?? 0)").font(TF.body(11)).foregroundStyle(TF.muted)
            }
            .frame(width: Self.labelWidth - 8, alignment: .leading)
            .padding(.trailing, 8)
            ForEach(bars, id: \.number) { bar in barView(bar, width: barWidth - Self.barGap) }
                .padding(.trailing, Self.barGap)
            Spacer(minLength: 0)
        }
        .frame(height: Self.rowHeight)
        .padding(.top, Self.sectionGutter)
    }

    private func barView(_ bar: ChordGridLayout.Bar, width: CGFloat) -> some View {
        let isCurrent = bar.start <= time + 1e-6 && time < bar.end
        let cellWidth = width / CGFloat(bar.cells.count)
        return HStack(spacing: 0) {
            ForEach(bar.cells.indices, id: \.self) { k in cellView(bar.cells[k], first: k == 0, width: cellWidth, current: isCurrent && bar.cells[k].time <= time + 1e-6 && time < bar.cells[k].end) }
        }
        .frame(width: width, height: Self.rowHeight)
        .background(isCurrent ? TF.accentBg : TF.field, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isCurrent ? TF.accent : TF.fieldLine))
    }

    @ViewBuilder
    private func cellView(_ c: ChordGridLayout.Cell, first: Bool, width: CGFloat, current: Bool) -> some View {
        let l = dragRange ?? ctl.loop
        let inLoop = l.map { ($0.lowerBound...$0.upperBound).contains((c.time + c.end) / 2) } ?? false
        let isChord = ChordLabel(index: c.label)?.isChord == true
        // Convención de cancionero: el pulso 1 de cada compás lleva siempre el acorde que suena; el resto, solo si cambia.
        let named = first || c.isChange
        let content = Text(named ? shown(c.label).name : "·")
            .font(TF.body(named ? 14 : 13, named ? .bold : .regular))
            .foregroundStyle(named && isChord ? TF.text : TF.muted)
            .lineLimit(1).minimumScaleFactor(0.6)
            .padding(.leading, named ? 6 : 0)
            .frame(width: width, height: Self.rowHeight - 6, alignment: named ? .leading : .center)
            .background(inLoop ? TF.accent.opacity(0.28) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .bottom) {
                if current { Capsule().fill(TF.accent).frame(width: max(width - 8, 4), height: 3) }
            }
            .padding(.vertical, 3)
            .background(GeometryReader { g in
                Color.clear.preference(key: GridCellFrames.self, value: [c.time: g.frame(in: .named("grid"))])
            })
        if edit, let seg = c.chord {
            Button { editing = c.time } label: { content }
                .buttonStyle(.plain)
                .popover(isPresented: Binding(get: { editing == c.time }, set: { if !$0 { editing = nil } })) {
                    ChordEditor(session: session, ctl: ctl, segment: chords[seg], time: c.time)
                }
        } else {
            content
        }
    }

    // MARK: Gestos (fuera del modo edición)

    private func range(_ a: ChordGridLayout.Cell, _ b: ChordGridLayout.Cell) -> ClosedRange<Double> {
        let lo = a.time <= b.time ? a : b, hi = a.time <= b.time ? b : a
        return lo.time...hi.end
    }

    private func cell(_ h: (row: Int, col: Int, beat: Int)?, rows: [[ChordGridLayout.Bar]]) -> ChordGridLayout.Cell? {
        h.map { rows[$0.row][$0.col].cells[$0.beat] }
    }

    /// Clic = saltar al pulso donde se ha pulsado; arrastre = bucle con imán al pulso (⌥ = al compás).
    private func dragGesture(rows: [[ChordGridLayout.Bar]], geometry g: ChordGridGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("grid"))
            .onChanged { v in
                guard hypot(v.translation.width, v.translation.height) >= Self.clickSlop,
                      let a = cell(g.hit(v.startLocation, rows: rows), rows: rows),
                      let b = cell(g.hit(v.location, rows: rows), rows: rows) else { return }
                dragRange = range(a, b)
            }
            .onEnded { v in
                dragRange = nil
                selection.clear()
                guard let a = cell(g.hit(v.startLocation, rows: rows), rows: rows),
                      let b = cell(g.hit(v.location, rows: rows), rows: rows) else { return }
                if hypot(v.translation.width, v.translation.height) < Self.clickSlop {
                    ctl.seek(to: a.time)
                } else {
                    let bar = NSEvent.modifierFlags.contains(.option)
                    ctl.setLoop(StudyBridge.snap(session.beats, range(a, b), bar: bar), name: bar ? "compases" : "acordes")
                }
            }
    }

    #if DEBUG
    /// `--grid-hit-selftest`: compara la posición medida de cada celda visible con la calculada y comprueba que
    /// el hit-test devuelve esa celda en su centro y a 0,5 pt de sus bordes.
    private func selfTest(rows: [[ChordGridLayout.Bar]], geometry g: ChordGridGeometry) {
        var fails: [String] = []
        for (time, m) in measured {
            var found: (Int, Int, Int, Int)?
            for (r, row) in rows.enumerated() {
                for (c, bar) in row.enumerated() {
                    if let k = bar.cells.firstIndex(where: { $0.time == time }) { found = (r, c, k, bar.cells.count) }
                }
            }
            guard let (r, c, k, n) = found else { fails.append("celda \(time) sin sitio en la rejilla"); continue }
            let f = g.cellFrame(row: r, col: c, beat: k, beatCount: n)
            if abs(f.minX - m.minX) > 0.6 || abs(f.minY - m.minY) > 0.6 || abs(f.width - m.width) > 0.6 || abs(f.height - m.height) > 0.6 {
                fails.append("medidas \(r),\(c),\(k): dibujada \(m) calculada \(f)")
            }
            for p in [CGPoint(x: m.midX, y: m.midY), CGPoint(x: m.minX + 0.5, y: m.midY), CGPoint(x: m.maxX - 0.5, y: m.midY),
                      CGPoint(x: m.midX, y: m.minY + 0.5), CGPoint(x: m.midX, y: m.maxY - 0.5)] {
                if let h = g.hit(p, rows: rows), (h.row, h.col, h.beat) == (r, c, k) { continue }
                fails.append("hit \(p) esperaba \(r),\(c),\(k)")
            }
        }
        DebugLog.append("rejilla: \(measured.count) celdas visibles, \(rows.count) filas de \(g.perRow) compases, ancho \(g.width); fallos: \(fails.count)\n"
                        + fails.prefix(10).joined(separator: "\n"))
    }
    #endif
}

#if DEBUG
enum DebugLog {
    static func append(_ text: String) {
        let url = URL(fileURLWithPath: "Temp/p8/grid-hit.txt")
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (old + text + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
#endif

/// Posición de cada acorde de la tira plegada, para saber sobre cuál se arrastra.
struct StripFrames: PreferenceKey {
    static var defaultValue: [Int: CGRect] { [:] }
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
