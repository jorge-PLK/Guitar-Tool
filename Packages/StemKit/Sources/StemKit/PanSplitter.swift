import Accelerate
import AVFoundation
import Foundation

// No usado desde la revisión del 15/11/2026; ver spec, «Opciones de guitarras y tramos de solo». El producto compone
// las pistas con `GuitarStemComposer` (L/R = canales, solista con modelo en tramos). Se conserva, con sus tests, por
// el trabajo medido: máscaras por canal, puerta del centro, `centerNotes` y `PanSoloSpan`.

/// Lado del panorama de una pista de guitarra (mini-spec Fase 4, «Separación por panorama»).
public enum GuitarSide: String, Sendable, CaseIterable, Codable {
    case left = "L"
    case center = "C"
    case right = "R"

    /// `guitar_L.wav`, `guitar_C.wav` o `guitar_R.wav` (en `stems/`).
    public var fileName: String { "guitar_\(rawValue).wav" }
}

/// Confianza de una pista separada por panorama.
public struct PanConfidence: Sendable, Equatable {
    public enum Level: String, Sendable, Codable {
        case high, medium, low
    }

    public var level: Level
    /// `focus · (1 − mixRisk)`, en [0, 1]; 0 si la entrada es mono (solo queda el centro).
    public var score: Double
    /// Fracción de la energía de la pista que viene de bins fuera de las zonas de transición.
    public var focus: Double
    /// Máximo parecido de envolventes por bandas con las otras pistas que se guardan (0 si es la única).
    /// Alto = dos pistas que tocan lo mismo (dobladas o restos de una en otra).
    public var mixRisk: Double

    public init(level: Level, score: Double, focus: Double, mixRisk: Double) {
        self.level = level
        self.score = score
        self.focus = focus
        self.mixRisk = mixRisk
    }
}

/// Pista propuesta y guardada en disco.
public struct PanSplitTrack: Sendable, Equatable {
    public var side: GuitarSide
    public var url: URL
    public var level: StemLevel
    public var confidence: PanConfidence
}

/// Motivo por el que una pista no se guarda.
public enum PanDiscardReason: Sendable, Equatable {
    /// `StemLevelMeter.isEmpty`.
    case empty
    /// RMS más de `relativeDiscardDB` por debajo de la entrada; lleva la diferencia (negativa) en dB.
    case belowInput(relativeDB: Double)
}

public struct PanSplitDiscard: Sendable, Equatable {
    public var side: GuitarSide
    public var level: StemLevel
    public var reason: PanDiscardReason
}

public struct PanSplitResult: Sendable, Equatable {
    public var inputLevel: StemLevel
    /// Pistas guardadas, en orden L, C, R.
    public var tracks: [PanSplitTrack]
    /// Lados descartados (no están en disco), en orden L, C, R.
    public var discarded: [PanSplitDiscard]
    /// Parecido de envolventes entre cada par de lados, guardados o no (para los tests informativos).
    var envelopeSimilarity: [Pair: Double] = [:]

    struct Pair: Hashable {
        let a: GuitarSide, b: GuitarSide
    }
}

/// Separa la pista de guitarras en izquierda, centro y derecha con máscaras suaves sobre la STFT
/// (mini-spec Fase 4, «Separación por panorama»; máscara por canal decidida por el orquestador).
///
/// En cada bin se suman ±`coherenceRadius` tramas de `Re(L·R*)`, `|L|²` y `|R|²` (S_LR, S_LL, S_RR).
/// Panorama `p = atan2(√S_RR, √S_LL) · 4/π − 1`, en [−1, 1]: con la ley de potencia constante, mono → 0,
/// extremos → ±1, «±30 %» → ±0,3. Cercanía al centro `pc(|p|)`: 1 hasta `centerWidth`, coseno alzado en
/// `transitionWidth` y 0 después.
/// Parte de centro por canal (Wiener: con L = c + a, R = c + b independientes, S_LR es la potencia de c):
/// `cL = pc · rampa((S_LR/S_LL − suelo)/(1 − suelo))`, ídem `cR` con S_RR. Una fuente real en el centro
/// (en fase y sostenida) da ≈ 1; las coincidencias de dos guitarras distintas (fase aleatoria, duran poco)
/// quedan por debajo del suelo `coherenceFloor` y vuelven a L/R (orquestador, 15/11/2026).
/// Pista L = `(1 − cL) · canal L` (su canal derecho va a cero), R = `(1 − cR) · canal R` y
/// C = `(cL · L, cR · R)`. En cada canal las máscaras suman 1, así que la suma de las pistas es la entrada.
/// Así, en un bin donde se solapan dos guitarras abiertas, cada canal se queda en su lado.
///
/// Por bloques con solape: cada bloque se transforma con un margen a cada lado (n_fft más el radio de la
/// coherencia) y la rejilla de tramas alineada con la global, de modo que el resultado es el mismo que con
/// el tema entero en memoria.
///
/// Centro con puerta (mini-spec Fase 4, «Centro con puerta»): C solo existe en `soloSpans`. En cada trama,
/// `cL = máx_tramo g(t) · sel(f, p) · cL_tramo`, con `g` la puerta del tramo (fundido de coseno alzado de
/// `PanSoloSpan.fadeSeconds` por fuera de cada borde), `sel` la franja de frecuencias y el rango de panorama y
/// `cL_tramo` la fórmula de arriba con la anchura y el suelo del tramo. Las máscaras siguen sumando 1 por canal.
/// Las muestras a las que solo llegan tramas con máscara 0 se copian de la entrada: ahí L y R son los canales
/// exactos y C = 0 exacto. Sin tramos no hay C (sale vacía y se descarta).
/// Excepción: entrada casi mono (sin puerta, L y R más de `relativeDiscardDB` por debajo de la entrada) → se
/// rehace sin puerta con los parámetros base, y todo queda en C como antes.
public struct PanSplitter: Sendable {
    /// Ancho del centro puro en |p| (mono = 0, ±30 % = 0,3). Mini-spec Fase 4, «Separación por panorama».
    /// Ancho porque la coherencia ya aparta las coincidencias de dobladas (orquestador, 15/11/2026: con
    /// 0,01 el solo grabado en el centro de Platero se repartía entre L y R).
    /// Con |p| ≥ 0,25 nada va al centro: deja fuera las guitarras sueltas a ±30 % de T1–T3.
    public static let defaultCenterWidth: Float = 0.15
    /// Ancho de la transición centro → lado en |p|.
    public static let defaultTransitionWidth: Float = 0.1
    /// Tramas a cada lado para promediar Re(L·R*), |L|² y |R|² (20 · 512 muestras = ±232 ms a 44,1 kHz).
    public static let defaultCoherenceRadius = 20
    /// Suelo de Re(L·R*)/|canal|²: lo que queda por debajo (ruido de fase de coincidencias) no va al centro.
    public static let defaultCoherenceFloor: Float = 0.25
    /// k en Re(S_LR) − k·|Im(S_LR)|: aparta las coincidencias en fase aleatoria (dobladas) del centro.
    public static let defaultPhasePenalty: Float = 2
    /// Rampa de γ del modelo `gate` (comparación en los barridos; no es el modelo por defecto).
    static let gateCoherenceLow: Float = 0.6
    static let gateCoherenceHigh: Float = 0.85
    /// Propuesta 1 confirmada (15/11/2026): se descarta la pista más de 24 dB por debajo de la entrada.
    public static let defaultRelativeDiscardDB = 24.0
    /// Umbrales de `PanConfidence.score`, calibrados con 12 s de T1–T3 (PanSplitterT1Tests), donde todas las
    /// guitarras abiertas son dobladas: L/R 0,55–0,58 (T1), 0,36 (T2), 0,31 (T3); C de coincidencias
    /// 0,36–0,55. Guitarras independientes o una sola abierta ≈ 1; mono o una sola a ±30 % ≈ 0.
    public static let highConfidenceScore = 0.7
    public static let mediumConfidenceScore = 0.4

    /// Semianchura de cada armónico de la guía por notas, en cents: cubre bends y vibrato de hasta un tono
    /// (banco T2 + solista en el centro, orquestador 15/11/2026: ±200 frente a ±100 y ±50 en PanSplitterT1Tests).
    public static let defaultGuideWidthCents = 200.0

    public var centerWidth: Float
    public var transitionWidth: Float
    public var relativeDiscardDB: Double
    /// Notas de la guitarra del centro en los pasajes de solo (Basic Pitch sobre `guitar_C.wav` de una
    /// primera pasada). Durante cada nota, f0 y armónicos (± `defaultGuideWidthCents`) de los dos canales
    /// pasan a C con la máscara de amplitud √(S_LR/S_canal), sin la puerta de panorama ni el suelo de coherencia.
    /// Vacío: sin guía (una sola pasada).
    public var centerNotes: [PanCenterNote]
    /// Tramos de solo de la puerta del centro (editor «Aislar solo»). Vacío: sin pista C, salvo entrada casi mono.
    public var soloSpans: [PanSoloSpan]
    /// Solo tests: C en todo el tema con `centerWidth` y el suelo base, sin puerta (comportamiento anterior a
    /// la puerta; lo usan los tests de máscara, diafonía y barridos). También es el modo de la entrada casi mono.
    var ungated = false
    /// Ajustables desde los tests (barridos de PanSplitterT1Tests).
    var coherenceRadius = PanSplitter.defaultCoherenceRadius
    var coherenceLow = PanSplitter.defaultCoherenceFloor
    var coherenceHigh: Float = 1
    var centerModel = PanCenterModel.wiener
    var phasePenalty = PanSplitter.defaultPhasePenalty
    var guideWidthCents = PanSplitter.defaultGuideWidthCents
    var guideMode = PanGuideMode.amplitude
    /// Solo tests: aplica las mismas máscaras a este WAV y escribe `probe-guitar_X.wav` en la salida
    /// (dónde acaba exactamente una fuente conocida de la mezcla).
    var probeInput: URL?
    /// Muestras útiles por bloque; múltiplo del hop. ~3 s a 44,1 kHz.
    var blockFrames = 64 * RoformerContract.nFFT

    public init(centerWidth: Float = PanSplitter.defaultCenterWidth,
                transitionWidth: Float = PanSplitter.defaultTransitionWidth,
                relativeDiscardDB: Double = PanSplitter.defaultRelativeDiscardDB,
                centerNotes: [PanCenterNote] = [],
                soloSpans: [PanSoloSpan] = []) {
        self.centerWidth = centerWidth
        self.transitionWidth = transitionWidth
        self.relativeDiscardDB = relativeDiscardDB
        self.centerNotes = centerNotes
        self.soloSpans = soloSpans
    }

    /// Con los parámetros por defecto.
    public static func split(input: URL, outputDirectory: URL,
                             soloSpans: [PanSoloSpan] = []) throws -> PanSplitResult {
        try PanSplitter(soloSpans: soloSpans).split(input: input, outputDirectory: outputDirectory)
    }

    /// Lee `input` (WAV estéreo) por bloques y escribe en `outputDirectory` las pistas no descartadas
    /// (`GuitarSide.fileName`), float32 estéreo, con la frecuencia y la longitud exactas de la entrada.
    /// Borra las pistas de una ejecución anterior que ahora se descarten.
    public func split(input: URL, outputDirectory: URL) throws -> PanSplitResult {
        precondition(centerWidth >= 0 && transitionWidth > 0, "PanSplitter: anchuras no válidas")
        precondition(coherenceRadius >= 0 && coherenceHigh > coherenceLow, "PanSplitter: coherencia no válida")
        precondition(blockFrames > 0 && blockFrames % RoformerContract.hop == 0,
                     "PanSplitter: el bloque debe ser múltiplo del hop")
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: input, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw SeparationError.invalidInput("no se puede leer \(input.lastPathComponent): \(error.localizedDescription)")
        }
        let fmt = file.processingFormat
        guard fmt.channelCount == 2 else {
            throw SeparationError.invalidInput("se esperaba audio estéreo y tiene \(fmt.channelCount) canales")
        }
        let n = Int(file.length)
        guard n > RoformerContract.nFFT else {
            throw SeparationError.invalidInput("audio demasiado corto para separar por panorama (\(n) muestras)")
        }

        let fm = FileManager.default
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let sides = GuitarSide.allCases
        let partials = sides.map { outputDirectory.appendingPathComponent(".partial-\($0.fileName)") }
        var finished = false
        defer {
            if !finished { for u in partials { try? fm.removeItem(at: u) } }
        }

        var params = PanMaskParameters(centerWidth: centerWidth, transitionWidth: transitionWidth,
                                       coherenceRadius: coherenceRadius, coherenceLow: coherenceLow,
                                       coherenceHigh: coherenceHigh, centerModel: centerModel,
                                       phasePenalty: phasePenalty, noteGuide: centerNotes,
                                       guideWidthCents: guideWidthCents, guideMode: guideMode,
                                       sampleRate: fmt.sampleRate)
        if !ungated {
            params.gate = soloSpans.compactMap { PanGateSpan($0, sampleRate: fmt.sampleRate) }
        }
        var stats = try runPass(params, file: file, format: fmt, frameCount: n, partials: partials,
                                outputDirectory: outputDirectory)
        if params.gate != nil && stats.isNearMono(relativeDB: relativeDiscardDB) {
            // Entrada casi mono: todo a C, sin puerta (mini-spec Fase 4, «Centro con puerta», excepción).
            params.gate = nil
            for u in partials { try? fm.removeItem(at: u) }
            stats = try runPass(params, file: file, format: fmt, frameCount: n, partials: partials,
                                outputDirectory: outputDirectory)
        }

        let inputLevel = try StemLevelMeter.measure(url: input)
        var kept: [(index: Int, side: GuitarSide, url: URL, level: StemLevel)] = []
        var discarded: [PanSplitDiscard] = []
        for (i, side) in sides.enumerated() {
            let level = try StemLevelMeter.measure(url: partials[i])
            let final = outputDirectory.appendingPathComponent(side.fileName)
            if fm.fileExists(atPath: final.path) { try fm.removeItem(at: final) }
            let relative = level.rmsDB - inputLevel.rmsDB
            if StemLevelMeter.isEmpty(level) || relative < -relativeDiscardDB {
                try fm.removeItem(at: partials[i])
                let reason: PanDiscardReason = StemLevelMeter.isEmpty(level) ? .empty : .belowInput(relativeDB: relative)
                discarded.append(PanSplitDiscard(side: side, level: level, reason: reason))
            } else {
                try fm.moveItem(at: partials[i], to: final)
                kept.append((i, side, final, level))
            }
        }
        finished = true

        let monoInput = kept.map(\.side) == [.center]
        let tracks = kept.map { k -> PanSplitTrack in
            let focus = stats.energy[k.index] > 0 ? min(1, stats.core[k.index] / stats.energy[k.index]) : 0
            let risk = kept.filter { $0.index != k.index }
                .map { stats.envelopeSimilarity(k.index, $0.index) }.max() ?? 0
            return PanSplitTrack(side: k.side, url: k.url, level: k.level,
                                 confidence: Self.confidence(focus: focus, mixRisk: risk, monoInput: monoInput))
        }
        var result = PanSplitResult(inputLevel: inputLevel, tracks: tracks, discarded: discarded)
        for (i, j) in [(0, 1), (0, 2), (1, 2)] {
            result.envelopeSimilarity[.init(a: sides[i], b: sides[j])] = stats.envelopeSimilarity(i, j)
        }
        return result
    }

    /// Una pasada completa: escribe las tres pistas en `partials` (y las de la sonda, si hay) y devuelve los acumulados.
    private func runPass(_ params: PanMaskParameters, file: AVAudioFile, format fmt: AVAudioFormat, frameCount n: Int,
                         partials: [URL], outputDirectory: URL) throws -> PanSplitStats {
        let writers = try partials.map { try AudioIO.StereoWriter(url: $0, sampleRate: fmt.sampleRate) }
        let engine = PanBlockEngine(params: params, maxLength: min(n, blockFrames + 2 * params.margin),
                                    format: fmt, totalFrames: n)
        var probe: (AVAudioFile, [AudioIO.StereoWriter])?
        if let probeInput {
            let pf = try AVAudioFile(forReading: probeInput, commonFormat: .pcmFormatFloat32, interleaved: false)
            let pw = try GuitarSide.allCases.map {
                try AudioIO.StereoWriter(url: outputDirectory.appendingPathComponent("probe-\($0.fileName)"),
                                         sampleRate: fmt.sampleRate)
            }
            probe = (pf, pw)
        }
        defer {
            writers.forEach { $0.close() }
            probe?.1.forEach { $0.close() }
        }
        try engine.run(file: file, frameCount: n, blockFrames: blockFrames, writers: writers, probe: probe)
        return engine.stats
    }

    /// Orquestador (15/11/2026): por pista, foco y riesgo de mezcla; entrada mono (solo queda C) → baja.
    static func confidence(focus: Double, mixRisk: Double, monoInput: Bool) -> PanConfidence {
        let score = monoInput ? 0 : focus * (1 - max(0, mixRisk))
        let level: PanConfidence.Level = score >= highConfidenceScore ? .high
            : score >= mediumConfidenceScore ? .medium : .low
        return PanConfidence(level: level, score: score, focus: focus, mixRisk: mixRisk)
    }
}

/// Acumulados de todo el tema para la confianza (solo tramas útiles de cada bloque).
struct PanSplitStats {
    /// Bandas logarítmicas de la envolvente, de ~43 Hz a Nyquist.
    static let bandCount = 16
    /// Tramas sumadas por punto de envolvente (4 · 512 = 46 ms a 44,1 kHz).
    static let envelopeGroup = 4

    /// Energía de cada pista (L, C, R) en el espectro.
    var energy = [Double](repeating: 0, count: 3)
    /// Lo mismo, solo con bins fuera de la transición (máscara 0 o 1).
    var core = [Double](repeating: 0, count: 3)
    /// Energía de la entrada (los dos canales) en el espectro.
    var inputEnergy = 0.0
    /// Energía que tendrían L y R sin puerta (parámetros base): decide la entrada casi mono.
    var ungatedSideEnergy = [0.0, 0.0]

    /// Sin puerta, L y R quedarían las dos más de `relativeDB` por debajo de la entrada (el criterio de mono de
    /// siempre: solo se guardaría C).
    func isNearMono(relativeDB: Double) -> Bool {
        guard inputEnergy > 0 else { return false }
        let limit = inputEnergy * pow(10, -relativeDB / 10)
        return ungatedSideEnergy[0] < limit && ungatedSideEnergy[1] < limit
    }
    /// Energía por pista, banda y grupo de tramas: `envelope[side * stride + band * groups + g]`.
    var envelope: [Double]
    let groups: Int
    /// `bandCount · groups`.
    let stride: Int

    init(totalFrames: Int) {
        groups = (1 + totalFrames / RoformerContract.hop + Self.envelopeGroup - 1) / Self.envelopeGroup
        stride = Self.bandCount * groups
        envelope = [Double](repeating: 0, count: 3 * stride)
    }

    /// Banda de cada bin (bins 0–1 van a la primera).
    static let bandOfBin: [Int] = {
        let bins = RoformerContract.bins
        let lo = 2.0, hi = Double(bins - 1)
        return (0..<bins).map { f in
            guard Double(f) > lo else { return 0 }
            let b = Int(log(Double(f) / lo) / log(hi / lo) * Double(bandCount))
            return min(bandCount - 1, max(0, b))
        }
    }()

    /// Correlación de las envolventes de amplitud (√energía) de dos pistas, sin la media de cada banda,
    /// sumando todas las bandas. 1 = mismas notas al mismo tiempo en las mismas bandas.
    func envelopeSimilarity(_ a: Int, _ b: Int) -> Double {
        var num = 0.0, da = 0.0, db = 0.0
        for band in 0..<Self.bandCount {
            let ba = a * stride + band * groups, bb = b * stride + band * groups
            var ma = 0.0, mb = 0.0
            for g in 0..<groups {
                ma += envelope[ba + g].squareRoot()
                mb += envelope[bb + g].squareRoot()
            }
            ma /= Double(groups)
            mb /= Double(groups)
            for g in 0..<groups {
                let x = envelope[ba + g].squareRoot() - ma
                let y = envelope[bb + g].squareRoot() - mb
                num += x * y
                da += x * x
                db += y * y
            }
        }
        guard da > 0, db > 0 else { return 0 }
        return num / (da * db).squareRoot()
    }
}

/// Nota de la guitarra del centro para `PanSplitter.centerNotes`, en segundos desde el inicio del fichero.
/// `midi` admite fracciones (afinación o bend medio).
public struct PanCenterNote: Sendable, Equatable {
    public var start: Double
    public var end: Double
    public var midi: Double

    public init(start: Double, end: Double, midi: Double) {
        self.start = start
        self.end = end
        self.midi = midi
    }
}

/// Cómo pasan a C los bins armónicos de una nota guía (comparación en PanSplitterT1Tests).
enum PanGuideMode: Sendable {
    /// El bin entero de los dos canales.
    case hard
    /// La potencia común del bin (S_LR/S_canal, sin la puerta de panorama ni el suelo).
    case wiener
    /// La raíz de la anterior (máscara de amplitud). Por defecto: la única que no empeora L ni R.
    case amplitude
}

/// Cómo se decide la parte de centro de un bin cercano al centro.
enum PanCenterModel: Sendable {
    /// Rampa sobre γ = 2·Re(L·R*)/(|L|² + |R|²) entre `coherenceLow` y `coherenceHigh`; igual en los dos canales.
    case gate
    /// Por canal, Re(L·R*)/|canal|² (potencia común entre la del canal, estimación de Wiener del centro),
    /// con `coherenceLow` como suelo para el ruido de fase de las coincidencias.
    case wiener
}

struct PanMaskParameters: Sendable {
    var centerWidth: Float
    var transitionWidth: Float
    var coherenceRadius: Int
    var coherenceLow: Float
    var coherenceHigh: Float
    var centerModel: PanCenterModel
    var phasePenalty: Float
    /// Guía por notas del centro: notas, semianchura de cada armónico en cents y modo.
    var noteGuide: [PanCenterNote] = []
    var guideWidthCents = PanSplitter.defaultGuideWidthCents
    var guideMode = PanGuideMode.amplitude
    var sampleRate = 44_100.0
    /// Puerta del centro: `nil` sin puerta (C en todo el tema con los parámetros base); vacío, C = 0 en todo el tema.
    var gate: [PanGateSpan]?
    /// Margen tras el final de una nota (cola) y antes del inicio (ataque), en segundos.
    static let guideRelease = 0.05
    static let guideAttack = 0.02
    /// Armónicos hasta esta frecuencia.
    static let guideMaxHz = 10_000.0
    /// Semianchura mínima de un armónico en bins (la ventana de Hann ocupa ±2 bins).
    static let guideMinHalfBins = 1.5

    /// Solape a cada lado: una muestra útil depende de tramas a ±n_fft/2; la máscara de cada trama, de
    /// ±radio tramas; y cada trama lee n_fft/2 más allá. Con n_fft + radio·hop de margen (y bloques alineados
    /// al hop) el bloque coincide con el proceso del tema entero.
    var margin: Int { RoformerContract.nFFT + coherenceRadius * RoformerContract.hop }
}

/// Proceso por bloques. No es seguro entre hilos.
final class PanBlockEngine {
    let params: PanMaskParameters
    private(set) var stats: PanSplitStats

    private let hop = RoformerContract.hop
    private let bins = RoformerContract.bins
    private let maxLength: Int
    private let maxFrames: Int
    private var transforms: [Int: SpectralTransform] = [:]
    private let inBuffer: AVAudioPCMBuffer
    private let spec: UnsafeMutablePointer<Float>
    private let work: UnsafeMutablePointer<Float>
    /// Máscara lateral s por (bin, trama).
    private let centerL: UnsafeMutablePointer<Float>
    private let centerR: UnsafeMutablePointer<Float>
    /// 1 en los bins armónicos de una nota guía del centro, por (bin, trama).
    private let guideMask: UnsafeMutablePointer<Float>
    private let trackMask: UnsafeMutablePointer<Float>
    private let magL: UnsafeMutablePointer<Float>
    private let magR: UnsafeMutablePointer<Float>
    private let outL: UnsafeMutablePointer<Float>
    private let outR: UnsafeMutablePointer<Float>
    private let zeros: UnsafeMutablePointer<Float>
    /// Sumas acumuladas (Double) de Re(L·R*) y |L|² + |R|² de un bin, para la coherencia por ventana.
    private let cumLR: UnsafeMutablePointer<Double>
    private let cumLL: UnsafeMutablePointer<Double>
    private let cumRR: UnsafeMutablePointer<Double>
    private let cumIm: UnsafeMutablePointer<Double>
    /// Trama con alguna máscara de centro > 0 (en algún bin o canal).
    private let frameOpen: UnsafeMutablePointer<Bool>
    /// Muestra del bloque a la que llega alguna trama abierta (si no, L y R se copian de la entrada y C = 0).
    private let sampleOpen: UnsafeMutablePointer<Bool>

    /// - Parameter format: formato de proceso del fichero de entrada (float32 estéreo no intercalado).
    init(params: PanMaskParameters, maxLength: Int, format: AVAudioFormat, totalFrames: Int) {
        self.params = params
        self.maxLength = maxLength
        stats = PanSplitStats(totalFrames: totalFrames)
        maxFrames = 1 + maxLength / RoformerContract.hop
        let specCount = 4 * RoformerContract.bins * maxFrames
        let maskCount = RoformerContract.bins * maxFrames
        inBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(maxLength))!
        func alloc(_ count: Int) -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: count)
            p.initialize(repeating: 0, count: count)
            return p
        }
        spec = alloc(specCount)
        work = alloc(specCount)
        centerL = alloc(maskCount)
        centerR = alloc(maskCount)
        guideMask = alloc(params.noteGuide.isEmpty ? 1 : maskCount)
        trackMask = alloc(maskCount)
        magL = alloc(maxFrames)
        magR = alloc(maxFrames)
        outL = alloc(maxLength)
        outR = alloc(maxLength)
        zeros = alloc(maxLength)
        let cumCount = 2 + maxLength / RoformerContract.hop
        func allocD() -> UnsafeMutablePointer<Double> {
            let p = UnsafeMutablePointer<Double>.allocate(capacity: cumCount)
            p.initialize(repeating: 0, count: cumCount)
            return p
        }
        cumLR = allocD()
        cumLL = allocD()
        cumRR = allocD()
        cumIm = allocD()
        frameOpen = .allocate(capacity: maxFrames)
        frameOpen.initialize(repeating: false, count: maxFrames)
        sampleOpen = .allocate(capacity: maxLength)
        sampleOpen.initialize(repeating: false, count: maxLength)
    }

    deinit {
        for p in [spec, work, centerL, centerR, guideMask, trackMask, magL, magR, outL, outR, zeros] {
            p.deallocate()
        }
        for p in [cumLR, cumLL, cumRR, cumIm] { p.deallocate() }
        frameOpen.deallocate()
        sampleOpen.deallocate()
    }

    func run(file: AVAudioFile, frameCount n: Int, blockFrames: Int, writers: [AudioIO.StereoWriter],
             probe: (AVAudioFile, [AudioIO.StereoWriter])? = nil) throws {
        let m = params.margin
        var k0 = 0
        while k0 < n {
            let k1 = min(n, k0 + blockFrames)
            let p0 = max(0, k0 - m)
            let p1 = min(n, k1 + m)
            let len = p1 - p0
            let (left, right) = try read(file, from: p0, count: len)
            let st = transform(len)
            st.forward(left, channel: 0, into: spec)
            st.forward(right, channel: 1, into: spec)
            // Tramas cuyo centro cae en [k0, k1): cada trama global se cuenta una sola vez.
            let t0 = (k0 - p0) / hop
            let t1 = k1 == n ? st.frames : (k1 - p0) / hop
            computeMask(st, keep: t0..<t1, firstGlobalFrame: p0 / hop)
            markOpenSamples(frames: st.frames, length: len)

            let off = k0 - p0
            let keep = k1 - k0
            try writeTracks(st, input: (left, right), off: off, keep: keep, writers: writers)
            if let (pf, pw) = probe {
                // Mismas máscaras sobre la sonda (medida exacta de dónde acaba una fuente conocida).
                let (pl, pr) = try read(pf, from: p0, count: len)
                st.forward(pl, channel: 0, into: spec)
                st.forward(pr, channel: 1, into: spec)
                try writeTracks(st, input: (pl, pr), off: off, keep: keep, writers: pw)
            }
            k0 = k1
        }
    }

    /// `sampleOpen[j]` si alguna trama abierta cubre la muestra j del bloque (la trama t ocupa
    /// `[t·hop − n_fft/2, t·hop + n_fft/2)`, center=True).
    private func markOpenSamples(frames: Int, length: Int) {
        sampleOpen.update(repeating: false, count: length)
        let half = RoformerContract.nFFT / 2
        for t in 0..<frames where frameOpen[t] {
            let a = max(0, t * hop - half), b = min(length, t * hop + half)
            if a < b { (sampleOpen + a).update(repeating: true, count: b - a) }
        }
    }

    /// Pistas L, C y R del bloque con las máscaras ya calculadas, sobre el espectro que haya en `spec`
    /// (`input`: las muestras de las que sale ese espectro). Donde no llega ninguna trama abierta, L y R son
    /// copia exacta de la entrada y C = 0.
    private func writeTracks(_ st: SpectralTransform, input: (UnsafePointer<Float>, UnsafePointer<Float>),
                             off: Int, keep: Int, writers: [AudioIO.StereoWriter]) throws {
        let (inL, inR) = input
        guard (off..<off + keep).contains(where: { sampleOpen[$0] }) else {
            try writers[0].write(left: inL + off, right: zeros, count: keep)
            try writers[1].write(left: zeros, right: zeros, count: keep)
            try writers[2].write(left: zeros, right: inR + off, count: keep)
            return
        }
        // L: solo canal izquierdo con s.
        applyMask(st, sideOf: centerL, channel: 0)
        st.inverse(work, channel: 0, into: outL)
        for j in off..<off + keep where !sampleOpen[j] { outL[j] = inL[j] }
        try writers[0].write(left: outL + off, right: zeros, count: keep)
        // C: los dos canales con 1 − s.
        applyMask(st, centerL, channel: 0)
        applyMask(st, centerR, channel: 1)
        st.inverse(work, channel: 0, into: outL)
        st.inverse(work, channel: 1, into: outR)
        for j in off..<off + keep where !sampleOpen[j] {
            outL[j] = 0
            outR[j] = 0
        }
        try writers[1].write(left: outL + off, right: outR + off, count: keep)
        // R: solo canal derecho con s.
        applyMask(st, sideOf: centerR, channel: 1)
        st.inverse(work, channel: 1, into: outR)
        for j in off..<off + keep where !sampleOpen[j] { outR[j] = inR[j] }
        try writers[2].write(left: zeros, right: outR + off, count: keep)
    }

    private func transform(_ length: Int) -> SpectralTransform {
        if let t = transforms[length] { return t }
        let t = SpectralTransform(length: length)
        transforms[length] = t
        return t
    }

    private func read(_ file: AVAudioFile, from start: Int, count: Int) throws -> (UnsafePointer<Float>, UnsafePointer<Float>) {
        file.framePosition = AVAudioFramePosition(start)
        let buf = inBuffer
        try file.read(into: buf, frameCount: AVAudioFrameCount(count))
        guard Int(buf.frameLength) == count else {
            throw SeparationError.invalidInput("lectura incompleta: \(buf.frameLength) de \(count) muestras")
        }
        let ch = buf.floatChannelData!
        return (UnsafePointer(ch[0]), UnsafePointer(ch[1]))
    }

    /// `guideMask` = 1 en f0 y armónicos (± `guideWidthCents`, mínimo `guideMinHalfBins`) de las notas que
    /// suenan en cada trama del bloque.
    private func fillGuide(frames: Int, firstGlobalFrame: Int) {
        vDSP_vclr(guideMask, 1, vDSP_Length(bins * frames))
        let sr = params.sampleRate
        let binHz = sr / Double(RoformerContract.nFFT)
        let t0 = Double(firstGlobalFrame * hop) / sr
        let t1 = Double((firstGlobalFrame + frames - 1) * hop) / sr
        let ratio = pow(2, params.guideWidthCents / 1200)
        for note in params.noteGuide {
            let a = note.start - PanMaskParameters.guideAttack, b = note.end + PanMaskParameters.guideRelease
            guard b >= t0, a <= t1 else { continue }
            let fa = max(0, Int(((a * sr) / Double(hop)).rounded(.up)) - firstGlobalFrame)
            let fb = min(frames - 1, Int(((b * sr) / Double(hop)).rounded(.down)) - firstGlobalFrame)
            guard fa <= fb else { continue }
            let f0 = 440 * pow(2, (note.midi - 69) / 12)
            var k = 1.0
            while k * f0 < PanMaskParameters.guideMaxHz {
                let c = k * f0 / binHz
                let half = max(PanMaskParameters.guideMinHalfBins, c * (ratio - 1))
                let lo = max(0, Int((c - half).rounded(.up))), hi = min(bins - 1, Int((c + half).rounded(.down)))
                if lo <= hi {
                    for f in lo...hi {
                        let row = guideMask + f * frames
                        for t in fa...fb { row[t] = 1 }
                    }
                }
                k += 1
            }
        }
    }

    /// Máscaras de centro por canal para todos los bins y tramas del bloque; acumula energía y envolventes.
    private func computeMask(_ st: SpectralTransform, keep: Range<Int>, firstGlobalFrame: Int) {
        let frames = st.frames
        let guided = !params.noteGuide.isEmpty
        let guideHard = params.guideMode == .hard
        let guideExponent = params.guideMode == .amplitude ? 0.5 : 1.0
        if guided { fillGuide(frames: frames, firstGlobalFrame: firstGlobalFrame) }
        let fourOverPi = 4 / Double.pi
        let w = Double(params.centerWidth)
        let tau = Double(params.transitionWidth)
        let radius = params.coherenceRadius
        let model = params.centerModel
        let phasePenalty = Double(params.phasePenalty)
        let gLow = Double(params.coherenceLow)
        let gSpan = Double(params.coherenceHigh - params.coherenceLow)
        let groups = stats.groups
        let group = PanSplitStats.envelopeGroup
        let envStride = stats.stride
        var energy = (0.0, 0.0, 0.0)
        var core = (0.0, 0.0, 0.0)
        var inputEnergy = 0.0, ungatedL = 0.0, ungatedR = 0.0
        // Puerta: ganancia de cada tramo que toca el bloque, por trama, y su máximo (sin puerta, 1 en todas).
        let gated = params.gate != nil
        var spanGains: [(span: PanGateSpan, gain: [Double])] = []
        var frameGain = [Double](repeating: gated ? 0 : 1, count: frames)
        for s in params.gate ?? [] {
            var g = [Double](repeating: 0, count: frames)
            var any = false
            for t in 0..<frames {
                let v = s.gain(at: Double((firstGlobalFrame + t) * hop) / params.sampleRate)
                g[t] = v
                if v > 0 {
                    any = true
                    frameGain[t] = max(frameGain[t], v)
                }
            }
            if any { spanGains.append((s, g)) }
        }
        frameOpen.update(repeating: false, count: frames)
        // Copia de trabajo de las envolventes: evita accesos con comprobación de copia en el bucle interno.
        var envelope = stats.envelope
        stats.envelope = []
        defer { stats.envelope = envelope }
        envelope.withUnsafeMutableBufferPointer { env in
        for f in 0..<bins {
            let binSpans = spanGains.isEmpty ? [] : spanGains.filter { $0.span.binLow <= f && f <= $0.span.binHigh }
            let rowL = spec + st.specIndex(bin: f, channel: 0, frame: 0)
            let rowR = spec + st.specIndex(bin: f, channel: 1, frame: 0)
            var zl = DSPSplitComplex(realp: rowL, imagp: rowL + 1)
            var zr = DSPSplitComplex(realp: rowR, imagp: rowR + 1)
            vDSP_zvabs(&zl, 2, magL, 1, vDSP_Length(frames))
            vDSP_zvabs(&zr, 2, magR, 1, vDSP_Length(frames))
            let maskL = centerL + f * frames
            let maskR = centerR + f * frames
            let envBase = PanSplitStats.bandOfBin[f] * groups
            // Sumas acumuladas de Re(L·R*), |L|² y |R|² para promediar en ±radius tramas.
            for t in 0..<frames {
                let cross = rowL[2 * t] * rowR[2 * t] + rowL[2 * t + 1] * rowR[2 * t + 1]
                cumLR[t + 1] = cumLR[t] + Double(cross)
                cumIm[t + 1] = cumIm[t] + Double(rowL[2 * t + 1] * rowR[2 * t] - rowL[2 * t] * rowR[2 * t + 1])
                cumLL[t + 1] = cumLL[t] + Double(magL[t] * magL[t])
                cumRR[t + 1] = cumRR[t] + Double(magR[t] * magR[t])
            }
            var eL = 0.0, eC = 0.0, eR = 0.0, kL = 0.0, kC = 0.0, kR = 0.0
            for t in 0..<frames {
                let a = max(0, t - radius), b = min(frames, t + radius + 1)
                // Potencia común en fase: Re − k·|Im| (una fuente en el centro tiene Im ≈ 0; dos tomas
                // distintas, fase aleatoria y Im del orden de Re).
                let sLR = cumLR[b] - cumLR[a] - phasePenalty * abs(cumIm[b] - cumIm[a])
                let sLL = cumLL[b] - cumLL[a], sRR = cumRR[b] - cumRR[a]
                var cl = 0.0, cr = 0.0
                // Sin puerta, con los parámetros base (con puerta solo sirve para decidir si la entrada es mono).
                var bl = 0.0, br = 0.0
                var nearOne = false
                if sLR > 0 {
                    // Panorama de las potencias promediadas: 0 = centro, ±1 = extremos.
                    let p = atan2(sRR.squareRoot(), sLL.squareRoot()) * fourOverPi - 1
                    let near = 1 - Self.raisedCosineStep((abs(p) - w) / tau)
                    if near > 0 {
                        switch model {
                        case .gate:
                            let gamma = 2 * sLR / (sLL + sRR)
                            bl = near * Self.raisedCosineStep((gamma - gLow) / gSpan)
                            br = bl
                        case .wiener:
                            // L = c + a, R = c + b independientes → E[L·R*] = potencia de c en cada canal.
                            bl = near * Self.clamp01((sLR / sLL - gLow) / (1 - gLow))
                            br = near * Self.clamp01((sLR / sRR - gLow) / (1 - gLow))
                        }
                    }
                    if !gated {
                        cl = bl
                        cr = br
                        nearOne = near == 1
                    } else if frameGain[t] > 0 {
                        // Tramos de solo: anchura y suelo propios, solo bins de la franja y del rango de panorama,
                        // por la puerta g del tramo. Con varios tramos, el máximo (sigue en [0, 1]).
                        let rl = sLR / sLL, rr = sLR / sRR
                        for (s, g) in binSpans where g[t] > 0 && p >= s.panLow && p <= s.panHigh {
                            let ns = 1 - Self.raisedCosineStep((abs(p) - s.centerWidth) / tau)
                            guard ns > 0 else { continue }
                            let fl = s.coherenceFloor
                            cl = max(cl, g[t] * ns * Self.clamp01((rl - fl) / (1 - fl)))
                            cr = max(cr, g[t] * ns * Self.clamp01((rr - fl) / (1 - fl)))
                            if ns == 1 && g[t] == 1 { nearOne = true }
                        }
                    }
                }
                if guided && guideMask[f * frames + t] > 0 && frameGain[t] > 0 {
                    // Bin armónico de una nota del centro: sin puerta de panorama ni suelo. Con L = s + a,
                    // R = s + b, √(S_LR/S_LL) es la máscara de amplitud de s en el canal L (orquestador,
                    // 15/11/2026: la binaria quita más solo pero roba armónicos a L/R; la de potencia, poco solo).
                    // Con puerta, por la puerta de la trama: fuera de los tramos C sigue a 0.
                    let fg = frameGain[t]
                    if guideHard {
                        cl = max(cl, fg)
                        cr = max(cr, fg)
                    } else if sLR > 0 {
                        let e = guideExponent
                        cl = max(cl, fg * pow(Self.clamp01(sLR / sLL), e))
                        cr = max(cr, fg * pow(Self.clamp01(sLR / sRR), e))
                    }
                }
                maskL[t] = Float(cl)
                maskR[t] = Float(cr)
                if cl > 0 || cr > 0 { frameOpen[t] = true }
                guard keep.contains(t) else { continue }
                let pl = Double(magL[t] * magL[t]), pr = Double(magR[t] * magR[t])
                inputEnergy += pl + pr
                ungatedL += (1 - bl) * (1 - bl) * pl
                ungatedR += (1 - br) * (1 - br) * pr
                let l = (1 - cl) * (1 - cl) * pl, r = (1 - cr) * (1 - cr) * pr
                let c = cl * cl * pl + cr * cr * pr
                eL += l; eR += r; eC += c
                if cl == 0 { kL += l }
                if cr == 0 { kR += r }
                if nearOne { kC += c }
                let g = envBase + (firstGlobalFrame + t) / group
                env[g] += l
                env[envStride + g] += c
                env[2 * envStride + g] += r
            }
            energy.0 += eL; energy.1 += eC; energy.2 += eR
            core.0 += kL; core.1 += kC; core.2 += kR
        }
        }
        stats.energy[0] += energy.0; stats.energy[1] += energy.1; stats.energy[2] += energy.2
        stats.core[0] += core.0; stats.core[1] += core.1; stats.core[2] += core.2
        stats.inputEnergy += inputEnergy
        stats.ungatedSideEnergy[0] += ungatedL
        stats.ungatedSideEnergy[1] += ungatedR
    }

    @inline(__always)
    static func raisedCosineStep(_ u: Double) -> Double {
        u <= 0 ? 0 : u >= 1 ? 1 : 0.5 - 0.5 * cos(Double.pi * u)
    }

    @inline(__always)
    static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

    /// `work[canal] = spec[canal] · (1 − center)`.
    private func applyMask(_ st: SpectralTransform, sideOf center: UnsafeMutablePointer<Float>, channel c: Int) {
        var minusOne: Float = -1, one: Float = 1
        vDSP_vsmsa(center, 1, &minusOne, &one, trackMask, 1, vDSP_Length(bins * st.frames))
        applyMask(st, trackMask, channel: c)
    }

    /// `work[canal] = spec[canal] · mask` (re e im).
    private func applyMask(_ st: SpectralTransform, _ mask: UnsafeMutablePointer<Float>, channel c: Int) {
        let frames = st.frames
        for f in 0..<bins {
            let row = mask + f * frames
            let i = st.specIndex(bin: f, channel: c, frame: 0)
            vDSP_vmul(spec + i, 2, row, 1, work + i, 2, vDSP_Length(frames))
            vDSP_vmul(spec + i + 1, 2, row, 1, work + i + 1, 2, vDSP_Length(frames))
        }
    }
}
