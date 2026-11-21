import Foundation
import NativeAudioFile
import XCTest
@testable import AudioKit

/// Medidas del motor portátil (plan, «Corte del paso 7», parte 7.6), en el Mac y en Windows: latencia de Signalsmith y
/// error de posición tras compensarla a 100 %, 70 % y 50 %; continuidad en el bucle y al buscar; coste de CPU con 6
/// stems estéreo. Render offline con señales sintéticas a 48 kHz; nada suena.
final class PortablePlayerMeasurementTests: XCTestCase {
    static let sr = 48_000.0
    var sr: Double { Self.sr }

    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("PortablePlayerMeasurementTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func sine(_ seconds: Double, _ hz: Double, _ amp: Float) -> [Float] {
        (0..<Int(seconds * sr)).map { amp * Float(sin(2 * Double.pi * hz * Double($0) / Self.sr)) }
    }

    /// Ráfaga de 2 ms a 3 kHz con ventana de Hann centrada en `t` (la de `StudyPlayerTests`).
    func addBurst(_ x: inout [Float], at t: Double) {
        let len = 96, c = Int((t * sr).rounded())
        for k in 0..<len {
            let w = 0.5 - 0.5 * cos(2 * Double.pi * Double(k) / Double(len))
            x[c - len / 2 + k] += Float(w * sin(2 * Double.pi * 3_000 * Double(k) / sr))
        }
    }

    func centroid(_ x: [Float], around c: Double, half: Int) -> Double {
        let lo = max(0, Int(c) - half), hi = min(x.count, Int(c) + half)
        var e = 0.0, ex = 0.0
        for j in lo..<hi { let v = Double(x[j]) * Double(x[j]); e += v; ex += v * Double(j) }
        return ex / e
    }

    /// Mayor salto entre muestras consecutivas en `[from, to)`.
    func maxStep(_ x: [Float], from: Int, to: Int) -> Float {
        var m: Float = 0
        for j in max(1, from)..<min(x.count, to) { m = max(m, abs(x[j] - x[j - 1])) }
        return m
    }

    @MainActor
    func player(_ stems: [[Float]], in dir: URL) throws -> PortableStudyPlayer {
        let tracks = try stems.enumerated().map { i, x -> Track in
            let url = dir.appendingPathComponent("s\(i).wav")
            try TakeFile.write([x, x], sampleRate: sr, to: url)
            return Track(id: "s\(i)", url: url)
        }
        let p = PortableStudyPlayer(offlineWith: nil)
        try p.load(tracks: tracks)
        return p
    }

    // MARK: Latencia y posición

    /// Ráfagas cada 0,5 s; a cada velocidad (100 % forzando Signalsmith) el centroide de cada ráfaga debe caer donde dice
    /// el modelo del reloj (`songTime(atOutputFrame:)`, el mismo de `currentTime` y del ancla). Tolerancia: 1 ms.
    @MainActor
    func testStretchLatencyAndPositionErrorAt100_70_50() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let song = 12.0, from = 0.3
        // Fondo de ruido a −50 dBFS: como en un tema, Signalsmith nunca entra en su modo de silencio (que copia la entrada).
        var seed: UInt32 = 99
        var x: [Float] = (0..<Int(song * sr)).map { _ in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Float(Int32(bitPattern: seed)) / Float(Int32.max) * 0.003
        }
        let marks = stride(from: 0.5, through: 11.5, by: 0.5).map { $0 }
        for t in marks { addBurst(&x, at: t) }
        let p = try player([x], in: dir)
        p.forceStretchForTests = true
        let e = try XCTUnwrap(p.engineForTests)
        let inLat = e.stretchInputLatency, outLat = e.stretchOutputLatency
        // 100/70/50 %: los del informe, tolerancia 1 ms. El resto, para ver la dispersión del vocoder de fase
        // (sin desfase sistemático: no hay latencia residual que compensar), 2 ms.
        for rate in [1.0, 0.7, 0.5, 0.6, 0.8, 0.9, 1.25, 1.5, 2.0] {
            let tolerance = [1.0, 0.7, 0.5].contains(rate) ? 0.001 : 0.002
            p.pause()
            p.rate = rate
            p.seek(to: from)
            try p.play()
            let r = try p.renderOffline(frames: Int((song - from) / rate * sr) + Int(sr))
            let i0 = p.runStartFrame - Double(r.start)
            var errors: [Double] = []
            var timeErr = 0.0
            for t in marks {
                let expected = i0 + p.modelLatencyFrames + (t - from) * sr / rate
                let c = centroid(r.channels[0], around: expected, half: 4_800)
                errors.append(c - expected)
                // El reloj guarda 20 s de tramos (`StudyPlayerConstants.historySeconds`): solo las marcas recientes.
                if Double(r.channels[0].count) - c < 18 * sr {
                    let st = p.songTime(atOutputFrame: Double(r.start) + c)
                    timeErr = max(timeErr, abs(st - t) * 1_000)
                }
            }
            let mean = errors.reduce(0, +) / Double(errors.count)
            let worst = errors.map(abs).max()!
            let uncompensated = Double(outLat) + Double(inLat) / rate
            print(String(format: "7.6 Signalsmith %.0f %%: latencia entrada %d + salida %d (sin compensar %.1f muestras = %.2f ms); tras outputSeek error medio %+.2f, máx |error| %.2f muestras (%.3f ms), %d ráfagas; currentTime ±%.3f ms",
                         rate * 100, inLat, outLat, uncompensated, uncompensated / sr * 1_000, mean, worst, worst / sr * 1_000,
                         errors.count, timeErr))
            XCTAssertLessThan(worst, tolerance * sr, "\(rate)")
            XCTAssertLessThan(timeErr, tolerance * 1_000, "\(rate)")
        }
    }

    // MARK: Continuidad

    /// Tono de 400 Hz (salto natural máximo entre muestras 0,3·2π·400/48000 = 0,0157). Bucle de 0,90131 s (no cabe un
    /// número entero de periodos: el corte cae a media fase) y búsqueda en marcha a 100 % y 70 %. El mayor salto en el
    /// empalme no debe pasar de 1,5 veces el natural.
    @MainActor
    func testLoopAndSeekSplicesHaveNoSteps() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let natural = Float(0.3 * 2 * Double.pi * 400 / sr)
        let p = try player([sine(8, 400, 0.3)], in: dir)
        let skip = Int(0.05 * sr)
        for rate in [1.0, 0.7] {
            p.pause()
            p.loop = 1.0...1.90131
            p.rate = rate
            p.seek(to: 1.5)
            try p.play()
            let a = try p.renderOffline(frames: Int(3 * sr))
            let i0 = Int(p.runStartFrame - Double(a.start))
            let loopStep = maxStep(a.channels[0], from: i0 + skip, to: a.channels[0].count)

            p.pause()
            p.loop = nil
            p.seek(to: 1.0)
            try p.play()
            let b = try p.renderOffline(frames: Int(0.3 * sr))
            p.seek(to: 3.123)
            let c = try p.renderOffline(frames: Int(0.3 * sr))
            let joined = b.channels[0] + c.channels[0]
            let cut = b.channels[0].count
            let seekStep = maxStep(joined, from: cut - Int(0.01 * sr), to: cut + Int(0.01 * sr))
            print(String(format: "7.6 empalmes %.0f %%: salto máx en bucle %.4f, al buscar %.4f (natural %.4f)",
                         rate * 100, loopStep, seekStep, natural))
            XCTAssertLessThan(loopStep, 1.5 * natural, "bucle \(rate)")
            XCTAssertLessThan(seekStep, 1.5 * natural, "buscar \(rate)")
        }
    }

    // MARK: Remuestreo a la frecuencia de salida

    /// Stems a 48 kHz, salida a 44,1 kHz (r8brain por stem en el lector): la ráfaga cae donde dice el modelo (±1 muestra
    /// de salida) y la duración escala con la frecuencia.
    @MainActor
    func testResampledOutputKeepsPositions() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var x = [Float](repeating: 0, count: Int(4 * sr))
        let marks = [0.5, 1.5, 2.5, 3.5]
        for t in marks { addBurst(&x, at: t) }
        let url = dir.appendingPathComponent("s.wav")
        try TakeFile.write([x, x], sampleRate: sr, to: url)
        let out = 44_100.0
        let p = PortableStudyPlayer(offlineAt: out)
        try p.load(tracks: [Track(id: "s", url: url)])
        try p.play()
        let r = try p.renderOffline(frames: Int(4 * out))
        let i0 = p.runStartFrame - Double(r.start)
        var worst = 0.0
        for t in marks {
            let expected = i0 + t * out
            let c = centroid(r.channels[0], around: expected, half: 1_000)
            worst = max(worst, abs(c - expected))
        }
        print(String(format: "7.6 remuestreo 48 → 44,1 kHz: máx |error| %.3f muestras de salida", worst))
        XCTAssertLessThan(worst, 1)
    }

    // MARK: Para el oído de Jorge (solo Mac, TF_76_LISTEN=1)

    #if canImport(AVFoundation)
    /// El mismo pasaje de 18 s del stem de guitarra de T1 (P4, no versionado) al 70 % y al 70 % con −2 semitonos, con el
    /// TimePitch de Apple y con Signalsmith → `Temp/win/listen/CHECK_player_{mac,signalsmith}_70[_pitchm2].wav`.
    @MainActor
    func testWriteCheckPlayerWAVs() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TF_76_LISTEN"] == "1", "TF_76_LISTEN=1 para generar los WAV")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../..").standardizedFileURL
        let guitar = root.appendingPathComponent("Probes/P4-modelos/bs_roformer_sw/out/stems/T1/guitar.wav")
        let fs = try AudioFileReader(url: guitar).sampleRate
        let outDir = root.appendingPathComponent("Temp/win/listen")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        for (kind, name) in [(PlayerKind.platform, "mac"), (.portable, "signalsmith")] {
            for (cents, suffix) in [(0.0, ""), (-200.0, "_pitchm2")] {
                let p = kind.offline()
                try p.load(tracks: [Track(id: "guitar", url: guitar)])
                p.rate = 0.7
                p.pitchCents = cents
                p.seek(to: 30)
                try p.play()
                let r = try p.renderOffline(frames: Int(18 * fs))
                let url = outDir.appendingPathComponent("CHECK_player_\(name)_70\(suffix).wav")
                try TakeFile.write(r.channels, sampleRate: fs, to: url)
                let peak = r.channels[0].map(abs).max() ?? 0
                print(String(format: "7.6 escucha: %@ (%.0f Hz, pico %.3f)", url.path, fs, peak))
                XCTAssertGreaterThan(peak, 0.001)
            }
        }
    }
    #endif

    // MARK: CPU

    /// 6 stems estéreo (tonos y ruido), 10 s de salida a 100 % (suma exacta) y a 70 % (Signalsmith). Incluye la lectura de
    /// los ficheros (offline va en el mismo hilo). En Debug Signalsmith y r8brain van sin optimizar (NativeKit congelado):
    /// es una cota alta.
    @MainActor
    func testCPUWithSixStereoStems() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var seed: UInt32 = 7
        let stems: [[Float]] = (0..<6).map { k in
            sine(20, 110 * Double(k + 1), 0.1).map { v in
                seed = seed &* 1_664_525 &+ 1_013_904_223
                return v + Float(Int32(bitPattern: seed)) / Float(Int32.max) * 0.02
            }
        }
        let p = try player(stems, in: dir)
        let seconds = 10.0
        for rate in [1.0, 0.7] {
            p.pause()
            p.rate = rate
            p.seek(to: 0)
            try p.play()
            let t0 = Date()
            _ = try p.renderOffline(frames: Int(seconds * sr))
            let dt = Date().timeIntervalSince(t0)
            print(String(format: "7.6 CPU 6 stems estéreo a %.0f %%: %.1f ms por segundo de audio (%.1f %% de un núcleo)",
                         rate * 100, dt / seconds * 1_000, dt / seconds * 100))
            XCTAssertLessThan(dt / seconds, 0.5, "\(rate)")
        }
    }
}
