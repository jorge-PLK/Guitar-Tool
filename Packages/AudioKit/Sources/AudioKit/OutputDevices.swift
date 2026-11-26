#if canImport(CoreAudio)
import CoreAudio
#endif
import Foundation

/// Dispositivo de audio del sistema, con sus entradas y salidas (mini-spec Fase 3, «Dispositivo y canales»).
/// Nada de la app mira el nombre: se identifica por `uid`.
public struct AudioDevice: Sendable, Equatable, Identifiable {
    public var id: UInt32
    public var uid: String
    public var name: String
    public var inputChannels: Int
    public var outputChannels: Int
    /// Frecuencias de muestreo que admite (vacío = desconocidas).
    public var sampleRates: [Double]
    /// Frecuencia ACTUAL del dispositivo (`nil` = desconocida). El aviso de frecuencia se basa en esta, no en
    /// `sampleRates`: hay aparatos que declaran varias pero solo la cambian desde su propio menú.
    public var nominalSampleRate: Double?
    /// Aparato físico al que pertenece (Windows: `PKEY_Device_ContainerId` del endpoint; paso 8, F2). nil en CoreAudio,
    /// donde un dispositivo ya es el aparato entero.
    public var containerID: String?

    public init(id: UInt32, uid: String, name: String, inputChannels: Int = 0, outputChannels: Int = 0,
                sampleRates: [Double] = [], nominalSampleRate: Double? = nil, containerID: String? = nil) {
        self.containerID = containerID
        self.id = id
        self.uid = uid
        self.name = name
        self.inputChannels = inputChannels
        self.outputChannels = outputChannels
        self.sampleRates = sampleRates
        self.nominalSampleRate = nominalSampleRate
    }

    public func supports(sampleRate: Double) -> Bool {
        sampleRates.isEmpty || sampleRates.contains { abs($0 - sampleRate) < 0.5 }
    }

    /// El dispositivo está ahora mismo a `sampleRate` (desconocida cuenta como no).
    public func isRunning(at sampleRate: Double) -> Bool {
        nominalSampleRate.map { abs($0 - sampleRate) < 0.5 } ?? false
    }
}

/// Dispositivos del sistema. `CoreAudioDeviceProvider` en la app; `SimulatedDeviceProvider` en tests.
public protocol AudioDeviceProviding: AnyObject, Sendable {
    /// Dispositivos con al menos una entrada.
    func inputDevices() -> [AudioDevice]
    /// Dispositivos con al menos una salida.
    func outputDevices() -> [AudioDevice]
    func defaultOutputDevice() -> AudioDevice?
    /// Se llama, en cualquier hilo, cuando cambia la lista o la salida por defecto.
    func setChangeHandler(_ handler: (@Sendable () -> Void)?)
    /// Pide al dispositivo `uid` que trabaje a `sampleRate` (mini-spec Fase 3, «Dispositivo y canales» ·
    /// Frecuencia). Devuelve si quedó a esa frecuencia (comprobado leyendo la actual, no por el código de
    /// retorno: hay aparatos que aceptan la orden y no cambian).
    func requestSampleRate(_ sampleRate: Double, deviceUID uid: String) -> Bool
}

public extension AudioDeviceProviding {
    /// Dispositivo con ese UID entre los de entrada y salida.
    func device(uid: String) -> AudioDevice? {
        inputDevices().first { $0.uid == uid } ?? outputDevices().first { $0.uid == uid }
    }
}

/// Salida elegida en el perfil de equipo: `EquipmentProfile.audio.outputDeviceUID` y `backingOut`
/// (canales numerados desde 1). La app hace de puente: Store no depende de AudioKit.
public struct OutputSelection: Sendable, Equatable {
    /// nil = salida por defecto del sistema.
    public var deviceUID: String?
    public var left: Int
    public var right: Int

    public init(deviceUID: String? = nil, left: Int = 1, right: Int = 2) {
        self.deviceUID = deviceUID
        self.left = left
        self.right = right
    }
}

/// Salida resuelta y mapa de canales del outputNode (uno por canal del dispositivo; −1 = mudo).
public struct OutputRoute: Sendable, Equatable {
    public var device: AudioDevice
    public var channelMap: [Int32]?
    /// true si es la salida por defecto del sistema porque no había nada elegido o no estaba conectado.
    public var isSystemDefault: Bool

    public init(device: AudioDevice, channelMap: [Int32]?, isSystemDefault: Bool = false) {
        self.device = device
        self.channelMap = channelMap
        self.isSystemDefault = isSystemDefault
    }
}

/// Regla de salida (mini-spec Fase 3, «Dispositivo y canales»): el backing sale por el dispositivo y el par
/// de canales elegidos; si no hay nada elegido, no está conectado o el par no cabe, por la salida por
/// defecto del sistema, canales 1 y 2. No mira nombres.
public enum AudioRouting {
    public static func route(selection: OutputSelection, devices: [AudioDevice], defaultDevice: AudioDevice?) -> OutputRoute? {
        if let uid = selection.deviceUID, !uid.isEmpty,
           let device = devices.first(where: { $0.uid == uid && $0.outputChannels > 0 }) {
            // Backing mono (M-3d, left == right) en una salida de un canal: sin mapa; CoreAudio mezcla en el reproductor
            // propio y la sesión alojada suma L+R×0,5 (`BackingMono`).
            if selection.left == selection.right, selection.left == 1, device.outputChannels == 1 {
                return OutputRoute(device: device, channelMap: nil)
            }
        }
        if let uid = selection.deviceUID, !uid.isEmpty,
           let device = devices.first(where: { $0.uid == uid && $0.outputChannels > 0 }),
           let map = channelMap(left: selection.left, right: selection.right, channels: device.outputChannels) {
            return OutputRoute(device: device, channelMap: map)
        }
        return defaultDevice.map { OutputRoute(device: $0, channelMap: nil, isSystemDefault: true) }
    }

    /// Mapa para un dispositivo de `channels` salidas, con `left`/`right` numerados desde 1.
    /// nil si el par no es válido (fuera de rango o el mismo canal).
    public static func channelMap(left: Int, right: Int, channels: Int) -> [Int32]? {
        guard left != right, (1...max(channels, 1)).contains(left), (1...max(channels, 1)).contains(right),
              channels >= 2 else { return nil }
        var map = [Int32](repeating: -1, count: channels)
        map[left - 1] = 0
        map[right - 1] = 1
        return map
    }
}

/// Lleva la ruta actual y avisa cuando cambia. Los avisos del proveedor llegan en otro hilo y se
/// pasan al actor principal.
@MainActor
final class OutputController {
    let provider: any AudioDeviceProviding
    private(set) var selection: OutputSelection
    private(set) var route: OutputRoute?
    var onRouteChange: ((OutputRoute?) -> Void)?

    init(provider: any AudioDeviceProviding, selection: OutputSelection = OutputSelection()) {
        self.provider = provider
        self.selection = selection
        route = Self.resolve(provider, selection)
        provider.setChangeHandler { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    private static func resolve(_ provider: any AudioDeviceProviding, _ selection: OutputSelection) -> OutputRoute? {
        AudioRouting.route(selection: selection, devices: provider.outputDevices(), defaultDevice: provider.defaultOutputDevice())
    }

    func select(_ selection: OutputSelection) {
        self.selection = selection
        refresh()
    }

    func refresh() {
        let r = Self.resolve(provider, selection)
        guard r != route else { return }
        route = r
        onRouteChange?(r)
    }
}

// MARK: - Simulado

/// Lista de dispositivos en memoria para tests; `plug`/`unplug` avisan como CoreAudio.
///
/// Frecuencia: la actual es la `nominalSampleRate` de cada dispositivo tal como se pasa. `requestSampleRate`
/// la cambia si está entre las admitidas y el UID no está en `fixedRateUIDs` (aparatos que solo la cambian
/// desde su propio menú).
public final class SimulatedDeviceProvider: AudioDeviceProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var devices: [AudioDevice]
    private var defaultID: UInt32?
    private var handler: (@Sendable () -> Void)?
    private let fixedRateUIDs: Set<String>

    public init(devices: [AudioDevice], defaultID: UInt32?, fixedRateUIDs: Set<String> = []) {
        self.devices = devices
        self.defaultID = defaultID
        self.fixedRateUIDs = fixedRateUIDs
    }

    public func requestSampleRate(_ sampleRate: Double, deviceUID uid: String) -> Bool {
        let (ok, h) = lock.withLock { () -> (Bool, (@Sendable () -> Void)?) in
            guard let i = devices.firstIndex(where: { $0.uid == uid }) else { return (false, nil) }
            if devices[i].isRunning(at: sampleRate) { return (true, nil) }
            guard !fixedRateUIDs.contains(uid), devices[i].supports(sampleRate: sampleRate) else { return (false, nil) }
            devices[i].nominalSampleRate = sampleRate
            return (true, handler)
        }
        h?()
        return ok
    }

    /// Cambia la frecuencia desde «el menú del aparato» (también en los de frecuencia fija).
    public func setNominalSampleRate(_ sampleRate: Double, deviceUID uid: String) {
        let h = lock.withLock { () -> (@Sendable () -> Void)? in
            guard let i = devices.firstIndex(where: { $0.uid == uid }) else { return nil }
            devices[i].nominalSampleRate = sampleRate
            return handler
        }
        h?()
    }

    public func inputDevices() -> [AudioDevice] { lock.withLock { devices.filter { $0.inputChannels > 0 } } }

    public func outputDevices() -> [AudioDevice] { lock.withLock { devices.filter { $0.outputChannels > 0 } } }

    public func defaultOutputDevice() -> AudioDevice? {
        lock.withLock { devices.first { $0.id == defaultID && $0.outputChannels > 0 } }
    }

    public func setChangeHandler(_ handler: (@Sendable () -> Void)?) { lock.withLock { self.handler = handler } }

    public func plug(_ device: AudioDevice) {
        let h = lock.withLock { () -> (@Sendable () -> Void)? in
            devices.append(device)
            return handler
        }
        h?()
    }

    public func unplug(id: UInt32) {
        let h = lock.withLock { () -> (@Sendable () -> Void)? in
            devices.removeAll { $0.id == id }
            return handler
        }
        h?()
    }
}

#if canImport(CoreAudio)
// MARK: - CoreAudio

/// Dispositivos reales del sistema, con avisos de CoreAudio al cambiar la lista, la salida por defecto o
/// la frecuencia actual de cualquier dispositivo. Los agregados privados de `CoreAudioIO` no se listan.
public final class CoreAudioDeviceProvider: AudioDeviceProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private var listener: AudioObjectPropertyListenerBlock?
    /// Dispositivos con escucha de frecuencia puesta.
    private var rateWatched: Set<AudioDeviceID> = []
    private let queue = DispatchQueue(label: "ToneForge.audio-devices")

    private static let watched: [AudioObjectPropertySelector] = [
        kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice
    ]

    public init() {}

    deinit {
        if let listener {
            for sel in Self.watched {
                var addr = Self.address(sel)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, queue, listener)
            }
            for id in rateWatched {
                var addr = Self.address(kAudioDevicePropertyNominalSampleRate)
                AudioObjectRemovePropertyListenerBlock(id, &addr, queue, listener)
            }
        }
    }

    public func inputDevices() -> [AudioDevice] { allDevices().filter { $0.inputChannels > 0 } }

    public func outputDevices() -> [AudioDevice] { allDevices().filter { $0.outputChannels > 0 } }

    private func allDevices() -> [AudioDevice] {
        Self.deviceIDs().compactMap(Self.device).filter { !$0.uid.hasPrefix(CoreAudioIO.aggregateUIDPrefix) }
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        HAL.array(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices, as: AudioDeviceID.self)
    }

    public func requestSampleRate(_ sampleRate: Double, deviceUID uid: String) -> Bool {
        guard let id = HAL.deviceID(uid: uid) else { return false }
        return HAL.setNominalSampleRate(id, sampleRate)
    }

    public func defaultOutputDevice() -> AudioDevice? {
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr,
              id != 0 else { return nil }
        return Self.device(id)
    }

    public func setChangeHandler(_ handler: (@Sendable () -> Void)?) {
        let install = lock.withLock { () -> Bool in
            self.handler = handler
            return listener == nil && handler != nil
        }
        guard install else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.notify() }
        lock.withLock { listener = block }
        for sel in Self.watched {
            var addr = Self.address(sel)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, queue, block)
        }
        watchRates()
    }

    private func notify() {
        watchRates()
        lock.withLock { handler }?()
    }

    /// Escucha la frecuencia de los dispositivos que aparecen (la de los que se van la quita CoreAudio).
    private func watchRates() {
        let ids = Set(Self.deviceIDs())
        let (block, added) = lock.withLock { () -> (AudioObjectPropertyListenerBlock?, Set<AudioDeviceID>) in
            let added = ids.subtracting(rateWatched)
            rateWatched = ids
            return (listener, added)
        }
        guard let block else { return }
        for id in added {
            var addr = Self.address(kAudioDevicePropertyNominalSampleRate)
            AudioObjectAddPropertyListenerBlock(id, &addr, queue, block)
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func device(_ id: AudioDeviceID) -> AudioDevice? {
        guard let name = string(id, kAudioObjectPropertyName) else { return nil }
        let uid = string(id, kAudioDevicePropertyDeviceUID) ?? ""
        return AudioDevice(id: id, uid: uid, name: name,
                           inputChannels: channels(id, scope: kAudioObjectPropertyScopeInput),
                           outputChannels: channels(id, scope: kAudioObjectPropertyScopeOutput),
                           sampleRates: sampleRates(id),
                           nominalSampleRate: HAL.get(id, kAudioDevicePropertyNominalSampleRate, as: Float64.self))
    }

    /// Frecuencias habituales dentro de lo que declara el dispositivo (discretas o en rango).
    private static let commonRates: [Double] = [44100, 48000, 88200, 96000, 176400, 192000]

    private static func sampleRates(_ id: AudioDeviceID) -> [Double] {
        var addr = address(kAudioDevicePropertyAvailableNominalSampleRates)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: Int(size) / MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &ranges) == noErr else { return [] }
        var out = Set<Double>()
        for r in ranges {
            if r.mMinimum == r.mMaximum { out.insert(r.mMinimum) }
            else { for c in commonRates where c >= r.mMinimum && c <= r.mMaximum { out.insert(c) } }
        }
        return out.sorted()
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let v = value else { return nil }
        return v.takeRetainedValue() as String
    }

    private static func channels(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

#endif // canImport(CoreAudio)
