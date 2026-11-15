import Foundation

/// FFT radix-2 en Double (sin dependencias) y correlación cruzada por FFT.
public enum FFT {
    public static func nextPow2(_ n: Int) -> Int {
        var p = 1
        while p < n { p <<= 1 }
        return p
    }

    /// In-place. La directa no se normaliza; la inversa divide por n. `re.count` debe ser potencia de 2.
    public static func transform(_ re: inout [Double], _ im: inout [Double], inverse: Bool = false) {
        let n = re.count
        precondition(n == im.count && n & (n - 1) == 0, "tamaño no potencia de 2")
        if n < 2 { return }
        let half = n / 2
        var cosT = [Double](repeating: 0, count: half)
        var sinT = [Double](repeating: 0, count: half)
        for k in 0..<half {
            let a = -2.0 * Double.pi * Double(k) / Double(n)
            cosT[k] = cos(a)
            sinT[k] = inverse ? -sin(a) : sin(a)
        }
        re.withUnsafeMutableBufferPointer { r in
            im.withUnsafeMutableBufferPointer { m in
                cosT.withUnsafeBufferPointer { ct in
                    sinT.withUnsafeBufferPointer { st in
                        var j = 0
                        for i in 1..<n {
                            var bit = n >> 1
                            while j & bit != 0 { j ^= bit; bit >>= 1 }
                            j ^= bit
                            if i < j { r.swapAt(i, j); m.swapAt(i, j) }
                        }
                        var len = 2
                        while len <= n {
                            let step = n / len
                            let h = len / 2
                            var i = 0
                            while i < n {
                                for k in 0..<h {
                                    let wr = ct[k * step], wi = st[k * step]
                                    let a = i + k, b = a + h
                                    let tr = r[b] * wr - m[b] * wi
                                    let ti = r[b] * wi + m[b] * wr
                                    r[b] = r[a] - tr; m[b] = m[a] - ti
                                    r[a] += tr; m[a] += ti
                                }
                                i += len
                            }
                            len <<= 1
                        }
                        if inverse {
                            let s = 1.0 / Double(n)
                            for i in 0..<n { r[i] *= s; m[i] *= s }
                        }
                    }
                }
            }
        }
    }
}

/// Espectro de una señal real, rellenada con ceros a `size`.
public struct Spectrum {
    public let size: Int
    public var re: [Double]
    public var im: [Double]

    public init(_ x: [Float], size: Int) {
        self.size = size
        re = [Double](repeating: 0, count: size)
        im = [Double](repeating: 0, count: size)
        for i in 0..<min(x.count, size) { re[i] = Double(x[i]) }
        FFT.transform(&re, &im)
    }
}

/// c[k] = sum_n signal[n + k] * reference[n] (k puede ser negativo; circular en `size`).
public struct XCorr {
    public let size: Int
    let data: [Double]

    public init(reference: Spectrum, signal: Spectrum) {
        precondition(reference.size == signal.size)
        size = reference.size
        var re = [Double](repeating: 0, count: size)
        var im = [Double](repeating: 0, count: size)
        for k in 0..<size {
            // Y * conj(X)
            re[k] = signal.re[k] * reference.re[k] + signal.im[k] * reference.im[k]
            im[k] = signal.im[k] * reference.re[k] - signal.re[k] * reference.im[k]
        }
        FFT.transform(&re, &im, inverse: true)
        data = re
    }

    /// `size` debe cubrir reference.count + signal.count para que no haya aliasing.
    public init(reference x: [Float], signal y: [Float]) {
        let n = FFT.nextPow2(x.count + y.count)
        self.init(reference: Spectrum(x, size: n), signal: Spectrum(y, size: n))
    }

    public func at(_ lag: Int) -> Double {
        data[((lag % size) + size) % size]
    }
}
