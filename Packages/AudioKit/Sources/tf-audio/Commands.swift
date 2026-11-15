import AudioKit
import Foundation

/// Códigos de salida: 0 bien, 1 medida fuera de tolerancia, 2 error de uso o de dispositivo.
enum Exit {
    static let ok: Int32 = 0
    static let outOfTolerance: Int32 = 1
    static let error: Int32 = 2
}

enum CLI {
    /// Variación máxima de la latencia entre reinicios del motor (mini-spec Fase 3, «Calibración de latencia»:
    /// «Pendiente de medir con hardware»); por encima, la regla pasa a calibrar por sesión.
    static let restartToleranceMs = 0.25
    /// Dispersión máxima de la calibración, en ms (mini-spec Fase 3, «Resultado»).
    static let spreadLimitMs = LatencyProbe.maxSpreadSeconds * 1000
    /// Pausa entre cerrar y abrir al repetir con `--restarts` (decisión propia: dejar al driver asentarse).
    static let restartPauseSeconds = 1.0

    static let help = """
    tf-audio: medidas de audio con el dispositivo (herramienta de desarrollo de ToneForge)

    Uso: tf-audio <devices|latency|verify|record> [opciones]

      devices
          Lista los dispositivos con UID, canales de entrada y salida, frecuencia actual y admitidas.
          Ejemplo: tf-audio devices

      latency --in <uid|nombre> --out <uid|nombre> --guitar <c[,c]> [--backing l,r] [--rate 44100|48000] [--restarts N]
          Mide la latencia de ida y vuelta con un cable de la salida a la entrada. Guarda el resultado en
          Temp/tf-audio/calibration.json. Con --restarts N repite abriendo y cerrando la sesión.
          Ejemplo: tf-audio latency --in flex --out flex --guitar 1,2 --backing 1,2 --restarts 5

      verify <mismas opciones> [--seconds 60]
          Reproduce clics por el backing, graba la vuelta, alinea y da el error de cada clic.
          Pasa si el máximo es menor de 1 ms. WAV en Temp/tf-audio/verify.wav.
          Ejemplo: tf-audio verify --in flex --out flex --guitar 1,2 --seconds 60

      record <mismas opciones> --seconds N [--song <wav>]
          Graba una toma de N s (con el WAV como backing si se da) en Temp/tf-audio/take-<fecha>.wav.
          Ejemplo: tf-audio record --in flex --out flex --guitar 1,2 --seconds 30 --song tema.wav

    Opciones comunes:
      --in, --out     UID del dispositivo o un trozo de su nombre (sin distinguir mayúsculas)
      --guitar        uno o dos canales de entrada con la guitarra procesada (desde 1)
      --backing       par de canales de salida del backing (por defecto 1,2)
      --rate          frecuencia de trabajo (por defecto, la actual del dispositivo)
      --simulated L   sin hardware: dispositivo simulado con latencia de L muestras (con decimales)
      --sim-rig R     con --simulated: retardo del rig de R muestras y canal de referencia interno
      --sim-miscalibrate M   con --simulated: alinea con M muestras de más (para comprobar que verify falla)

    Salida: 0 bien, 1 medida fuera de tolerancia, 2 error de uso o de dispositivo.
    Ejemplo sin hardware: tf-audio verify --simulated 2400.81 --seconds 20
    """

    static func run(_ args: [String], env: Env) async -> Int32 {
        do {
            let o = try Parse.options(args)
            if o.help {
                env.line(help)
                return Exit.ok
            }
            switch o.command {
            case .devices: return devices(env)
            case .latency: return try await latency(o, env)
            case .verify: return try await verify(o, env)
            case .record: return try await record(o, env)
            }
        } catch let e as CLIError {
            env.line("Error: \(e.description)")
            return Exit.error
        } catch {
            env.line("Error: \(error)")
            return Exit.error
        }
    }

    // MARK: devices

    static func devices(_ env: Env) -> Int32 {
        let p = CoreAudioDeviceProvider()
        var byUID: [String: AudioDevice] = [:]
        for d in p.inputDevices() + p.outputDevices() { byUID[d.uid] = d }
        let list = byUID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let defaultOut = p.defaultOutputDevice()?.uid
        if list.isEmpty { env.line("No hay dispositivos de audio.") }
        for d in list {
            env.line("Dispositivo: \(d.name)\(d.uid == defaultOut ? " (salida por defecto)" : "")")
            env.line("  UID: \(d.uid)")
            env.line("  Canales de entrada: \(d.inputChannels)")
            env.line("  Canales de salida: \(d.outputChannels)")
            env.line("  Frecuencia actual: \(d.nominalSampleRate.map { "\(Int($0)) Hz" } ?? "desconocida")")
            env.line("  Frecuencias admitidas: \(d.sampleRates.isEmpty ? "no declaradas" : d.sampleRates.map { "\(Int($0))" }.joined(separator: ", ")) Hz")
        }
        return Exit.ok
    }

    // MARK: latency

    static func ms(_ samples: Double, _ fs: Double) -> String { (samples / fs * 1000).fixed(3) }

    static func describe(_ f: LatencyFailure) -> String {
        switch f {
        case .noSignal: return "sin señal (falta el cable o el volumen de salida está muy bajo)"
        case .saturated: return "saturada (baja el volumen de salida)"
        case .unstable: return "inestable (la dispersión pasa de \(spreadLimitMs.fixed(1)) ms)"
        }
    }

    static func clockText(_ c: AudioIOClock?) -> String {
        switch c {
        case .single: return "un dispositivo (un solo reloj)"
        case .aggregate: return "agregado privado (salida como reloj maestro, corrección de deriva en la entrada)"
        case nil: return "desconocido"
        }
    }

    @MainActor
    static func report(_ r: LatencyCalibrationResult, rig: Rig, env: Env) {
        let fs = rig.fs
        env.line("Frecuencia de trabajo: \(Int(fs)) Hz")
        env.line("Reloj: \(clockText(rig.session.clock))")
        if let io = rig.ioBox.get() {
            env.line("Latencia declarada por el dispositivo: \(io.declaredLatencySamples.fixed(1)) muestras (\(ms(io.declaredLatencySamples, fs)) ms)")
        }
        env.line("Latencia medida (canal \(r.guitarIn.first ?? 1)): \(r.latencySamples.fixed(2)) muestras (\(ms(r.latencySamples, fs)) ms)")
        env.line("Dispersión: \(r.spreadSamples.fixed(2)) muestras (\(ms(r.spreadSamples, fs)) ms; límite \(spreadLimitMs.fixed(1)) ms)")
        env.line("Pico sobre el fondo: \(r.guitar.peakToFloorDB.fixed(1)) dB (mínimo \(LatencyProbe.minPeakToFloorDB.fixed(0)) dB)")
        env.line("Pico de entrada: \(Double(r.guitar.inputPeak).fixed(3)) (1 = fondo de escala)")
        if let f = r.failure { env.line("Validez: NO válida, \(describe(f))") } else { env.line("Validez: válida") }
        if let ref = r.reference {
            env.line("Canal de referencia interno: canal \(ref.channel), \(ref.latencySamples.fixed(2)) muestras (\(ms(ref.latencySamples, fs)) ms)")
            if let rd = r.rigDelayAtCalibration { env.line("Retardo del rig en la calibración: \(rd.fixed(2)) muestras (\(ms(rd, fs)) ms)") }
        } else {
            env.line("Canal de referencia interno: ninguno")
        }
        for c in r.channels where c.channel != r.guitarIn.first {
            env.line("Canal \(c.channel): \(c.failure == nil ? "\(c.latencySamples.fixed(2)) muestras (\(ms(c.latencySamples, fs)) ms)" : "\(c.failure == .noSignal ? "sin señal" : "sin medida válida: \(describe(c.failure!))")")")
        }
    }

    @MainActor
    static func latency(_ o: Options, _ env: Env) async throws -> Int32 {
        let runs = o.restarts ?? 1
        var lat: [Double] = []
        var code = Exit.ok
        var fs = 0.0
        for i in 1...runs {
            let rig = try await Rig(o)
            fs = rig.fs
            if i == 1 {
                env.line("Entrada: \(rig.inputName)")
                env.line("Salida: \(rig.outputName)")
                env.line("Canales: guitarra \(rig.setup.guitarIn.map(String.init).joined(separator: ",")), backing \(rig.setup.backingLeft),\(rig.setup.backingRight)")
            }
            try rig.open()
            defer { rig.close() }
            if runs > 1 { env.line("Reinicio \(i) de \(runs)") }
            env.line("Calibrando (unos 6 s)…")
            let r = try await rig.calibrate()
            report(r, rig: rig, env: env)
            if r.isValid {
                lat.append(r.latencySamples)
                try StoredCalibration.save(r, to: env.calibrationURL)
                env.line("Calibración guardada en \(env.calibrationURL.path)")
            } else {
                code = Exit.outOfTolerance
            }
            if i < runs {
                rig.close()
                if rig.sim == nil { try await Task.sleep(for: .seconds(restartPauseSeconds)) }
            }
        }
        if runs > 1, lat.count > 1 {
            let spread = lat.max()! - lat.min()!
            let spreadMs = spread / fs * 1000
            env.line("Variación entre reinicios: \(spread.fixed(2)) muestras (\(spreadMs.fixed(3)) ms) en \(lat.count) reinicios válidos")
            if spreadMs > restartToleranceMs {
                env.line("Supera \(restartToleranceMs.fixed(2)) ms: la regla pasa a calibrar por sesión.")
                code = Exit.outOfTolerance
            } else {
                env.line("No supera \(restartToleranceMs.fixed(2)) ms: la calibración vale entre reinicios.")
            }
        }
        return code
    }

    // MARK: calibración guardada

    /// Calibración guardada si vale para la sesión abierta; si no, lo dice.
    @MainActor
    static func applySaved(to rig: Rig, env: Env) -> LatencyCalibrationResult? {
        guard let saved = StoredCalibration.load(from: env.calibrationURL) else {
            env.line("Sin calibración guardada.")
            return nil
        }
        guard let key = rig.session.calibrationKey, saved.applies(to: key) else {
            env.line("La calibración guardada (\(saved.date.formatted(date: .abbreviated, time: .shortened))) es de otra configuración o no es válida.")
            return nil
        }
        rig.session.calibration = saved
        env.line("Calibración guardada del \(saved.date.formatted(date: .abbreviated, time: .shortened)): \(saved.latencySamples.fixed(2)) muestras (\(ms(saved.latencySamples, rig.fs)) ms)")
        return saved
    }

    /// Para probar el fallo: el alineado usa `by` muestras de más.
    static func miscalibrated(_ c: LatencyCalibrationResult, by d: Double) -> LatencyCalibrationResult {
        var c = c
        c.channels[(c.guitarIn.first ?? 1) - 1].latencySamples += d
        if var r = c.reference {
            r.latencySamples += d
            c.reference = r
        }
        return c
    }

    // MARK: verify

    @MainActor
    static func verify(_ o: Options, _ env: Env) async throws -> Int32 {
        let seconds = o.seconds ?? AlignmentCheck.verifySeconds
        let rig = try await Rig(o)
        env.line("Entrada: \(rig.inputName)")
        env.line("Salida: \(rig.outputName)")
        try rig.open()
        defer { rig.close() }
        env.line("Frecuencia de trabajo: \(Int(rig.fs)) Hz · reloj: \(clockText(rig.session.clock))")
        var cal = applySaved(to: rig, env: env)
        if cal == nil {
            env.line("Calibrando antes (unos 6 s)…")
            let r = try await rig.calibrate()
            report(r, rig: rig, env: env)
            guard r.isValid else {
                env.line("NO PASA: la calibración no es válida, no se puede alinear.")
                return Exit.outOfTolerance
            }
            try StoredCalibration.save(r, to: env.calibrationURL)
            cal = r
        }
        if let d = o.simMiscalibration, let c = cal {
            rig.session.calibration = miscalibrated(c, by: d)
            env.line("Latencia mal aplicada a propósito: \(d.fixed(2)) muestras de más.")
        }

        let fs = rig.fs
        let backing = AlignmentCheck.backing(songSeconds: seconds + 2, sampleRate: fs)
        let backingURL = env.dir.appendingPathComponent("verify-backing.wav")
        try WavFile.write([backing, backing], sampleRate: fs, to: backingURL)
        let player = rig.makePlayer()
        try player.load(tracks: [Track(id: "clicks", url: backingURL)])
        try player.attach(to: rig.session)
        env.line("Reproduciendo y grabando \(seconds.fixed(0)) s de clics…")
        player.seek(to: 0)
        try player.play()
        try await rig.settle()
        let wavURL = env.dir.appendingPathComponent("verify.wav")
        let recordHost = CoreAudioIO.hostNowSeconds
        try rig.session.startRecording(to: wavURL)
        try await rig.advance(seconds: seconds)
        let take: RecordedTake
        do { take = try rig.session.stopRecording() } catch {
            player.pause()
            throw CLIError(((error as? LocalizedError)?.errorDescription ?? "\(error)"))
        }
        let hosted = player.hostedDiagnostics
        let io = rig.session.ioDiagnostics
        let timing = (rig.ioBox.get() as? CoreAudioIO)?.hostTimingReport()
        player.pause()

        let x = try WavFile.readFirstChannel(wavURL).samples
        let r = AlignmentCheck.measure(take: x, songStart: take.songStart, sampleRate: fs, songSeconds: seconds)
        let csvURL = env.dir.appendingPathComponent("verify-clicks.csv")
        try clicksCSV(r, songStart: take.songStart).write(to: csvURL, atomically: true, encoding: .utf8)
        env.line("WAV grabado: \(wavURL.path)")
        env.line("Error por clic: \(csvURL.path)")
        env.line("Inicio en el tema: \(take.songStart.fixed(6)) s (muestra \(Int((take.songStart * fs).rounded())))")
        env.line("Latencia usada: \(take.latencySamples.fixed(2)) muestras (\(ms(take.latencySamples, fs)) ms)\(take.latencyCalibrated ? "" : " (declarada, sin calibrar)")")
        if let rd = take.rigDelaySamples {
            env.line("Retardo del rig en la toma: \(rd.fixed(2)) muestras (\(ms(rd, fs)) ms), \(take.rigDelayReliable == true ? "fiable" : "no fiable")")
        }
        env.line("Clics medidos: \(r.clicks.count) de \(r.expectedClicks)")
        env.line("Error máximo: \(r.maxAbsErrorSamples.fixed(2)) muestras (\(r.maxAbsErrorMs.fixed(3)) ms; límite \((AlignmentCheck.passThresholdSeconds * 1000).fixed(0)) ms)")
        env.line("Error medio: \(r.meanErrorSamples.fixed(2)) muestras (\(ms(r.meanErrorSamples, fs)) ms)")
        env.line("Pendiente: \(r.slopeSamplesPerMinute.fixed(2)) muestras/min")
        if let worst = r.clicks.map(\.peakToFloorDB).filter({ $0.isFinite }).min() {
            env.line("Pico sobre el fondo de los clics: mínimo \(worst.fixed(1)) dB")
        }
        if let t = r.backgroundTone, !t.isFeedback {
            env.line("Tono de fondo: \(t.frequencyHz.fixed(1)) Hz a \(t.peakDBFS.fixed(1)) dBFS, despreciable.")
        }
        if let t = r.backgroundTone, t.isFeedback {
            env.line("AVISO: tono sostenido en la entrada de \(t.frequencyHz.fixed(1)) Hz a \(t.peakDBFS.fixed(1)) dBFS de pico "
                     + "(\(t.prominenceDB.fixed(0)) dB sobre su entorno): el bucle del cable realimenta y oscila. Se quita antes de "
                     + "medir, pero la prueba solo es concluyente sin él: baja el volumen del rig (o de su salida) hasta que desaparezca.")
        }
        env.line("Muestras perdidas por el búfer: \(rig.session.droppedFrames)")
        if let h = hosted {
            env.line("Vacíos de StemFeed: \(h.feedUnderrunFrames) muestras")
            env.line("Render alojado: \(h.render.outputJumps) saltos de salida (mayor \(h.render.outputJumpMaxFrames) muestras), "
                     + "\(h.render.outputBackwardJumps) hacia atrás, \(h.render.catchUpFrames) muestras tiradas en \(h.render.catchUps) recuperaciones, "
                     + "\(h.render.failedPullFrames) muestras que el motor no dio a tiempo")
            env.line("Latencia del TimePitch en esta sesión: \(h.timePitchLatencyFrames.fixed(0)) muestras; total sumada al ancla: \(h.anchorLatencyFrames.fixed(2))")
        }
        if let d = io {
            env.line("HAL: \(d.callbacks) ciclos, \(d.overloads) sobrecargas, saltos de sampleTime: entrada \(d.inputJumps) (mayor \(d.inputJumpMaxFrames)), "
                     + "salida \(d.outputJumps) (mayor \(d.outputJumpMaxFrames))")
            if let lo = d.outMinusInMin, let hi = d.outMinusInMax {
                env.line("HAL: sampleTime salida − entrada entre \(lo) y \(hi) muestras\(lo == hi ? " (constante)" : " (CAMBIÓ durante la sesión)")")
            }
        }
        let clickSteps = clickErrorSteps(r)
        env.line("Escalones del error por clic: \(clickSteps.count)"
                 + (clickSteps.isEmpty ? "" : " (" + clickSteps.map { "\($0.0.fixed(2)) s: \(signed($0.1))" }.joined(separator: ", ") + ")"))
        if let h = timing {
            // Hora de host → tiempo del tema (≈, a un búfer): el tema iba por `songStart` al empezar a grabar.
            func song(_ host: Double) -> Double { take.songStart + host - recordHost }
            let halURL = env.dir.appendingPathComponent("verify-hal.csv")
            try halCSV(h, song: song).write(to: halURL, atomically: true, encoding: .utf8)
            env.line("Marcas de host por segundo: \(halURL.path) (\(h.cycles) ciclos)")
            env.line("Escalones en las marcas de host: \(h.steps.count)"
                     + (h.steps.isEmpty ? "" : " (" + h.steps.map { "\(song($0.hostSeconds).fixed(2)) s: \(signed($0.sizeSamples)) en \($0.series.rawValue)" }
                        .joined(separator: ", ") + ")"))
            if let a = h.seconds.first, let b = h.seconds.last {
                env.line("Host salida − entrada: \(a.hostOutMinusInSamples.fixed(2)) → \(b.hostOutMinusInSamples.fixed(2)) muestras; "
                         + "rateScalar entrada \(a.inputRateScalar.fixed(6)) → \(b.inputRateScalar.fixed(6)); "
                         + "latencias declaradas \(a.latencies.map { "\($0.total)" } ?? "?") → \(b.latencies.map { "\($0.total)" } ?? "?")")
            }
        }
        if r.isInconclusive {
            env.line("NO CONCLUYENTE: baja el volumen del rig (o de su salida) hasta que el tono desaparezca y repite.")
            return Exit.outOfTolerance
        }
        env.line(r.passes ? "PASA" : "NO PASA")
        return r.passes ? Exit.ok : Exit.outOfTolerance
    }

    /// Una fila por clic (punto decimal, para leerlo con código): instante del tema, error en muestras y ms, y
    /// pico sobre el fondo.
    static func clicksCSV(_ r: AlignmentReport, songStart: Double) -> String {
        var s = "clic,tiempo_tema_s,error_muestras,error_ms,pico_sobre_fondo_db\n"
        for (i, c) in r.clicks.enumerated() {
            s += String(format: "%d,%.3f,%.3f,%.4f,%.1f\n", i, c.songTime, c.errorSamples, c.errorSamples / r.sampleRate * 1000, c.peakToFloorDB)
        }
        return s
    }

    /// Cambios de nivel del error por clic (diferencia entre clics seguidos de `HostTimingAnalysis.stepThresholdSamples`
    /// o más): instante del tema del primer clic con el nivel nuevo y tamaño en muestras.
    static func clickErrorSteps(_ r: AlignmentReport) -> [(Double, Double)] {
        zip(r.clicks, r.clicks.dropFirst()).compactMap { a, b in
            let d = b.errorSamples - a.errorSamples
            return abs(d) >= HostTimingAnalysis.stepThresholdSamples ? (b.songTime, d) : nil
        }
    }

    static func signed(_ v: Double) -> String { (v >= 0 ? "+" : "") + v.fixed(2) }

    /// Una fila por segundo de marcas del HAL (punto decimal): tiempo del tema aproximado, diferencia de host
    /// salida − entrada en muestras, la de `sampleTime`, residuos host − sampleTime, rateScalar y latencias declaradas.
    static func halCSV(_ h: HostTimingReport, song: (Double) -> Double) -> String {
        var s = "t_s,tiempo_tema_s,host_salida_menos_entrada_muestras,sampletime_salida_menos_entrada,"
            + "residuo_host_entrada_muestras,residuo_host_salida_muestras,ratescalar_entrada,ratescalar_salida,"
            + "lat_entrada_disp,lat_entrada_seguridad,lat_entrada_stream,lat_salida_disp,lat_salida_seguridad,lat_salida_stream\n"
        let t0 = h.seconds.first?.hostSeconds ?? 0
        for x in h.seconds {
            let l = x.latencies
            s += String(format: "%.0f,%.3f,%.3f,%.1f,%.3f,%.3f,%.9f,%.9f,", x.hostSeconds - t0, song(x.hostSeconds), x.hostOutMinusInSamples,
                        x.sampleOutMinusIn, x.inputHostResidualSamples, x.outputHostResidualSamples, x.inputRateScalar,
                        x.outputRateScalar)
            s += l.map { "\($0.inputDevice),\($0.inputSafety),\($0.inputStream),\($0.outputDevice),\($0.outputSafety),\($0.outputStream)\n" }
                ?? ",,,,,\n"
        }
        return s
    }

    // MARK: record

    @MainActor
    static func record(_ o: Options, _ env: Env) async throws -> Int32 {
        let seconds = o.seconds ?? 0
        var rate = o.rate
        var songURL: URL?
        if let song = o.song {
            let url = URL(fileURLWithPath: song)
            guard FileManager.default.fileExists(atPath: url.path) else { throw CLIError("No existe el WAV «\(song)».") }
            songURL = url
            if rate == nil { rate = try? WavFile.sampleRate(of: url) }
        }
        var opts = o
        opts.rate = rate
        let rig = try await Rig(opts)
        env.line("Entrada: \(rig.inputName)")
        env.line("Salida: \(rig.outputName)")
        try rig.open()
        defer { rig.close() }
        _ = applySaved(to: rig, env: env)

        let fs = rig.fs
        let player = rig.makePlayer()
        if songURL == nil {
            // Sin tema, el reproductor toca silencio: así la toma tiene ancla y sale alineada como siempre.
            let silence = [Float](repeating: 0, count: Int((seconds + 2) * fs))
            let url = env.dir.appendingPathComponent("record-silence.wav")
            try WavFile.write([silence, silence], sampleRate: fs, to: url)
            songURL = url
        }
        try player.load(tracks: [Track(id: "backing", url: songURL!)])
        try player.attach(to: rig.session)
        env.line("Grabando \(seconds.fixed(1)) s…")
        player.seek(to: 0)
        try player.play()
        try await rig.settle()
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let url = env.dir.appendingPathComponent("take-\(stamp.string(from: Date())).wav")
        try FileManager.default.createDirectory(at: env.dir, withIntermediateDirectories: true)
        try rig.session.startRecording(to: url)
        try await rig.advance(seconds: seconds)
        let take: RecordedTake
        do { take = try rig.session.stopRecording() } catch {
            player.pause()
            throw CLIError(((error as? LocalizedError)?.errorDescription ?? "\(error)"))
        }
        player.pause()

        env.line("Toma: \(url.path)")
        env.line("Duración: \((Double(take.frameCount) / fs).fixed(2)) s, \(take.channelCount) canal(es), \(Int(fs)) Hz")
        env.line("Inicio en el tema: \(take.songStart.fixed(3)) s")
        env.line("Latencia usada: \(take.latencySamples.fixed(2)) muestras (\(ms(take.latencySamples, fs)) ms)")
        if let rd = take.rigDelaySamples {
            env.line("Retardo del rig: \(rd.fixed(2)) muestras (\(ms(rd, fs)) ms)")
            env.line("Retardo del rig fiable: \(take.rigDelayReliable == true ? "sí" : "no")")
        } else {
            env.line("Retardo del rig: no medido (sin canal de referencia)")
        }
        env.line("Calibrada: \(take.latencyCalibrated ? "sí" : "no (latencia declarada por el dispositivo; puede ir desfasada decenas de ms)")")
        env.line("Reloj: \(clockText(take.clock))")
        env.line("Muestras perdidas por el búfer: \(rig.session.droppedFrames)")
        return Exit.ok
    }
}
