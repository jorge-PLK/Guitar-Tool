import CoreGraphics
import CryptoKit
import Foundation

/// Articulaciones que delimitan la guitarra (mini-spec Fase 7, «Encuadre»: muñecas, codos y torso).
public enum PoseJoint: String, Codable, Sendable, CaseIterable {
    case leftWrist, rightWrist, leftElbow, rightElbow, leftShoulder, rightShoulder, neck, root, leftHip, rightHip

    var isArm: Bool { [.leftWrist, .rightWrist, .leftElbow, .rightElbow].contains(self) }
}

/// Punto normalizado (0…1, origen arriba a la izquierda).
public struct PosePoint: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Pose de un fotograma muestreado: solo las articulaciones con confianza suficiente (vacía: sin persona).
public struct PoseSample: Codable, Sendable, Equatable {
    public var time: Double
    public var joints: [PoseJoint: PosePoint]

    public init(time: Double, joints: [PoseJoint: PosePoint]) {
        self.time = time
        self.joints = joints
    }
}

/// Encuadre automático de la guitarra (mini-spec Fase 7, «Encuadre»). Esta parte es pura (de poses a caja,
/// suavizado, recorte); la que llama a Vision está en `GuitarFramer+Vision.swift`.
public enum GuitarFramer {
    /// Intervalo de muestreo de la toma (decisión propia: 4 fotogramas por segundo bastan para una caja suavizada).
    public static let defaultInterval = 0.25
    /// Confianza mínima de una articulación de Vision (decisión propia).
    public static let minConfidence: Float = 0.3
    /// Margen alrededor de las articulaciones, en fracción del ancho y del alto de la caja por cada lado
    /// (decisión propia: «con margen» en la spec).
    public static let boxMargin = 0.15
    /// Mínimo de articulaciones, con al menos una del brazo, para dar caja (decisión propia).
    public static let minJoints = 3
    /// Filtro de mediana (muestras) contra detecciones sueltas y sigma (s) del suavizado gaussiano sin desfase
    /// (decisión propia: «sin temblor ni saltos»).
    public static let medianWindow = 5
    public static let smoothingSigma = 0.5

    /// Caja de la guitarra para una pose: el rectángulo de muñecas, codos y torso más el margen, dentro del fotograma.
    public static func box(joints: [PoseJoint: PosePoint]) -> FramingBox? {
        let pts = Array(joints.values)
        guard pts.count >= minJoints, joints.keys.contains(where: \.isArm) else { return nil }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        let x0 = xs.min()!, x1 = xs.max()!, y0 = ys.min()!, y1 = ys.max()!
        let mx = (x1 - x0) * boxMargin, my = (y1 - y0) * boxMargin
        let a = max(0, x0 - mx), b = min(1, x1 + mx), c = max(0, y0 - my), d = min(1, y1 + my)
        guard b > a, d > c else { return nil }
        return FramingBox(x: a, y: c, width: b - a, height: d - c)
    }

    /// Análisis de una toma a partir de sus poses muestreadas (en orden de tiempo).
    /// - Fija: mediana de cada borde de las cajas detectadas.
    /// - Trayectoria: centro y tamaño por muestra; los huecos se interpolan (los extremos repiten la detección más
    ///   cercana), una mediana de `medianWindow` quita las detecciones sueltas y un gaussiano sin desfase de sigma
    ///   `smoothingSigma` quita el temblor.
    public static func analyze(samples: [PoseSample], frameWidth: Int, frameHeight: Int, fingerprint: String) -> FramingAnalysis {
        let sorted = samples.sorted { $0.time < $1.time }
        let boxes = sorted.map { box(joints: $0.joints) }
        let found = boxes.compactMap { $0 }
        guard !found.isEmpty else {
            return FramingAnalysis(fingerprint: fingerprint, frameWidth: frameWidth, frameHeight: frameHeight, samples: sorted.count,
                                   detected: 0, fixed: nil, track: [])
        }
        func median(_ v: [Double]) -> Double {
            let s = v.sorted()
            return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
        }
        let l = median(found.map(\.x)), t = median(found.map(\.y))
        let r = median(found.map { $0.x + $0.width }), b = median(found.map { $0.y + $0.height })
        let fixed = FramingBox(x: l, y: t, width: r - l, height: b - t)

        let times = sorted.map(\.time)
        // Canales: centro x, centro y, ancho, alto.
        var channels: [[Double?]] = [boxes.map { $0?.midX }, boxes.map { $0?.midY }, boxes.map { $0?.width }, boxes.map { $0?.height }]
        channels = channels.map { fillGaps($0, times: times).map { Optional($0) } }
        let smooth = channels.map { gaussian(medianFilter($0.map { $0! }, window: medianWindow), times: times, sigma: smoothingSigma) }
        var track: [FramingKey] = []
        for i in times.indices {
            let w = smooth[2][i], h = smooth[3][i]
            track.append(FramingKey(time: times[i], box: FramingBox(x: smooth[0][i] - w / 2, y: smooth[1][i] - h / 2, width: w, height: h)))
        }
        return FramingAnalysis(fingerprint: fingerprint, frameWidth: frameWidth, frameHeight: frameHeight, samples: sorted.count,
                               detected: found.count, fixed: fixed, track: track)
    }

    /// Huecos (`nil`) interpolados linealmente en el tiempo; antes de la primera y tras la última detección, su valor.
    static func fillGaps(_ v: [Double?], times: [Double]) -> [Double] {
        let known = v.indices.filter { v[$0] != nil }
        guard let first = known.first, let last = known.last else { return v.map { _ in 0 } }
        var out = [Double](repeating: 0, count: v.count)
        var k = 0
        for i in v.indices {
            if let x = v[i] { out[i] = x; continue }
            if i < first { out[i] = v[first]!; continue }
            if i > last { out[i] = v[last]!; continue }
            while k + 1 < known.count && known[k + 1] < i { k += 1 }
            let a = known[k], b = known[k + 1]
            let u = (times[i] - times[a]) / max(1e-12, times[b] - times[a])
            out[i] = v[a]! + (v[b]! - v[a]!) * u
        }
        return out
    }

    static func medianFilter(_ v: [Double], window: Int) -> [Double] {
        let h = window / 2
        guard h > 0, v.count > 2 else { return v }
        return v.indices.map { i in
            let s = v[max(0, i - h)...min(v.count - 1, i + h)].sorted()
            return s[s.count / 2]
        }
    }

    /// Gaussiano sin desfase con pesos por distancia en el tiempo (vale con muestras irregulares).
    static func gaussian(_ v: [Double], times: [Double], sigma: Double) -> [Double] {
        guard sigma > 0, v.count > 1 else { return v }
        let reach = 3 * sigma
        var lo = 0
        return v.indices.map { i in
            while times[i] - times[lo] > reach { lo += 1 }
            var sum = 0.0, wsum = 0.0
            var j = lo
            while j < v.count && times[j] - times[i] <= reach {
                let d = times[j] - times[i]
                let w = exp(-d * d / (2 * sigma * sigma))
                sum += w * v[j]
                wsum += w
                j += 1
            }
            return sum / wsum
        }
    }

    /// Recorte de un recuadro (normalizado): la caja ampliada a la proporción `aspect` (ancho/alto, en píxeles) sin
    /// salirse del fotograma; si no cabe, la mayor de esa proporción, centrada en la caja hasta donde se pueda.
    /// Sin caja: el fotograma entero, centrado (mini-spec, «Encuadre»).
    public static func crop(box: FramingBox?, frameSize: CGSize, aspect: Double) -> FramingBox {
        let W = Double(frameSize.width), H = Double(frameSize.height)
        guard W > 0, H > 0, aspect > 0, aspect.isFinite else { return .full }
        let b = box ?? .full
        var w = max(1e-6, b.width) * W, h = max(1e-6, b.height) * H
        let cx = b.midX * W, cy = b.midY * H
        if w / h < aspect { w = h * aspect } else { h = w / aspect }
        if w > W { w = W; h = W / aspect }
        if h > H { h = H; w = H * aspect }
        let x = min(max(cx - w / 2, 0), W - w), y = min(max(cy - h / 2, 0), H - h)
        return FramingBox(x: x / W, y: y / H, width: w / W, height: h / H)
    }

    /// Huella de la toma y sus punches para la caché (`cache/framing/<takeID>.json`): rutas, tamaño y fecha de los
    /// ficheros, desfases y tramos.
    public static func fingerprint(video: MontagePartVideo) -> String {
        func file(_ url: URL?) -> String {
            guard let url else { return "-" }
            let a = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (a?[.size] as? NSNumber)?.int64Value ?? -1
            let date = (a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            return "\(url.lastPathComponent):\(size):\(Int(date))"
        }
        var text = "v\(FramingAnalysis.currentVersion)|\(file(video.url))|\(video.videoOffset)|\(video.take.start)|\(video.take.end)"
        for p in video.punches { text += "|\(file(p.videoURL)):\(p.start):\(p.end):\(p.videoOffset)" }
        // El giro cambia las coordenadas del análisis; sin giro la huella no cambia (las cachés anteriores valen).
        if video.rotation != .none { text += "|rot\(video.rotation.degrees)" }
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
