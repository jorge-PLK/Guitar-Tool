import AudioToolbox
import CoreAudio
import Foundation

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ s: String) { description = s }
}

/// Acceso mínimo a propiedades de CoreAudio.
enum HAL {
    static func addr(_ sel: AudioObjectPropertySelector,
                     _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                     _ el: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: el)
    }

    static func get<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
                       _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                       _ el: AudioObjectPropertyElement = kAudioObjectPropertyElementMain, as: T.Type) -> T? {
        var a = addr(sel, scope, el)
        var size = UInt32(MemoryLayout<T>.size)
        let p = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { p.deallocate() }
        guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, p) == noErr else { return nil }
        return p.pointee
    }

    static func array<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
                         _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                         _ el: AudioObjectPropertyElement = kAudioObjectPropertyElementMain, as: T.Type) -> [T] {
        var a = addr(sel, scope, el)
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

    static func string(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
                       _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                       _ el: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> String? {
        guard let o = get(obj, sel, scope, el, as: Unmanaged<CFString>?.self), let u = o else { return nil }
        return u.takeRetainedValue() as String
    }

    /// (primer canal 0-based, nº de canales) de cada buffer/stream del dispositivo en ese ámbito.
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

    static func fourCC(_ v: UInt32) -> String {
        let b = [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
        return String(decoding: b, as: UTF8.self)
    }
}

struct StreamInfo {
    let latency: UInt32
    let format: AudioStreamBasicDescription?
    var isFloat32: Bool {
        guard let f = format else { return true } // sin dato: se asume el formato estándar del HAL
        return f.mFormatID == kAudioFormatLinearPCM && f.mFormatFlags & kAudioFormatFlagIsFloat != 0 && f.mBitsPerChannel == 32
    }
}

struct DirectionInfo {
    let channels: Int
    let names: [String?]
    /// Por canal de dispositivo: (índice de buffer, posición dentro del buffer, canales del buffer).
    let map: [(buf: Int, off: Int, n: Int)]
    let deviceLatency: UInt32
    let safetyOffset: UInt32
    let streams: [StreamInfo]
    var streamLatency: UInt32 { streams.map { $0.latency }.max() ?? 0 }
    var totalLatency: UInt32 { deviceLatency + safetyOffset + streamLatency }
}

struct DeviceInfo {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let manufacturer: String
    let transport: String
    let input: DirectionInfo
    let output: DirectionInfo
    let nominalRate: Double
    let rates: [AudioValueRange]
    let bufferFrames: UInt32
    let bufferRange: AudioValueRange?

    var inputChannels: Int { input.channels }
    var outputChannels: Int { output.channels }

    static func all() -> [DeviceInfo] {
        HAL.array(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices, as: AudioDeviceID.self).map(DeviceInfo.init(id:))
    }

    /// Por UID exacto o por nombre (sin distinguir mayúsculas; subcadena). Falla si es ambiguo.
    static func find(_ spec: String) throws -> DeviceInfo {
        let devs = all()
        if let d = devs.first(where: { $0.uid == spec }) { return d }
        let s = spec.lowercased()
        let exact = devs.filter { $0.name.lowercased() == s }
        if exact.count == 1 { return exact[0] }
        let part = devs.filter { $0.name.lowercased().contains(s) }
        if part.count == 1 { return part[0] }
        if part.isEmpty { throw Failure("Ningún dispositivo coincide con \"\(spec)\". Usa `p2 list`.") }
        throw Failure("\"\(spec)\" es ambiguo: " + part.map { "\($0.name) [\($0.uid)]" }.joined(separator: "; ") + ". Usa el UID.")
    }

    init(id: AudioDeviceID) {
        self.id = id
        uid = HAL.string(id, kAudioDevicePropertyDeviceUID) ?? "?"
        name = HAL.string(id, kAudioObjectPropertyName) ?? "?"
        manufacturer = HAL.string(id, kAudioObjectPropertyManufacturer) ?? ""
        transport = HAL.get(id, kAudioDevicePropertyTransportType, as: UInt32.self).map(HAL.fourCC) ?? "?"
        nominalRate = HAL.get(id, kAudioDevicePropertyNominalSampleRate, as: Float64.self) ?? 0
        rates = HAL.array(id, kAudioDevicePropertyAvailableNominalSampleRates, as: AudioValueRange.self)
        bufferFrames = HAL.get(id, kAudioDevicePropertyBufferFrameSize, as: UInt32.self) ?? 0
        bufferRange = HAL.get(id, kAudioDevicePropertyBufferFrameSizeRange, as: AudioValueRange.self)
        input = DeviceInfo.direction(id, kAudioObjectPropertyScopeInput)
        output = DeviceInfo.direction(id, kAudioObjectPropertyScopeOutput)
    }

    static func direction(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> DirectionInfo {
        let bufs = HAL.bufferLayout(id, scope)
        var map: [(buf: Int, off: Int, n: Int)] = []
        for (b, n) in bufs.enumerated() { for c in 0..<n { map.append((b, c, n)) } }
        let names: [String?] = (0..<map.count).map { HAL.string(id, kAudioObjectPropertyElementName, scope, AudioObjectPropertyElement($0 + 1)) }
        let streams = HAL.array(id, kAudioDevicePropertyStreams, scope, as: AudioStreamID.self).map { s in
            StreamInfo(latency: HAL.get(s, kAudioStreamPropertyLatency, as: UInt32.self) ?? 0,
                       format: HAL.get(s, kAudioStreamPropertyVirtualFormat, as: AudioStreamBasicDescription.self))
        }
        return DirectionInfo(channels: map.count, names: names, map: map,
                             deviceLatency: HAL.get(id, kAudioDevicePropertyLatency, scope, as: UInt32.self) ?? 0,
                             safetyOffset: HAL.get(id, kAudioDevicePropertySafetyOffset, scope, as: UInt32.self) ?? 0,
                             streams: streams)
    }

    func setBufferFrames(_ n: UInt32) throws {
        var a = HAL.addr(kAudioDevicePropertyBufferFrameSize)
        var v = n
        let st = AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
        guard st == noErr else { throw Failure("No se pudo fijar el búfer a \(n) (OSStatus \(st)).") }
    }

    /// Latencia de ida y vuelta que declara el dispositivo: entrada + salida (dispositivo + safety + stream) + 2 búferes.
    var declaredRoundTripFrames: UInt32 { input.totalLatency + output.totalLatency + 2 * bufferFrames }
}
