import Foundation

/// `AudioDeviceProviding` sobre los endpoints de WASAPI (plan, «Fase 7c», paso 8, W2-C). El enumerador se inyecta: en Windows es
/// `WASAPIAudioIO.devices` (ver el `init()` de abajo) y en el Mac, tests con listas fijas (el mapeo es lógica pura).
///
/// Lo que WASAPI da y lo que no:
/// - `AudioDevice.uid` = id del endpoint (el mismo que `AudioSetup` y la clave de calibración); `id` = hash FNV-1a de 32 bits del
///   id (solo identifica en la lista; nadie lo usa como clave).
/// - Un endpoint es de un solo sentido: `inputChannels` (captura) o `outputChannels` (render) = canales del formato de mezcla.
/// - `AudioDevice.containerID` = `PKEY_Device_ContainerId` (F2): los endpoints del mismo aparato comparten contenedor.
/// - La frecuencia del formato de mezcla es la ÚNICA frecuencia (`sampleRates` y `nominalSampleRate`): en modo compartido el motor
///   de Windows manda y la app no puede cambiarla; `requestSampleRate` solo dice si ya está a esa frecuencia.
/// - WASAPI no avisa de cambios de la lista sin una sesión abierta: mientras haya `setChangeHandler`, se sondea cada
///   `pollInterval` (2 s) y se avisa si cambió la lista, la salida por defecto o alguna frecuencia.
public final class WASAPIDeviceProvider: AudioDeviceProviding, @unchecked Sendable {
    /// Cada cuánto se sondea la lista mientras haya quien escuche los cambios.
    public static let defaultPollInterval: TimeInterval = 2

    public typealias Enumerator = @Sendable () throws -> [WASAPIDeviceInfo]

    private let enumerate: Enumerator
    private let pollInterval: TimeInterval
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private var pollTask: Task<Void, Never>?
    private var lastSnapshot: [Signature]?

    public init(pollInterval: TimeInterval = WASAPIDeviceProvider.defaultPollInterval, enumerate: @escaping Enumerator) {
        self.enumerate = enumerate
        self.pollInterval = pollInterval
    }

    deinit { pollTask?.cancel() }

    // MARK: AudioDeviceProviding

    public func inputDevices() -> [AudioDevice] { snapshot().devices.filter { $0.inputChannels > 0 } }

    public func outputDevices() -> [AudioDevice] { snapshot().devices.filter { $0.outputChannels > 0 } }

    public func defaultOutputDevice() -> AudioDevice? { snapshot().defaultOutput }

    public func requestSampleRate(_ sampleRate: Double, deviceUID uid: String) -> Bool {
        snapshot().devices.first { $0.uid == uid }?.isRunning(at: sampleRate) ?? false
    }

    public func setChangeHandler(_ handler: (@Sendable () -> Void)?) {
        lock.lock()
        self.handler = handler
        pollTask?.cancel()
        pollTask = nil
        lastSnapshot = nil
        let interval = pollInterval
        lock.unlock()
        guard handler != nil else { return }
        // Estado de partida para no avisar en el primer sondeo.
        let start = snapshot()
        lock.lock()
        lastSnapshot = start.signature
        pollTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.poll()
            }
        }
        lock.unlock()
    }

    // MARK: Mapeo

    /// Endpoints activos como dispositivos de AudioKit (un endpoint, un dispositivo de un solo sentido).
    public static func devices(from infos: [WASAPIDeviceInfo]) -> [AudioDevice] {
        infos.map { info in
            let channels = max(info.mix.channels, 0)
            return AudioDevice(id: stableID(info.id), uid: info.id, name: info.name,
                               inputChannels: info.flow == .capture ? channels : 0,
                               outputChannels: info.flow == .render ? channels : 0,
                               sampleRates: info.mix.sampleRate > 0 ? [info.mix.sampleRate] : [],
                               nominalSampleRate: info.mix.sampleRate > 0 ? info.mix.sampleRate : nil,
                               containerID: info.containerID)
        }
    }

    /// FNV-1a de 32 bits del id del endpoint.
    static func stableID(_ s: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for b in s.utf8 { h = (h ^ UInt32(b)) &* 16_777_619 }
        return h
    }

    private struct Signature: Equatable {
        var uid: String
        var name: String
        var inputChannels: Int
        var outputChannels: Int
        var rate: Double?
        var isDefault: Bool
    }

    private struct Snapshot {
        var devices: [AudioDevice]
        var defaultOutput: AudioDevice?
        var signature: [Signature]
    }

    /// Lectura nueva; si WASAPI falla, lista vacía (como un dispositivo que no está).
    private func snapshot() -> Snapshot {
        let infos = (try? enumerate()) ?? []
        let devices = Self.devices(from: infos)
        let defaultUID = infos.first { $0.flow == .render && $0.isDefault }?.id
        let signature = devices.map { d in
            Signature(uid: d.uid, name: d.name, inputChannels: d.inputChannels, outputChannels: d.outputChannels,
                      rate: d.nominalSampleRate, isDefault: d.uid == defaultUID)
        }
        return Snapshot(devices: devices, defaultOutput: devices.first { $0.uid == defaultUID }, signature: signature)
    }

    /// Un sondeo: avisa si algo cambió desde el anterior.
    func poll() {
        let current = snapshot().signature
        let fire: (@Sendable () -> Void)? = {
            lock.lock(); defer { lock.unlock() }
            guard let h = handler, let last = lastSnapshot, last != current else { return nil }
            lastSnapshot = current
            return h
        }()
        fire?()
    }
}

#if os(Windows)
public extension WASAPIDeviceProvider {
    /// Proveedor del sistema: endpoints activos de WASAPI.
    convenience init() { self.init(enumerate: { try WASAPIAudioIO.devices() }) }
}
#endif
