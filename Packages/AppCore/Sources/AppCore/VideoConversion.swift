import Foundation
import SourceKit
import Store
import VideoKit

// Conversión HEVC → H.264 de las tomas en Windows (plan, «Fase 7c», mini-spec «Tomas HEVC en Windows», aprobada por
// Jorge). El Mac graba HEVC; Windows sin «Extensiones de vídeo HEVC» no lo lee ni en Media Foundation (montaje, encuadre,
// análisis) ni en WebView2 (visor). Bajo demanda (decisión de Jorge): quien va a leer el vídeo de una toma pregunta aquí
// (`state`); si hay que convertir, el trabajo entra en una cola en serie, con el progreso en `jobs.progress` (clave
// `video-<takeId>`, nunca el UUID del tema: `JobEngine.overlay` lo pintaría como «Separando») y la toma queda en
// «convirtiendo» hasta que acaba. El códec se lee del fichero (`TakeVideoProbe`), no se guarda en `project.json`.
//
// Sustitución al terminar (decisión de Jorge, opción b', 22/11/2026): en cuanto la conversión acaba y pasa la
// verificación, el convertido sustituye al original YA, aunque el visor de tomas (o la hoja «Ajustar desfase») tenga esa
// toma abierta: el visor no abre nunca el HEVC (la página enseña un aviso en lugar del `<video>`), así que no hay nada
// que esperar. El observador avisa al visor (`takeview.video`) y la página carga solo el `<video>`, sin cerrar el visor
// ni tocar el audio. Respaldo: si NTFS no deja sustituir porque el original sigue abierto por otro motivo (`busy`), se
// reintenta (`releaseRetries` × `releaseRetryDelay`); agotados, el convertido se queda como `.converting-<nombre>`, la
// toma pasa a `awaitingRelease` y se vuelve a intentar al cerrar el visor (`TakeViewService.close` → `applyPendingSoon`)
// o en la siguiente petición del vídeo (`state`: montaje, encuadre, export o el visor). Si la app se cierra antes,
// `Library.removeOrphanTemporaries` borra el convertido al arrancar y la siguiente petición convierte de nuevo.
//
// Paridad: solo Windows (el Mac lee HEVC de serie). En el Mac la política por omisión no convierte nada.

enum VideoConversionConstants {
    /// Prefijo de la clave del trabajo en `jobs.progress` (`video-<takeId>`).
    static let keyPrefix = "video-"
    /// Etapa del trabajo (la página no la cuenta como importación ni como separación).
    static let stage = "video"
    static let runningText = "Convirtiendo vídeo a H.264"
    static let queuedText = "En cola: convertir vídeo a H.264"
    static let doneText = "Vídeo convertido a H.264"
    /// Respaldo `busy`: convertido y verificado, pero el original sigue abierto por otro programa y NTFS no deja sustituirlo.
    static let awaitingText = "Vídeo convertido: se aplicará cuando el fichero original deje de estar en uso"
    /// Sin una línea de progreso de ffmpeg en este tiempo, se da por colgado (s; decisión propia).
    static let idleTimeout: TimeInterval = 120
    /// Si la sustitución choca con el original aún abierto (`busy`), se reintenta estas veces con esta pausa (decisión
    /// propia), al terminar la conversión y al cerrar el visor. Agotados, queda para la siguiente petición del vídeo.
    static let releaseRetries = 4
    static let releaseRetryDelay: TimeInterval = 0.5
    /// Conversiones simultáneas por omisión (medido en el PC de pruebas; decisión propia, ver `Hooks.maxConcurrent`).
    static let maxConcurrent = 2
    /// Códigos para la página (montaje, encuadre y visor).
    static let convertingCode = "video-converting"
    static let failedCode = "video-failed"
}

/// Estado del vídeo de una toma para quien lo va a leer.
enum TakeVideoState: Equatable, Sendable {
    case ready
    /// En cola (`nil`) o convirtiéndose (fracción 0…1).
    case converting(Double?)
    /// Solo el respaldo `busy`: convertido y verificado, pero el original sigue abierto por otro programa y la sustitución
    /// no se pudo aplicar tras los reintentos (el original sigue en su sitio; se reintenta en la siguiente petición).
    case awaitingRelease
    case failed(String)

    var isReady: Bool { self == .ready }
}

/// Resultado de intentar aplicar una sustitución pendiente.
enum VideoSwapOutcome: Equatable, Sendable {
    /// No había nada pendiente (o ya se estaba aplicando).
    case nothing
    case applied
    /// El fichero sigue abierto por alguien (NTFS no deja sustituirlo): sigue pendiente.
    case busy
    /// La toma ya no existe (se borró mientras tanto): se descarta el convertido.
    case gone
}

/// Lo que ve la página de una toma que aún no se puede leer.
struct TakeVideoStatusInfo: Codable, Sendable, Equatable {
    /// `video-converting` o `video-failed`.
    var code: String
    var takeId: String
    /// Clave del trabajo en `jobs.progress`.
    var jobId: String
    var progress: Double?
    var message: String

    init?(takeId: UUID, state: TakeVideoState) {
        self.takeId = takeId.uuidString
        jobId = VideoConversionEngine.key(takeId)
        switch state {
        case .ready: return nil
        case .converting(let f):
            code = VideoConversionConstants.convertingCode
            progress = f
            message = VideoConversionEngine.convertingMessage(f)
        case .awaitingRelease:
            code = VideoConversionConstants.convertingCode
            progress = 1
            message = VideoConversionEngine.awaitingMessage
        case .failed(let m):
            code = VideoConversionConstants.failedCode
            progress = nil
            message = VideoConversionEngine.failedMessage(m)
        }
    }

    /// Error del puente con el mismo texto (`montage.framingFrame`).
    var rpcError: RPCError { RPCError(code: code, message: message) }
}

/// Fallo de una conversión (texto del trabajo fallido; el original HEVC se queda).
enum VideoConversionError: Error, Equatable, CustomStringConvertible {
    case unreadable(String)
    case ffmpeg(String)
    case verification(String)

    var description: String {
        switch self {
        case .unreadable(let s): "no se pudo leer el vídeo (\(s))"
        case .ffmpeg(let s): "ffmpeg no pudo convertirlo (\(s))"
        case .verification(let s): "la conversión no pasó la verificación: \(s); se conserva el original"
        }
    }
}

/// Límite de trabajos a la vez, por orden de llegada; esperar en la cola es cancelable.
actor ConversionGate {
    private let limit: Int
    private var active = 0
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    init(limit: Int) { self.limit = max(1, limit) }

    func acquire() async throws {
        try Task.checkCancellation()
        if active < limit { active += 1; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { c.resume(throwing: CancellationError()); return }
                waiters.append((id, c))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    /// Libera el sitio: pasa al siguiente que espera (conserva el contador) o lo devuelve.
    func release() {
        if waiters.isEmpty { active = max(0, active - 1) } else { waiters.removeFirst().continuation.resume() }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let i = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: i).continuation.resume(throwing: CancellationError())
    }
}

/// Cola de conversiones (como `LinkEngine`: cancelación por clave, `cancelAll` al cerrar; hasta `maxConcurrent` a la vez).
final class VideoConversionEngine: @unchecked Sendable {
    /// Lo que depende del sistema; los tests ponen un `ScriptedProcessRunner` y la política.
    struct Hooks: Sendable {
        var ffmpeg: @Sendable () async throws -> URL
        var runner: any ProcessRunning
        /// ¿Hay que convertir un vídeo así? Windows: si es HEVC. Mac: nunca (lee HEVC de serie).
        var needsConversion: @Sendable (TakeVideoProbe) -> Bool
        /// Sustituye el original por el convertido. NTFS falla si el original sigue abierto (respaldo `busy`); los tests lo
        /// simulan en cualquier sistema.
        var replace: @Sendable (_ original: URL, _ converted: URL) throws -> Void = { try FileOps.atomicReplace($0, with: $1) }

        /// ¿Y si el sondeo falla o no hay pista de vídeo? Windows: sí se intenta convertir (ffmpeg lee más que el parser de
        /// `moov`, y un fallo allí es visible); Mac: no (lee de serie, quien lo lea dará su error).
        var assumeNeedsWhenUnprobed: Bool = platformAssumeNeedsWhenUnprobed

        /// Conversiones a la vez (el resto espera en cola, por orden). Medido en una RTX 3060 con dos tomas de 7500
        /// fotogramas: dos a la vez 19,6 s frente a 21,6 s en serie (NVENC ya va al 80-95 % con una); en CPU sola no gana
        /// nada. Con 2 se solapan además el sondeo, el tramo vacío y la verificación de una con la codificación de otra.
        var maxConcurrent: Int = VideoConversionConstants.maxConcurrent

        /// Intentos por orden (codificador y decodificación en GPU); los tests los sustituyen.
        var attempts: [TakeVideoTranscode.Attempt] = TakeVideoTranscode.attempts

        static var platformAssumeNeedsWhenUnprobed: Bool {
            #if os(Windows)
            true
            #else
            false
            #endif
        }

        static var platformPolicy: @Sendable (TakeVideoProbe) -> Bool {
            #if os(Windows)
            { $0.codec != .h264 }
            #else
            { _ in false }
            #endif
        }

        static func production(sources: ExternalSources) -> Hooks {
            Hooks(ffmpeg: { try await sources.ffmpegURL() }, runner: SystemProcessRunner(), needsConversion: platformPolicy)
        }
    }

    /// Suelta los ficheros de la toma antes de sustituirlos (NTFS no reemplaza un fichero abierto).
    typealias Releaser = @Sendable (_ takeId: UUID, _ files: [URL]) async -> Void
    /// Fin de un trabajo: `ready` (sustitución aplicada), `failed` (también si se canceló o se borró la toma) o
    /// `awaitingRelease` (respaldo `busy`).
    typealias Observer = @Sendable (_ takeId: UUID, _ state: TakeVideoState) -> Void

    static func key(_ takeId: UUID) -> String { VideoConversionConstants.keyPrefix + takeId.uuidString }

    static func convertingMessage(_ f: Double?) -> String {
        "Esta toma se está convirtiendo a H.264…" + (f.map { " \(Int(($0 * 100).rounded())) %" } ?? "")
    }

    static let awaitingMessage = "El vídeo de esta toma ya está convertido a H.264, pero el fichero original sigue en uso por otro programa; se aplicará en cuanto se libere."

    static func failedMessage(_ m: String) -> String { "No se pudo convertir el vídeo de esta toma a H.264: \(m)." }

    let jobs: JobEngine
    private let hooks: Hooks
    private let lock = NSLock()
    private let gate: ConversionGate
    private struct Job { var task: Task<Void, Never>?; var fraction: Double? }
    /// Original y convertido verificado que espera a sustituirlo.
    struct Swap: Equatable, Sendable { var original: URL; var converted: URL }
    private var running: [UUID: Job] = [:]
    private var swaps: [UUID: (title: String, files: [Swap])] = [:]
    private var applying: Set<UUID> = []
    /// Trabajo que ya salió de `running` y aún aplica la sustitución (para que `wait` también lo espere).
    private var settling: [UUID: Task<Void, Never>] = [:]
    private var failures: [UUID: String] = [:]
    private var releasers: [Releaser] = []
    private var observers: [Observer] = []
    /// Reintentos del respaldo `busy` (tests: más cortos).
    var releaseRetries = VideoConversionConstants.releaseRetries
    var releaseRetryDelay = VideoConversionConstants.releaseRetryDelay
    /// ¿Hay que convertir? por ruta, tamaño y fecha (no relee `moov` en cada vista previa).
    private var verdicts: [String: (size: Int64, date: Double, needs: Bool)] = [:]

    init(jobs: JobEngine, hooks: Hooks) {
        self.jobs = jobs
        self.hooks = hooks
        gate = ConversionGate(limit: hooks.maxConcurrent)
    }

    func addReleaser(_ r: @escaping Releaser) { lock.withLock { releasers.append(r) } }
    func addObserver(_ o: @escaping Observer) { lock.withLock { observers.append(o) } }

    /// Estado sin poner nada en marcha (para refrescar el progreso de una instantánea).
    func currentState(takeId: UUID) -> TakeVideoState {
        lock.withLock {
            if let j = running[takeId] { return .converting(j.fraction) }
            if swaps[takeId] != nil { return .awaitingRelease }
            if let f = failures[takeId] { return .failed(f) }
            return .ready
        }
    }

    /// Sustitución pendiente de la toma (tests).
    func pendingSwaps(takeId: UUID) -> [Swap] { lock.withLock { swaps[takeId]?.files ?? [] } }

    /// Estado del vídeo de la toma (base y punches): `ready` si se puede leer ya; si hay que convertir y no está en marcha,
    /// encola el trabajo y da `converting`. Un fallo se recuerda (no se reintenta en cada vista previa) hasta `forget`.
    /// Con una sustitución pendiente (respaldo `busy`), intenta aplicarla en segundo plano (si el original ya se liberó,
    /// los observadores reciben `ready` al acabar).
    func state(takeId: UUID, files: [URL?], title: String) -> TakeVideoState {
        let now = currentState(takeId: takeId)
        if now == .awaitingRelease { Task { await self.applyPending(takeId: takeId) } }
        guard now == .ready else { return now }
        let pending = files.compactMap { $0 }.filter { needsConversion($0) }
        guard !pending.isEmpty else { return .ready }
        return enqueue(takeId: takeId, files: pending, title: title)
    }

    /// Olvida los fallos (al abrir de nuevo el montaje o el visor se reintenta).
    func forget(takeIds: [UUID]) { lock.withLock { for t in takeIds { failures[t] = nil } } }

    func needsConversion(_ url: URL) -> Bool {
        let a = try? FileManager.default.attributesOfItem(atPath: url.path)
        // Sin tamaño legible no se descarta el vídeo: se sondea igual (y sin caché).
        let size = (a?[.size] as? NSNumber)?.int64Value
        let date = (a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        if let size, let v = lock.withLock({ verdicts[url.path] }), v.size == size, v.date == date { return v.needs }
        let probe: TakeVideoProbe?
        do { probe = try TakeVideoProbe.read(url) } catch {
            // Sondeo fallido: no se da por bueno en silencio (en Windows, ffmpeg sí sabe leerlo; si tampoco, el trabajo
            // falla con un mensaje visible). Sin caché: se reintenta en la siguiente consulta.
            FileHandle.standardError.write(Data("VideoConversion: no se pudo sondear \(url.path): \(error)\n".utf8))
            return hooks.assumeNeedsWhenUnprobed
        }
        guard let probe else {
            FileHandle.standardError.write(Data("VideoConversion: \(url.path) sin pista de vídeo\n".utf8))
            return hooks.assumeNeedsWhenUnprobed
        }
        let needs = hooks.needsConversion(probe)
        if let size { lock.withLock { verdicts[url.path] = (size, date, needs) } }
        return needs
    }

    /// Cancela el trabajo de una toma (en cola o en marcha). `true` si existía.
    @discardableResult
    func cancel(takeId: UUID) -> Bool {
        guard let t = lock.withLock({ running[takeId]?.task }) else { return false }
        t.cancel()
        return true
    }

    /// Cierre de la app: cancela todo (los temporales y los convertidos pendientes los borra
    /// `Library.removeOrphanTemporaries` al arrancar).
    func cancelAll() async {
        let tasks = lock.withLock { running.values.compactMap(\.task) }
        for t in tasks { t.cancel() }
    }

    /// Antes de borrar una toma: cancela su conversión, espera a que pare y descarta lo convertido pendiente.
    func discard(takeId: UUID) async {
        let task = lock.withLock { running[takeId]?.task }
        task?.cancel()
        await task?.value
        let dropped = lock.withLock { () -> (title: String, files: [Swap])? in
            failures[takeId] = nil
            return swaps.removeValue(forKey: takeId)
        }
        guard let dropped else { return }
        for s in dropped.files { try? FileManager.default.removeItem(at: s.converted) }
        jobs.update(Self.key(takeId), title: dropped.title, stage: VideoConversionConstants.stage, state: "cancelled",
                    text: "Conversión descartada")
    }

    /// Aplica la sustitución pendiente de la toma (opción b' de Jorge: aunque el visor la tenga abierta, porque el visor
    /// no abre nunca el HEVC): suelta a los lectores y reemplaza cada original por su convertido. Si el fichero sigue
    /// abierto por otro motivo (`busy`), queda pendiente.
    @discardableResult
    func applyPending(takeId: UUID) async -> VideoSwapOutcome {
        guard let pending = lock.withLock({ () -> (title: String, files: [Swap])? in
            guard let p = swaps[takeId], !applying.contains(takeId) else { return nil }
            applying.insert(takeId)
            return p
        }) else { return .nothing }
        defer { lock.withLock { _ = applying.remove(takeId) } }
        let key = Self.key(takeId), stage = VideoConversionConstants.stage
        let fm = FileManager.default
        if pending.files.contains(where: { !fm.fileExists(atPath: $0.original.path) }) {
            lock.withLock { swaps[takeId] = nil }
            for s in pending.files { try? fm.removeItem(at: s.converted) }
            jobs.update(key, title: pending.title, stage: stage, state: "cancelled", text: "Conversión descartada: la toma ya no existe")
            notify(takeId, .failed("la toma ya no existe"))
            return .gone
        }
        for r in lock.withLock({ releasers }) { await r(takeId, pending.files.map(\.original)) }
        var left = pending.files
        while let s = left.first {
            do { try hooks.replace(s.original, s.converted) } catch {
                lock.withLock { swaps[takeId]?.files = left }
                jobs.update(key, title: pending.title, stage: stage, state: "running", fraction: 1, text: VideoConversionConstants.awaitingText, force: true)
                notify(takeId, .awaitingRelease)
                return .busy
            }
            left.removeFirst()
            lock.withLock { verdicts[s.original.path] = nil }
        }
        lock.withLock { swaps[takeId] = nil }
        jobs.update(key, title: pending.title, stage: stage, state: "done", fraction: 1, text: VideoConversionConstants.doneText)
        notify(takeId, .ready)
        return .applied
    }

    /// `applyPending` con reintentos mientras el original siga abierto (`busy`): al terminar la conversión y al cerrar el
    /// visor. Devuelve el último resultado.
    @discardableResult
    func applyPendingSoon(takeId: UUID) async -> VideoSwapOutcome {
        let retries = max(0, releaseRetries), delay = releaseRetryDelay
        var outcome = VideoSwapOutcome.nothing
        for attempt in 0...retries {
            if attempt > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1e9)) }
            outcome = await applyPending(takeId: takeId)
            guard outcome == .busy else { return outcome }
        }
        return outcome
    }

    /// Trabajos vivos (tests).
    var runningCount: Int { lock.withLock { running.count } }

    /// Espera a que acabe el trabajo de la toma, si hay (tests).
    /// Incluye la aplicación de la sustitución (si no, `wait` volvía en el hueco entre convertir y sustituir).
    func wait(takeId: UUID) async { await lock.withLock({ running[takeId]?.task ?? settling[takeId] })?.value }

    // MARK: Cola

    private func enqueue(takeId: UUID, files: [URL], title: String) -> TakeVideoState {
        let key = Self.key(takeId)
        let created: Bool = lock.withLock {
            if running[takeId] != nil { return false }
            running[takeId] = Job(task: nil, fraction: nil)
            return true
        }
        guard created else { return currentState(takeId: takeId) }
        jobs.update(key, title: title, stage: VideoConversionConstants.stage, state: "queued", text: VideoConversionConstants.queuedText)
        lock.withLock {
            let task = Task { [self] in await run(takeId: takeId, files: files, title: title) }
            running[takeId]?.task = task
        }
        return .converting(nil)
    }

    private func setFraction(_ takeId: UUID, _ f: Double, title: String) {
        let f = min(max(f, 0), 1)
        lock.withLock { running[takeId]?.fraction = f }
        jobs.update(Self.key(takeId), title: title, stage: VideoConversionConstants.stage, state: "running", fraction: f,
                    text: "\(VideoConversionConstants.runningText)… \(Int((f * 100).rounded())) %")
    }

    private func notify(_ takeId: UUID, _ state: TakeVideoState) {
        for o in lock.withLock({ observers }) { o(takeId, state) }
    }

    private func finish(_ takeId: UUID, _ state: TakeVideoState, remember: Bool) {
        lock.withLock {
            running[takeId] = nil
            if remember, case .failed(let m) = state { failures[takeId] = m }
        }
        notify(takeId, state)
    }

    private func run(takeId: UUID, files: [URL], title: String) async {
        let key = Self.key(takeId), stage = VideoConversionConstants.stage
        var made: [Swap] = []
        var holdsSlot = false
        do {
            try await gate.acquire()
            holdsSlot = true
            try Task.checkCancellation()
            setFraction(takeId, 0, title: title)
            let ffmpeg = try await hooks.ffmpeg()
            for (i, url) in files.enumerated() {
                let temp = try await convert(url, ffmpeg: ffmpeg, takeId: takeId, part: i, of: files.count, title: title)
                made.append(Swap(original: url, converted: temp))
            }
            await gate.release()
            holdsSlot = false
            try Task.checkCancellation()
            // De «convirtiendo» a «pendiente de sustituir» sin hueco en el que `state` encolaría otra vez; la sustitución se
            // aplica ya, con el visor abierto o no (opción b'), y solo se queda pendiente si el original sigue en uso.
            lock.withLock {
                settling[takeId] = running[takeId]?.task
                running[takeId] = nil
                swaps[takeId] = (title, made)
            }
            await applyPendingSoon(takeId: takeId)
            lock.withLock { settling[takeId] = nil }
        } catch let error where Self.isCancellation(error) {
            if holdsSlot { await gate.release() }
            for s in made { try? FileManager.default.removeItem(at: s.converted) }
            jobs.update(key, title: title, stage: stage, state: "cancelled", text: "Conversión cancelada")
            finish(takeId, .failed("conversión cancelada"), remember: false)
        } catch {
            if holdsSlot { await gate.release() }
            for s in made { try? FileManager.default.removeItem(at: s.converted) }
            let message = (error as? VideoConversionError)?.description ?? JobEngine.describe(error)
            jobs.update(key, title: title, stage: stage, state: "failed", error: message, text: "No se pudo convertir el vídeo")
            finish(takeId, .failed(message), remember: true)
        }
    }

    static func isCancellation(_ e: Error) -> Bool {
        if e is CancellationError { return true }
        if case SourceError.cancelled? = e as? SourceError { return true }
        return false
    }

    /// Un fichero: ffmpeg (NVENC y, si falla, Media Foundation) a un temporal junto al original, tramo vacío del original y
    /// verificación. Devuelve el convertido; la sustitución (el HEVC desaparece) la hace `applyPending`.
    private func convert(_ url: URL, ffmpeg: URL, takeId: UUID, part: Int, of count: Int, title: String) async throws -> URL {
        let fm = FileManager.default
        let original: TakeVideoProbe
        do {
            guard let p = try TakeVideoProbe.read(url) else { throw VideoConversionError.unreadable("\(url.lastPathComponent) sin pista de vídeo") }
            original = p
        } catch let e as VideoConversionError { throw e } catch { throw VideoConversionError.unreadable("\(url.lastPathComponent): \(error)") }
        let temp = url.deletingLastPathComponent().appendingPathComponent(Library.videoConversionPrefix + url.lastPathComponent)
        var keep = false
        defer { if !keep { try? fm.removeItem(at: temp) } }
        let bitrate = TakeVideoTranscode.bitrate(for: original), gop = TakeVideoTranscode.gop(for: original)
        let duration = max(original.duration, 1e-3)
        var problems: [String] = []
        var converted = false
        for attempt in hooks.attempts {
            try Task.checkCancellation()
            try? fm.removeItem(at: temp)
            let args = TakeVideoTranscode.ffmpegArguments(input: url, output: temp, encoder: attempt.encoder, bitrate: bitrate, gop: gop,
                                                          hwDecode: attempt.hwDecode)
            let onLine: @Sendable (String) -> Void = { [weak self] line in
                guard let us = TakeVideoTranscode.progressMicroseconds(line) else { return }
                let within = min(max(Double(us) / 1e6 / duration, 0), 1)
                self?.setFraction(takeId, (Double(part) + within) / Double(count), title: title)
            }
            let result: ProcessResult
            do {
                result = try await hooks.runner.run(ProcessRequest(executable: ffmpeg, arguments: args,
                                                                   timeout: .idle(VideoConversionConstants.idleTimeout)), onLine: onLine)
            } catch let error where Self.isCancellation(error) {
                throw CancellationError()
            } catch {
                problems.append("\(attempt.label): \(error)")
                continue
            }
            if result.status == 0, fm.fileExists(atPath: temp.path) {
                converted = true
                break
            }
            let last = result.stderr.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
            problems.append("\(attempt.label): \(last.isEmpty ? "código \(result.status)" : last)")
        }
        guard converted else { throw VideoConversionError.ffmpeg(problems.joined(separator: "; ")) }
        let after: TakeVideoProbe
        do {
            try TakeVideoTranscode.alignStart(temp, firstFrameTime: original.firstFrameTime)
            guard let p = try TakeVideoProbe.read(temp) else { throw VideoConversionError.verification("el fichero convertido no tiene vídeo") }
            after = p
        } catch let e as VideoConversionError { throw e } catch { throw VideoConversionError.verification("\(error)") }
        if let why = TakeVideoTranscode.verify(original: original, converted: after) { throw VideoConversionError.verification(why) }
        try Task.checkCancellation()
        keep = true
        return temp
    }
}

extension ExternalSources {
    /// `ffmpeg` embebido (o el de `TF_HELPERS`), el mismo que usa la importación por enlace.
    func ffmpegURL() async throws -> URL { try await locator().ffmpeg() }
}

// MARK: - Bridge

extension Bridge {
    /// Montaje (vista previa, encuadre y export) y visor preguntan al motor antes de leer el vídeo de una toma. El montaje
    /// no abre nunca un fichero que haya que convertir (la puerta lo para antes) y el visor tampoco (enseña un aviso en
    /// lugar del `<video>`), así que la sustitución no espera a nadie (opción b' de Jorge). Al acabar, el montaje reanaliza
    /// y el visor avisa a la página (`takeview.video`) para que cargue el `<video>`. Se llama después de
    /// `registerRecordMethods` (borrar una toma descarta antes su conversión).
    func registerVideoConversion() {
        let engine = videoConversion
        addShutdownHook { await engine.cancelAll() }
        let montage = montageService, takeView = takeViewService
        montage.videoConversion = engine
        takeView.videoConversion = engine
        engine.addObserver { takeId, state in
            Task { @MainActor in
                montage.videoConversionFinished(takeId: takeId, state: state)
                takeView.videoConversionFinished(takeId: takeId, state: state)
            }
        }
        if let record = recordService {
            let previous = record.willDeleteTake
            record.willDeleteTake = { takeId in
                await engine.discard(takeId: takeId)
                await previous?(takeId)
            }
        }
    }
}
