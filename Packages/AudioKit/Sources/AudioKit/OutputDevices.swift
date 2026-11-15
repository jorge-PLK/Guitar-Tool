import CoreAudio
import Foundation

/// Dispositivo de salida de audio.
public struct AudioOutputDevice: Sendable, Equatable, Identifiable {
    public var id: UInt32
    public var uid: String
    public var name: String
    public var outputChannels: Int

    public init(id: UInt32, uid: String, name: String, outputChannels: Int) {
        self.id = id
        self.uid = uid
        self.name = name
        self.outputChannels = outputChannels
    }
}

/// Lista de salidas del sistema. `CoreAudioDeviceProvider` en la app; `SimulatedDeviceProvider` en tests.
public protocol AudioDeviceProviding: AnyObject, Sendable {
    func outputDevices() -> [AudioOutputDevice]
    func defaultOutputDevice() -> AudioOutputDevice?
    /// Se llama, en cualquier hilo, cuando cambia la lista o la salida por defecto.
    func setChangeHandler(_ handler: (@Sendable () -> Void)?)
}

/// Salida elegida y mapa de canales del outputNode (uno por canal del dispositivo; −1 = mudo).
public struct OutputRoute: Sendable, Equatable {
    public var device: AudioOutputDevice
    public var channelMap: [Int32]?

    public init(device: AudioOutputDevice, channelMap: [Int32]?) {
        self.device = device
        self.channelMap = channelMap
    }
}

/// Regla de salida (mini-spec Fase 2 §1 AudioKit): la Flex Prime si está, por sus salidas USB 1/2;
/// si no, la salida por defecto.
public enum OutputRouting {
    /// Nombre del dispositivo (docs/probes/P2-audio-usb.md).
    public static let flexPrimeName = "HeadRush Flex Prime"
    /// Salidas USB 1/2 de las 4 (P2: backing por USB 1/2 a los auriculares).
    public static let flexPrimeOutputs: [Int32] = [0, 1]

    public static func isFlexPrime(_ device: AudioOutputDevice) -> Bool {
        device.name.localizedCaseInsensitiveContains("Flex Prime")
    }

    public static func route(devices: [AudioOutputDevice], defaultDevice: AudioOutputDevice?) -> OutputRoute? {
        if let flex = devices.first(where: isFlexPrime) {
            let map = (0..<max(flex.outputChannels, 2)).map { $0 < flexPrimeOutputs.count ? flexPrimeOutputs[$0] : -1 }
            return OutputRoute(device: flex, channelMap: map)
        }
        return defaultDevice.map { OutputRoute(device: $0, channelMap: nil) }
    }
}

/// Lleva la ruta actual y avisa cuando cambia. Los avisos del proveedor llegan en otro hilo y se
/// pasan al actor principal.
@MainActor
final class OutputController {
    let provider: any AudioDeviceProviding
    private(set) var route: OutputRoute?
    var onRouteChange: ((OutputRoute?) -> Void)?

    init(provider: any AudioDeviceProviding) {
        self.provider = provider
        route = OutputRouting.route(devices: provider.outputDevices(), defaultDevice: provider.defaultOutputDevice())
        provider.setChangeHandler { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let r = OutputRouting.route(devices: provider.outputDevices(), defaultDevice: provider.defaultOutputDevice())
        guard r != route else { return }
        route = r
        onRouteChange?(r)
    }
}

// MARK: - Simulado

/// Lista de dispositivos en memoria para tests; `plug`/`unplug` avisan como CoreAudio.
public final class SimulatedDeviceProvider: AudioDeviceProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var devices: [AudioOutputDevice]
    private var defaultID: UInt32?
    private var handler: (@Sendable () -> Void)?

    public init(devices: [AudioOutputDevice], defaultID: UInt32?) {
        self.devices = devices
        self.defaultID = defaultID
    }

    public func outputDevices() -> [AudioOutputDevice] { lock.withLock { devices } }

    public func defaultOutputDevice() -> AudioOutputDevice? {
        lock.withLock { devices.first { $0.id == defaultID } }
    }

    public func setChangeHandler(_ handler: (@Sendable () -> Void)?) { lock.withLock { self.handler = handler } }

    public func plug(_ device: AudioOutputDevice) {
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

// MARK: - CoreAudio

/// Salidas reales del sistema, con avisos de CoreAudio al cambiar la lista o la salida por defecto.
public final class CoreAudioDeviceProvider: AudioDeviceProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private var listener: AudioObjectPropertyListenerBlock?
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
        }
    }

    public func outputDevices() -> [AudioOutputDevice] {
        var addr = Self.address(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap(Self.device).filter { $0.outputChannels > 0 }
    }

    public func defaultOutputDevice() -> AudioOutputDevice? {
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
    }

    private func notify() {
        lock.withLock { handler }?()
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func device(_ id: AudioDeviceID) -> AudioOutputDevice? {
        guard let name = string(id, kAudioObjectPropertyName) else { return nil }
        let uid = string(id, kAudioDevicePropertyDeviceUID) ?? ""
        return AudioOutputDevice(id: id, uid: uid, name: name, outputChannels: outputChannels(id))
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let v = value else { return nil }
        return v.takeRetainedValue() as String
    }

    private static func outputChannels(_ id: AudioDeviceID) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
