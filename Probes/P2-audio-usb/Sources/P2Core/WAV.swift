import Foundation

public struct WavFile {
    public var sampleRate: Double
    public var channels: [[Float]]
}

public enum WAV {
    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    /// Lee PCM 8/16/24/32 entero o float32/64, cualquier número de canales.
    public static func read(_ url: URL) throws -> WavFile {
        let d = try Data(contentsOf: url)
        func fail(_ s: String) -> Failure { Failure(description: "\(url.lastPathComponent): \(s)") }
        func u16(_ o: Int) -> Int { Int(d[o]) | Int(d[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        func tag(_ o: Int) -> String { String(decoding: d[o..<o + 4], as: UTF8.self) }
        guard d.count >= 12, tag(0) == "RIFF", tag(8) == "WAVE" else { throw fail("no es un WAV") }

        var fmt = 0, nch = 0, rate = 0, bits = 0
        var dataOff = -1, dataLen = 0
        var o = 12
        while o + 8 <= d.count {
            let id = tag(o), size = u32(o + 4), body = o + 8
            if id == "fmt " {
                fmt = u16(body); nch = u16(body + 2); rate = u32(body + 4); bits = u16(body + 14)
                if fmt == 0xFFFE, size >= 26 { fmt = u16(body + 24) }
            } else if id == "data" {
                dataOff = body
                dataLen = min(size, d.count - body)
                break
            }
            o = body + size + (size & 1)
        }
        guard dataOff >= 0, nch > 0, bits > 0 else { throw fail("cabecera incompleta") }
        let bps = bits / 8
        let frames = dataLen / (bps * nch)
        var out = [[Float]](repeating: [Float](repeating: 0, count: frames), count: nch)
        try d.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for c in 0..<nch {
                for i in 0..<frames {
                    let p = dataOff + (i * nch + c) * bps
                    switch (fmt, bits) {
                    case (3, 32): out[c][i] = Float(bitPattern: raw.loadUnaligned(fromByteOffset: p, as: UInt32.self))
                    case (3, 64): out[c][i] = Float(Double(bitPattern: raw.loadUnaligned(fromByteOffset: p, as: UInt64.self)))
                    case (1, 8): out[c][i] = (Float(raw[p]) - 128) / 128
                    case (1, 16): out[c][i] = Float(Int16(bitPattern: raw.loadUnaligned(fromByteOffset: p, as: UInt16.self))) / 32768
                    case (1, 24):
                        let v = UInt32(raw[p]) | UInt32(raw[p + 1]) << 8 | UInt32(raw[p + 2]) << 16
                        out[c][i] = Float(Int32(bitPattern: v << 8) >> 8) / 8388608
                    case (1, 32): out[c][i] = Float(Int32(bitPattern: raw.loadUnaligned(fromByteOffset: p, as: UInt32.self))) / 2147483648
                    default: throw fail("formato no soportado (tag \(fmt), \(bits) bits)")
                    }
                }
            }
        }
        return WavFile(sampleRate: Double(rate), channels: out)
    }

    /// Escribe un WAV mono float32.
    public static func write(_ samples: [Float], sampleRate: Double, to url: URL) throws {
        var d = Data(capacity: 44 + samples.count * 4)
        func a32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func a16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let dataBytes = UInt32(samples.count * 4)
        d.append(contentsOf: Array("RIFF".utf8)); a32(36 + dataBytes)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); a32(16)
        a16(3); a16(1); a32(UInt32(sampleRate.rounded())); a32(UInt32(sampleRate.rounded()) * 4); a16(4); a16(32)
        d.append(contentsOf: Array("data".utf8)); a32(dataBytes)
        samples.withUnsafeBytes { d.append(contentsOf: $0) }
        try d.write(to: url)
    }
}
