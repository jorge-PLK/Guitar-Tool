// HAL de Core Audio: solo macOS.
#if canImport(CoreAudio)
import CoreAudio
import Foundation

/// Acceso mínimo a propiedades del HAL (copiado y recortado de `Probes/P2-audio-usb/Sources/p2/HAL.swift`,
/// probado con la pedalera). Fuera del hilo de E/S.
enum HAL {
    static func addr(_ sel: AudioObjectPropertySelector,
                     _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                     _ el: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: el)
    }

    static func get<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
                       _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, as: T.Type) -> T? {
        var a = addr(sel, scope)
        var size = UInt32(MemoryLayout<T>.size)
        let p = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { p.deallocate() }
        guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, p) == noErr else { return nil }
        return p.pointee
    }

    @discardableResult
    static func set<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ value: T,
                       _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> OSStatus {
        var a = addr(sel, scope)
        var v = value
        return AudioObjectSetPropertyData(obj, &a, 0, nil, UInt32(MemoryLayout<T>.size), &v)
    }

    static func array<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
                         _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, as: T.Type) -> [T] {
        var a = addr(sel, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(obj, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<T>.stride
        return [T](unsafeUninitializedCapacity: count) { buf, n in
            var sz = size
            if AudioObjectGetPropertyData(obj, &a, 0, nil, &sz, buf.baseAddress!) == noErr {
                n = Int(sz) / MemoryLayout<T>.stride
            } else { n = 0 }
        }
    }

    static func string(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
        var a = addr(sel)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &value) == noErr, let v = value else { return nil }
        return v.takeRetainedValue() as String
    }

    static func allDevices() -> [AudioDeviceID] {
        array(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices, as: AudioDeviceID.self)
    }

    static func deviceID(uid: String) -> AudioDeviceID? {
        allDevices().first { string($0, kAudioDevicePropertyDeviceUID) == uid }
    }

    static func isAlive(_ id: AudioDeviceID) -> Bool {
        (get(id, kAudioDevicePropertyDeviceIsAlive, as: UInt32.self) ?? 0) != 0
    }

    static func nominalSampleRate(_ id: AudioDeviceID) -> Double? {
        get(id, kAudioDevicePropertyNominalSampleRate, as: Float64.self)
    }

    /// Pide la frecuencia y espera (hasta `timeout` s) a que el dispositivo la anuncie: el cambio es asíncrono.
    static func setNominalSampleRate(_ id: AudioDeviceID, _ rate: Double, timeout: Double = 1.5) -> Bool {
        func done() -> Bool { nominalSampleRate(id).map { abs($0 - rate) < 0.5 } ?? false }
        if done() { return true }
        guard set(id, kAudioDevicePropertyNominalSampleRate, Float64(rate)) == noErr else { return false }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if done() { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return done()
    }

    /// Canales de cada búfer (stream) del dispositivo en ese ámbito, en orden.
    static func bufferLayout(_ dev: AudioObjectID, _ scope: AudioObjectPropertyScope) -> [Int] {
        var a = addr(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(dev, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(dev, &a, 0, nil, &size, raw) == noErr else { return [] }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.map { Int($0.mNumberChannels) }
    }

    static func channelCount(_ dev: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Int {
        bufferLayout(dev, scope).reduce(0, +)
    }

    /// Latencia de un sentido que declara el dispositivo: la suya + margen de seguridad + la del stream.
    /// Con las marcas de tiempo del HAL los búferes ya están descontados (ver `CoreAudioIO`).
    static func declaredLatency(_ dev: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Int {
        let p = latencyParts(dev, scope)
        return p.device + p.safety + p.stream
    }

    /// Las tres partes de `declaredLatency` por separado (el diagnóstico las vigila durante la sesión).
    static func latencyParts(_ dev: AudioObjectID, _ scope: AudioObjectPropertyScope) -> (device: Int, safety: Int, stream: Int) {
        let device = get(dev, kAudioDevicePropertyLatency, scope, as: UInt32.self) ?? 0
        let safety = get(dev, kAudioDevicePropertySafetyOffset, scope, as: UInt32.self) ?? 0
        let streams = array(dev, kAudioDevicePropertyStreams, scope, as: AudioStreamID.self)
        let stream = streams.compactMap { get($0, kAudioStreamPropertyLatency, as: UInt32.self) }.max() ?? 0
        return (Int(device), Int(safety), Int(stream))
    }
}

#endif // canImport(CoreAudio)
