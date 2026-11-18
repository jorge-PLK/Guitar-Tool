// Genera en el Mac, con vDSP, los valores de referencia de la prueba b (Fase 7c paso 4).
// uso: swift fftref.swift <salida ref_data.c>
// 1) FFT real de 4096 (vDSP_DFT_zrop float, como LogMel/DrumSpectrogram/SemitoneSpectrogram/SpectralTransform).
// 2) SignalMath.analyticCorrelation (vDSP_DFT_zop double, n = 65536) sobre un ruido retrasado 12345 muestras:
//    es la correlación de la que sale la latencia (LatencyProbe/TakeAligner).
import Accelerate
import Foundation

struct LCG {
    var s: UInt32
    mutating func next() -> Float {
        s = s &* 1_664_525 &+ 1_013_904_223
        return Float(Int32(bitPattern: s)) / 2_147_483_648
    }
}

let out = CommandLine.arguments[1]
var c = "// Generado por fftref.swift en el Mac con vDSP (Fase 7c paso 4, prueba b). No editar.\n#include \"ref_data.h\"\n\n"

// 1) FFT real 4096, entrada: dos senos + ruido (valores guardados tal cual en float).
let n = 4096
var g = LCG(s: 1)
var x = [Float](repeating: 0, count: n)
for i in 0..<n {
    let t = Double(i) / 44_100
    x[i] = Float(0.7 * sin(2 * .pi * 440.5 * t) + 0.3 * sin(2 * .pi * 3000.25 * t + 0.3)) + 0.05 * g.next()
}
let setup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(n), .FORWARD)!
var er = [Float](repeating: 0, count: n / 2), ei = er, orr = er, oi = er
x.withUnsafeBufferPointer { xp in
    xp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { cp in
        er.withUnsafeMutableBufferPointer { r in
            ei.withUnsafeMutableBufferPointer { im in
                var z = DSPSplitComplex(realp: r.baseAddress!, imagp: im.baseAddress!)
                vDSP_ctoz(cp, 2, &z, 1, vDSP_Length(n / 2))
            }
        }
    }
}
vDSP_DFT_Execute(setup, er, ei, &orr, &oi)
vDSP_DFT_DestroySetup(setup)

func arr(_ name: String, _ type: String, _ v: [String]) -> String {
    var s = "const \(type) \(name)[\(v.count)] = {\n"
    for i in stride(from: 0, to: v.count, by: 8) { s += "  " + v[i..<min(i + 8, v.count)].joined(separator: ", ") + ",\n" }
    return s + "};\n\n"
}
c += arr("tf_ref_x", "float", x.map { String(format: "%.9gf", $0) })
c += arr("tf_ref_re", "float", orr.map { String(format: "%.9gf", $0) })
c += arr("tf_ref_im", "float", oi.map { String(format: "%.9gf", $0) })

// 2) Correlación analítica (copia literal de SignalMath.analyticCorrelation).
let sn = 1024, xn = 40_000, delay = 12_345
var gs = LCG(s: 7), gx = LCG(s: 99)
let s = (0..<sn).map { _ in gs.next() }
var xs = (0..<xn).map { _ in 0.01 * gx.next() }
for i in 0..<sn { xs[delay + i] += 0.5 * s[i] }

func nextPow2(_ n: Int) -> Int { var p = 1; while p < n { p <<= 1 }; return p }
let m = nextPow2(xn + sn)
let fwd = vDSP_DFT_zop_CreateSetupD(nil, vDSP_Length(m), .FORWARD)!
let inv = vDSP_DFT_zop_CreateSetupD(fwd, vDSP_Length(m), .INVERSE)!
let zeros = [Double](repeating: 0, count: m)
var xr = zeros, sr = zeros
vDSP_vspdp(xs, 1, &xr, 1, vDSP_Length(xn))
vDSP_vspdp(s, 1, &sr, 1, vDSP_Length(sn))
var xR = zeros, xI = zeros, sR = zeros, sI = zeros
vDSP_DFT_ExecuteD(fwd, xr, zeros, &xR, &xI)
vDSP_DFT_ExecuteD(fwd, sr, zeros, &sR, &sI)
var cR = zeros, cI = zeros
for k in 0...(m / 2) {
    let w: Double = (k == 0 || k == m / 2) ? 1 : 2
    cR[k] = w * (xR[k] * sR[k] + xI[k] * sI[k])
    cI[k] = w * (xI[k] * sR[k] - xR[k] * sI[k])
}
var oR = zeros, oI = zeros
vDSP_DFT_ExecuteD(inv, cR, cI, &oR, &oI)
let scale = 1 / Double(m)
var env = [Double](repeating: 0, count: xn)
for k in 0..<xn { env[k] = (oR[k] * oR[k] + oI[k] * oI[k]).squareRoot() * scale }
let peak = env.indices.max { env[$0] < env[$1] }!
let (a, b, cc) = (env[peak - 1], env[peak], env[peak + 1])
let frac = 0.5 * (a - cc) / (a - 2 * b + cc)
let step = 40
c += "const int tf_corr_peak = \(peak);\n"
c += "const double tf_corr_peak_pos = \(String(format: "%.17g", Double(peak) + frac));\n"
c += "const double tf_corr_peak_val = \(String(format: "%.17g", b));\n"
c += arr("tf_corr_env", "double", stride(from: 0, to: xn, by: step).map { String(format: "%.17g", env[$0]) })
try! c.write(toFile: out, atomically: true, encoding: .utf8)
print("n=\(n) bins=\(n / 2) | corr m=\(m) pico=\(peak) pos=\(Double(peak) + frac) val=\(b) | muestras env=\(xn / step)")
