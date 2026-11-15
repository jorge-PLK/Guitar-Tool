import CoreAudio
import Foundation
import P2Core

// Constantes del encargo de P2.
/// Nivel del barrido enviado (dBFS): -12 dBFS, con margen para no saturar la entrada de la pedalera.
let sweepAmplitude: Float = 0.25
/// Duración del barrido de backing-test (s), con silencio antes y después.
let sweepSeconds = 8.0
let sweepPreRollSeconds = 1.0
let sweepTailSeconds = 2.0
/// Por encima de este nivel (dB relativos a lo enviado) el retorno mezcla lo que se envía por USB.
let backingMixThresholdDb = -60.0
/// Clics de latencia: primer clic y separación (s).
let clickFirstSeconds = 0.5
let clickSpacingSeconds = 1.0
/// Cola tras el DI en reamp (s).
let reampTailSeconds = 1.0

enum Commands {
    static func device(_ a: Args) throws -> DeviceInfo {
        let d = try DeviceInfo.find(try a.require("device"))
        if let b = a.string("buffer") {
            guard let n = UInt32(b) else { throw Failure("--buffer no es un entero: \(b)") }
            try d.setBufferFrames(n)
            return try DeviceInfo.find(d.uid)
        }
        return d
    }

    // MARK: list

    static func list(_ a: Args) throws {
        let out = try Out.dir(a.string("out") ?? "out")
        var json: [[String: Any]] = []
        for (i, d) in DeviceInfo.all().enumerated() {
            Log.say("[\(i + 1)] \(d.name)  (uid \(d.uid), \(d.transport), \(d.manufacturer))")
            Log.say("    entradas \(d.inputChannels) · salidas \(d.outputChannels) · nominal \(Int(d.nominalRate)) Hz · admite " + d.rates.map { $0.mMinimum == $0.mMaximum ? "\(Int($0.mMinimum))" : "\(Int($0.mMinimum))-\(Int($0.mMaximum))" }.joined(separator: ", "))
            Log.say("    búfer \(d.bufferFrames) (rango \(d.bufferRange.map { "\(Int($0.mMinimum))-\(Int($0.mMaximum))" } ?? "n/d"))")
            for (label, dir) in [("in ", d.input), ("out", d.output)] where dir.channels > 0 {
                Log.say("    latencia \(label): dispositivo \(dir.deviceLatency) + safety \(dir.safetyOffset) + stream \(dir.streamLatency) = \(dir.totalLatency) muestras")
                let names = dir.names.enumerated().map { "\($0.offset + 1):\($0.element ?? "-")" }.joined(separator: " ")
                Log.say("    canales \(label): \(names)")
            }
            Log.say("    ida y vuelta declarada (in + out + 2 búferes): \(d.declaredRoundTripFrames) muestras" + (d.nominalRate > 0 ? " = \(f2(Double(d.declaredRoundTripFrames) / d.nominalRate * 1000)) ms" : ""))
            func dirJSON(_ x: DirectionInfo) -> [String: Any] {
                ["channels": x.channels, "channelNames": x.names.map { $0 ?? NSNull() as Any },
                 "deviceLatency": Int(x.deviceLatency), "safetyOffset": Int(x.safetyOffset),
                 "streamLatencies": x.streams.map { Int($0.latency) }, "totalLatency": Int(x.totalLatency),
                 "streamFormats": x.streams.map { s -> Any in
                     guard let f = s.format else { return NSNull() }
                     return ["rate": f.mSampleRate, "bitsPerChannel": Int(f.mBitsPerChannel), "channelsPerFrame": Int(f.mChannelsPerFrame),
                             "float": f.mFormatFlags & kAudioFormatFlagIsFloat != 0, "interleaved": f.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0] as [String: Any]
                 }]
            }
            json.append(["name": d.name, "uid": d.uid, "manufacturer": d.manufacturer, "transport": d.transport,
                         "input": dirJSON(d.input), "output": dirJSON(d.output),
                         "nominalRate": d.nominalRate,
                         "availableRates": d.rates.map { ["min": $0.mMinimum, "max": $0.mMaximum] },
                         "bufferFrames": Int(d.bufferFrames),
                         "bufferRange": d.bufferRange.map { ["min": $0.mMinimum, "max": $0.mMaximum] } ?? NSNull(),
                         "declaredRoundTripFrames": Int(d.declaredRoundTripFrames)])
        }
        try Out.json(["date": iso8601(), "devices": json], to: out.appendingPathComponent("list.json"))
        Log.say("Detalle: \(out.path)/list.json")
    }

    // MARK: record

    static func record(_ a: Args) throws {
        let dev = try device(a)
        let seconds = try a.double("seconds")
        let out = try Out.dir(try a.require("out"))
        Log.say("Grabando \(f1(seconds)) s de \(dev.name): \(dev.inputChannels) canales a \(Int(dev.nominalRate)) Hz, búfer \(dev.bufferFrames)...")
        let r = try Session.run(dev: dev, seconds: seconds)
        try Out.writeChannels(r.inputs, fs: r.sampleRate, to: out)
        var chans: [[String: Any]] = []
        for (i, x) in r.inputs.enumerated() {
            Log.say("  ch\(String(format: "%02d", i + 1)): RMS \(f1(rmsDb(x))) dBFS · pico \(f1(peakDb(x))) dBFS")
            chans.append(["channel": i + 1, "name": dev.input.names[i] ?? NSNull(), "rmsDb": rmsDb(x), "peakDb": peakDb(x)])
        }
        reportHealth(r)
        var j = deviceHeader(dev)
        j["command"] = "record"; j["seconds"] = seconds; j["channels"] = chans; j["session"] = sessionJSON(r)
        try Out.json(j, to: out.appendingPathComponent("record.json"))
        Log.say("WAV en \(out.path)/chNN.wav; detalle en record.json")
    }

    // MARK: analyze

    static func analyze(_ a: Args) throws {
        guard let path = a.positional.first else { throw Failure("Uso: p2 analyze <dir>") }
        guard FileManager.default.fileExists(atPath: path) else { throw Failure("No existe \(path).") }
        let dir = try Out.dir(path)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("ch") && $0.hasSuffix(".wav") }.sorted()
        guard !files.isEmpty else { throw Failure("No hay ch*.wav en \(path).") }
        var fs = 0.0
        var chans: [[Float]] = []
        for f in files {
            let w = try WAV.read(dir.appendingPathComponent(f))
            fs = w.sampleRate
            chans.append(w.channels[0])
        }
        let rep = Analyzer.analyze(channels: chans, fs: fs)
        Log.say("Análisis de \(files.count) canales (\(Int(fs)) Hz):")
        Log.say("  canal   RMS dBFS   pico dBFS   cresta dB   centroide Hz   limpieza")
        for (f, s) in zip(files, rep.channels) {
            Log.say(String(format: "  %@   %8.1f   %9.1f   %9.1f   %12.0f   %@", String(f.dropLast(4)), s.rmsDb, s.peakDb, s.crestDb,
                           s.centroidHz.isFinite ? s.centroidHz : 0, s.dryScore.map { f1($0) } ?? "inactivo"))
        }
        if chans.count > 1 {
            Log.say("  correlación máx (±10 ms) [retardo muestras del col respecto a la fila]:")
            for i in 0..<chans.count {
                Log.say("   " + (0..<chans.count).map { j in i == j ? "  ---  " : String(format: "%.2f(%d)", rep.bestCorrelation[i][j], rep.bestLagSamples[i][j]) }.joined(separator: "  "))
            }
        }
        Log.say("  " + rep.note)
        let j: [String: Any] = [
            "command": "analyze", "sampleRate": fs, "files": files,
            "channels": rep.channels.map { ["index": $0.index + 1, "rmsDb": $0.rmsDb, "peakDb": $0.peakDb, "crestDb": $0.crestDb,
                                            "centroidHz": $0.centroidHz, "active": $0.active, "dryScore": $0.dryScore ?? NSNull()] as [String: Any] },
            "correlationZeroLag": rep.correlation, "correlationBest": rep.bestCorrelation, "bestLagSamples": rep.bestLagSamples,
            "suggestedDI": rep.suggestedDI.map { $0 + 1 } ?? NSNull(), "suggestedProcessed": rep.suggestedProcessed.map { $0 + 1 } ?? NSNull(),
            "note": rep.note,
        ]
        try Out.json(j, to: dir.appendingPathComponent("analyze.json"))
        Log.say("Detalle: \(dir.path)/analyze.json")
    }

    // MARK: backing-test

    static func backingTest(_ a: Args) throws {
        let dev = try device(a)
        let outCh = try a.channels("out-ch", max: dev.outputChannels)
        let out = try Out.dir(a.string("out") ?? "out")
        let fs = dev.nominalRate
        let sweep = Signals.logSweep(fs: fs, seconds: sweepSeconds, amplitude: sweepAmplitude)
        let pre = Int(sweepPreRollSeconds * fs), tail = Int(sweepTailSeconds * fs)
        let play = [Float](repeating: 0, count: pre) + sweep + [Float](repeating: 0, count: tail)
        Log.say("Barrido 20 Hz-20 kHz (\(f1(dB(Double(sweepAmplitude)))) dBFS, \(f1(sweepSeconds)) s) por salidas \(outCh.map { $0 + 1 }) de \(dev.name); grabando \(dev.inputChannels) entradas...")
        let r = try Session.run(dev: dev, seconds: Double(play.count) / fs, play: play, outChannels: outCh)
        try Out.writeChannels(r.inputs, fs: fs, to: out.appendingPathComponent("backing-rec", isDirectory: true).createDir())
        var rows: [[String: Any]] = []
        var mixing: [Int] = []
        var inconclusive: [Int] = []
        Log.say("  entrada   nivel vs enviado   suelo     retardo (muestras / ms)   veredicto")
        for (i, x) in r.inputs.enumerated() {
            let m = Detectors.measureSweep(sweep: sweep, received: x)
            let lag = m.lagSamples - pre
            let mixes = m.detected && m.levelDb > backingMixThresholdDb
            if mixes { mixing.append(i + 1) }
            // Sin barrido detectado solo se puede afirmar "no mezcla" si el suelo de la medida está bien por debajo del umbral.
            let conclusive = m.detected || m.floorDb + Detectors.detectionMarginDb < backingMixThresholdDb
            if !conclusive { inconclusive.append(i + 1) }
            let verdict = mixes ? "MEZCLA el envío USB"
                : (!conclusive ? "INCONCLUSO: suelo \(f1(m.floorDb)) dB (¿suena algo en la entrada? no toques la guitarra)"
                   : (m.detected ? "no mezcla (< \(Int(backingMixThresholdDb)) dB)" : "no mezcla (barrido no detectado, suelo \(f1(m.floorDb)) dB)"))
            Log.say(String(format: "  %7d   %12@ dB   %6@ dB   %6d / %@   %@", i + 1, f1(m.levelDb), f1(m.floorDb), lag, f2(Double(lag) / fs * 1000), verdict))
            rows.append(["input": i + 1, "name": dev.input.names[i] ?? NSNull(), "levelDb": m.levelDb, "floorDb": m.floorDb,
                         "peakToFloorDb": m.peakToFloorDb, "detected": m.detected, "lagSamples": lag, "lagMs": Double(lag) / fs * 1000,
                         "mixesBacking": mixes, "conclusive": conclusive])
        }
        if !inconclusive.isEmpty { Log.say("AVISO: medida inconclusa en las entradas \(inconclusive); repite sin tocar la guitarra.") }
        Log.say(mixing.isEmpty ? "RESULTADO: ninguna entrada contiene el envío USB por encima de \(Int(backingMixThresholdDb)) dB."
                               : "RESULTADO: las entradas \(mixing) contienen lo que se envía por USB (por encima de \(Int(backingMixThresholdDb)) dB).")
        reportHealth(r)
        var j = deviceHeader(dev)
        j["command"] = "backing-test"; j["outChannels"] = outCh.map { $0 + 1 }; j["thresholdDb"] = backingMixThresholdDb
        j["sweepDbFS"] = dB(Double(sweepAmplitude)); j["inputs"] = rows; j["inputsMixingBacking"] = mixing; j["session"] = sessionJSON(r)
        try Out.json(j, to: out.appendingPathComponent("backing-test.json"))
        Log.say("Detalle: \(out.path)/backing-test.json")
    }

    // MARK: latency

    static func latency(_ a: Args) throws {
        let dev = try device(a)
        let outCh = try a.channels("out-ch", max: dev.outputChannels)
        let inCh = try a.channels("in-ch", max: dev.inputChannels)
        guard outCh.count == 1, inCh.count == 1 else { throw Failure("latency usa un solo canal: --out-ch a --in-ch b.") }
        let reps = try a.int("reps", default: 10)
        guard reps >= 1 else { throw Failure("--reps debe ser >= 1.") }
        let out = try Out.dir(a.string("out") ?? "out")
        let fs = dev.nominalRate
        let tpl = Signals.Click.template(fs: fs)
        let sentAt = (0..<reps).map { Int((clickFirstSeconds + Double($0) * clickSpacingSeconds) * fs) }
        let total = Int((clickFirstSeconds + Double(reps) * clickSpacingSeconds + 0.5) * fs)
        var play = [Float](repeating: 0, count: total)
        for p in sentAt { for (i, v) in tpl.enumerated() { play[p + i] = v } }
        Log.say("Latencia: \(reps) clics por salida \(outCh[0] + 1) → entrada \(inCh[0] + 1) de \(dev.name), búfer \(dev.bufferFrames)...")
        let r = try Session.run(dev: dev, seconds: Double(total) / fs, play: play, outChannels: outCh)
        let res = Detectors.measureClicks(fs: fs, sentAt: sentAt, received: r.inputs[inCh[0]])
        if res.samples.isEmpty {
            reportHealth(r)
            throw Failure("No se detectó ningún clic en la entrada \(inCh[0] + 1) (¿está el retorno por USB habilitado y sin silenciar? ¿Es esa la entrada correcta?). Nivel de la entrada: RMS \(f1(rmsDb(r.inputs[inCh[0]]))) dBFS.")
        }
        Log.say("  válidos \(res.samples.count)/\(reps)")
        Log.say("  media  \(f2(res.mean)) muestras = \(f2(res.ms(res.mean))) ms")
        Log.say("  desv.  \(f2(res.std)) muestras = \(f2(res.ms(res.std))) ms")
        Log.say("  mín    \(f2(res.min)) muestras = \(f2(res.ms(res.min))) ms")
        Log.say("  máx    \(f2(res.max)) muestras = \(f2(res.ms(res.max))) ms")
        Log.say("  declarada por el dispositivo (in + out + 2 búferes): \(dev.declaredRoundTripFrames) muestras = \(f2(Double(dev.declaredRoundTripFrames) / fs * 1000)) ms")
        reportHealth(r)
        var j = deviceHeader(dev)
        j["command"] = "latency"; j["outChannel"] = outCh[0] + 1; j["inChannel"] = inCh[0] + 1; j["reps"] = reps
        j["validReps"] = res.samples.count; j["samples"] = res.samples
        j["meanSamples"] = res.mean; j["stdSamples"] = res.std; j["minSamples"] = res.min; j["maxSamples"] = res.max
        j["meanMs"] = res.ms(res.mean); j["stdMs"] = res.ms(res.std); j["minMs"] = res.ms(res.min); j["maxMs"] = res.ms(res.max)
        j["declaredRoundTripFrames"] = Int(dev.declaredRoundTripFrames); j["session"] = sessionJSON(r)
        try Out.json(j, to: out.appendingPathComponent("latency.json"))
        Log.say("Detalle: \(out.path)/latency.json")
    }

    // MARK: reamp

    static func reamp(_ a: Args) throws {
        let dev = try device(a)
        let outCh = try a.channels("out-ch", max: dev.outputChannels)
        let out = try Out.dir(try a.require("out"))
        let fs = dev.nominalRate
        let wav = try WAV.read(URL(fileURLWithPath: try a.require("di")))
        var di = wav.channels[0]
        if wav.channels.count > 1 { Log.say("  AVISO: el DI tiene \(wav.channels.count) canales; se usa el primero.") }
        if abs(wav.sampleRate - fs) > 0.5 {
            Log.say("  AVISO: el DI está a \(Int(wav.sampleRate)) Hz y el dispositivo a \(Int(fs)) Hz; remuestreo lineal (usa un DI grabado a la frecuencia nominal).")
            let ratio = wav.sampleRate / fs
            let n = Int(Double(di.count) / ratio)
            let src = di
            di = (0..<n).map { i in
                let p = Double(i) * ratio, k = Int(p), f = Float(p - Double(k))
                return k + 1 < src.count ? src[k] * (1 - f) + src[k + 1] * f : src[min(k, src.count - 1)]
            }
        }
        let peak = peakDb(di)
        if peak > -0.1 { Log.say("  AVISO: el DI llega a \(f1(peak)) dBFS; puede saturar la entrada de la pedalera.") }
        let latencyMs = a.string("latency-ms") != nil ? try a.double("latency-ms") : nil
        let lat = latencyMs.map { Int(($0 / 1000 * fs).rounded()) } ?? 0
        let seconds = Double(di.count + lat) / fs + reampTailSeconds
        Log.say("Reamp: \(f1(Double(di.count) / fs)) s de DI (pico \(f1(peak)) dBFS) por salidas \(outCh.map { $0 + 1 }); grabando \(dev.inputChannels) entradas...")
        let r = try Session.run(dev: dev, seconds: seconds, play: di, outChannels: outCh)
        let aligned: [[Float]] = r.inputs.map { x in
            (0..<di.count).map { i in i + lat < x.count ? x[i + lat] : 0 }
        }
        try Out.writeChannels(aligned, fs: fs, to: out)
        if lat > 0 { try Out.writeChannels(r.inputs, fs: fs, to: out.appendingPathComponent("raw", isDirectory: true).createDir()) }
        var chans: [[String: Any]] = []
        for (i, x) in aligned.enumerated() {
            Log.say("  ch\(String(format: "%02d", i + 1)): RMS \(f1(rmsDb(x))) dBFS · pico \(f1(peakDb(x))) dBFS")
            chans.append(["channel": i + 1, "rmsDb": rmsDb(x), "peakDb": peakDb(x)])
        }
        Log.say(lat > 0 ? "  Alineado: recortadas \(lat) muestras (\(f2(Double(lat) / fs * 1000)) ms) del inicio; brutos en \(out.path)/raw"
                        : "  Sin --latency-ms: grabación sin alinear (el DI empieza en la muestra 0 de la grabación + latencia).")
        reportHealth(r)
        var j = deviceHeader(dev)
        j["command"] = "reamp"; j["di"] = try a.require("di"); j["outChannels"] = outCh.map { $0 + 1 }
        j["latencyMs"] = latencyMs ?? NSNull(); j["trimmedSamples"] = lat; j["diFrames"] = di.count
        j["channels"] = chans; j["session"] = sessionJSON(r)
        try Out.json(j, to: out.appendingPathComponent("reamp.json"))
        Log.say("WAV en \(out.path)/chNN.wav; detalle en reamp.json")
    }

    // MARK: soak

    static func soak(_ a: Args) throws {
        let dev = try device(a)
        let minutes = try a.double("minutes", default: 5)
        let out = try Out.dir(try a.require("out"))
        Log.say("Soak: \(f1(minutes)) min de \(dev.name) (\(dev.inputChannels) canales, \(Int(dev.nominalRate)) Hz, búfer \(dev.bufferFrames)). No toques el USB ni suspendas el Mac.")
        let r = try Session.run(dev: dev, seconds: minutes * 60)
        let fs = r.sampleRate
        let perMinute = Int(60 * fs)
        var chans: [[String: Any]] = []
        for (i, x) in r.inputs.enumerated() {
            var mins: [Double] = []
            var s = 0
            while s < x.count { mins.append(rmsDb(Array(x[s..<min(x.count, s + perMinute)]))); s += perMinute }
            Log.say("  ch\(String(format: "%02d", i + 1)): RMS \(f1(rmsDb(x))) dBFS · pico \(f1(peakDb(x))) dBFS · RMS por minuto \(mins.map(f1).joined(separator: ", "))")
            chans.append(["channel": i + 1, "rmsDb": rmsDb(x), "peakDb": peakDb(x), "rmsDbPerMinute": mins])
        }
        reportHealth(r)
        var j = deviceHeader(dev)
        j["command"] = "soak"; j["minutes"] = minutes; j["channels"] = chans; j["session"] = sessionJSON(r)
        if let d = Session.driftPPM(r.stamps, nominal: fs) {
            Log.say("  deriva del reloj del dispositivo respecto al del Mac: \(f2(d.ppm)) ppm (residuo máx de la regresión \(f2(d.residualMaxMs)) ms)")
            j["clockDriftPPM"] = d.ppm; j["clockDriftResidualMaxMs"] = d.residualMaxMs
        } else {
            Log.say("  deriva del reloj: no medible (pocas marcas de tiempo válidas).")
        }
        if a.flag("keep-wav") {
            try Out.writeChannels(r.inputs, fs: fs, to: out)
            Log.say("  WAV guardados en \(out.path)")
        }
        try Out.json(j, to: out.appendingPathComponent("soak.json"))
        Log.say("Detalle: \(out.path)/soak.json")
    }

    // MARK: selftest

    static func selftest(_ a: Args) throws {
        let out = try Out.dir(a.string("out") ?? "out")
        // Toma sintética en out/selftest-take para probar `p2 analyze` de punta a punta.
        let takeDir = try out.appendingPathComponent("selftest-take", isDirectory: true).createDir()
        try Out.writeChannels(SelfTest.syntheticTake(fs: 48_000), fs: 48_000, to: takeDir)
        let checks = SelfTest.run()
        for c in checks {
            Log.say("  \(c.pass ? "OK  " : "FALLO") \(c.name): esperado \(f2(c.expected)) ± \(f2(c.tolerance)) \(c.unit), obtenido \(String(format: "%.3f", c.got))")
        }
        let failed = checks.filter { !$0.pass }.count
        Log.say("selftest: \(checks.count - failed)/\(checks.count) correctas")
        try Out.json(["command": "selftest", "checks": checks.map { ["name": $0.name, "expected": $0.expected, "got": $0.got, "tolerance": $0.tolerance, "pass": $0.pass] as [String: Any] }],
                     to: out.appendingPathComponent("selftest.json"))
        if failed > 0 { throw Failure("\(failed) comprobaciones fallidas.") }
    }
}

extension URL {
    func createDir() throws -> URL {
        try FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
        return self
    }
}
