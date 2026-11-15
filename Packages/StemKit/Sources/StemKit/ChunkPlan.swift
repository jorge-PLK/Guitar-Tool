import Accelerate

/// Plan de trozos idéntico a `demix_np` de Probes/P4-modelos/bs_roformer_sw/sw_common.py
/// (que reproduce `utils.model_utils.demix` de MSST en modo generic):
/// - paso = trozo / solapes, fundido = trozo / 10, borde = trozo − paso;
/// - si la canción mide más de 2·borde, se rellena con reflect `borde` muestras por cada lado;
/// - trozos en 0, paso, 2·paso… mientras el inicio quede dentro de la señal rellenada;
/// - el último trozo incompleto se rellena con reflect si le quedan más de medio trozo, si no con ceros;
/// - fundido lineal de entrada y salida, salvo la entrada del primero y la salida del último.
struct ChunkPlan: Equatable {
    enum TailPad: Equatable { case none, reflect, zeros }

    let inputLength: Int
    let chunk: Int
    let step: Int
    let fade: Int
    let border: Int
    /// `inputLength > 2·border && border > 0`.
    let padded: Bool
    /// Longitud de la señal sobre la que se trocea (rellenada o no).
    let paddedLength: Int
    /// Inicio de cada trozo en coordenadas de la señal rellenada.
    let starts: [Int]

    init(inputLength: Int, chunk: Int = RoformerContract.chunk, overlaps: Int = RoformerContract.overlaps) {
        precondition(inputLength > 0 && chunk >= 10 && overlaps >= 1)
        self.inputLength = inputLength
        self.chunk = chunk
        step = chunk / overlaps
        fade = chunk / 10
        border = chunk - step
        padded = inputLength > 2 * border && border > 0
        paddedLength = padded ? inputLength + 2 * border : inputLength
        starts = Array(stride(from: 0, to: paddedLength, by: step))
    }

    var count: Int { starts.count }

    /// Muestras reales (sin relleno de cola) del trozo `k`.
    func validCount(_ k: Int) -> Int { min(chunk, paddedLength - starts[k]) }

    func tailPad(_ k: Int) -> TailPad {
        let n = validCount(k)
        if n == chunk { return .none }
        return n > chunk / 2 ? .reflect : .zeros
    }

    func isLast(_ k: Int) -> Bool { starts[k] + step >= paddedLength }

    /// Pesos del trozo `k` (longitud `chunk`), como `window_array` + los ajustes de los extremos.
    func weights(_ k: Int) -> [Float] {
        var w = [Float](repeating: 1, count: chunk)
        if fade > 0 {
            // np.linspace(0, 1, fade, dtype=float32): se calcula en Double y se convierte.
            let denom = Double(max(fade - 1, 1))
            for j in 0..<fade {
                let up = fade == 1 ? 0 : Float(Double(j) / denom)
                w[j] = up
                w[chunk - fade + j] = fade == 1 ? 1 : Float(1 - Double(j) / denom)
            }
            // linspace(1, 0) se calcula como 1 + j·(−1/(fade−1)); el último vale exactamente 0.
            if fade > 1 { w[chunk - 1] = 0 }
        }
        if starts[k] == 0 { for j in 0..<fade { w[j] = 1 } }
        if isLast(k) { for j in 0..<fade { w[chunk - fade + j] = 1 } }
        return w
    }

    /// Copia en `parts` (un búfer de `chunk` muestras por canal) el trozo `k` de la señal ya rellenada,
    /// aplicando el relleno de cola que toque.
    func fill(_ k: Int, from source: [UnsafePointer<Float>], into parts: [UnsafeMutablePointer<Float>]) {
        let i = starts[k], n = validCount(k), pad = chunk - n
        for (src, dst) in zip(source, parts) {
            dst.update(from: src + i, count: n)
            switch tailPad(k) {
            case .none: break
            case .zeros: (dst + n).update(repeating: 0, count: pad)
            case .reflect:
                // np.pad(part, (0, pad), "reflect"): dst[n + j] = dst[n − 2 − j]
                (dst + n).update(from: dst + (n - 1 - pad), count: pad)
                vDSP_vrvrs(dst + n, 1, vDSP_Length(pad))
            }
        }
    }
}

/// Suma con solape en streaming de la salida de los trozos (`result += y·w; counter += w`) y división
/// por la suma de pesos en cuanto un tramo queda completo. Con trozos en 0, paso, 2·paso…, al añadir el
/// trozo que empieza en `i` ya no llegará nada más a `[i, i + paso)`, así que ese tramo se entrega al
/// `sink` en coordenadas de la canción original (sin el borde de relleno). Solo guarda un trozo por canal.
final class OverlapAddAssembler {
    typealias Sink = (_ outputStart: Int, _ channels: [UnsafePointer<Float>], _ count: Int) throws -> Void

    let plan: ChunkPlan
    let channelCount: Int
    private let sink: Sink
    private var accum: [UnsafeMutablePointer<Float>]
    private let counter: UnsafeMutablePointer<Float>
    private var finished: [UnsafeMutablePointer<Float>]
    private let divisor: UnsafeMutablePointer<Float>
    private(set) var nextChunk = 0
    private(set) var emitted = 0

    init(plan: ChunkPlan, channelCount: Int, sink: @escaping Sink) {
        self.plan = plan
        self.channelCount = channelCount
        self.sink = sink
        func alloc(_ n: Int) -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: n)
            p.initialize(repeating: 0, count: n)
            return p
        }
        accum = (0..<channelCount).map { _ in alloc(plan.chunk) }
        finished = (0..<channelCount).map { _ in alloc(plan.chunk) }
        counter = alloc(plan.chunk)
        divisor = alloc(plan.chunk)
    }

    deinit {
        (accum + finished + [counter, divisor]).forEach { $0.deallocate() }
    }

    /// Añade la salida del trozo siguiente (`outputs[canal]`, `chunk` muestras cada uno).
    func add(_ outputs: [UnsafePointer<Float>]) throws {
        precondition(outputs.count == channelCount && nextChunk < plan.count)
        let k = nextChunk
        let i = plan.starts[k]
        let n = vDSP_Length(plan.validCount(k))
        let w = plan.weights(k)
        w.withUnsafeBufferPointer { wp in
            for ch in 0..<channelCount {
                vDSP_vma(outputs[ch], 1, wp.baseAddress!, 1, accum[ch], 1, accum[ch], 1, n)
            }
            vDSP_vadd(counter, 1, wp.baseAddress!, 1, counter, 1, n)
        }
        let last = plan.isLast(k)
        let count = last ? plan.paddedLength - i : plan.step
        // result /= counter; nan_to_num. Donde counter = 0 todas las contribuciones pesaron 0 → salida 0.
        for j in 0..<count { divisor[j] = counter[j] == 0 ? 1 : counter[j] }
        for ch in 0..<channelCount {
            vDSP_vdiv(divisor, 1, accum[ch], 1, finished[ch], 1, vDSP_Length(count))
        }
        // Tramo [i, i+count) de la señal rellenada → coordenadas de salida, recortado a [0, inputLength).
        let offset = plan.padded ? plan.border : 0
        let lo = max(i, offset), hi = min(i + count, offset + plan.inputLength)
        if hi > lo {
            let ptrs = finished.map { UnsafePointer($0 + (lo - i)) }
            try sink(lo - offset, ptrs, hi - lo)
            emitted += hi - lo
        }
        if !last {
            let keep = plan.chunk - plan.step
            for buf in accum + [counter] {
                buf.update(from: buf + plan.step, count: keep)
                (buf + keep).update(repeating: 0, count: plan.step)
            }
        }
        nextChunk += 1
    }
}
