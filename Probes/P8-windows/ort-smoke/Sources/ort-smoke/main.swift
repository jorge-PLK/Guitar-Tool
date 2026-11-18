// ONNX Runtime desde Swift por la API C (Fase 7c paso 4, tf-ml).
//
//   ort-smoke                                       versión, DLL cargada y proveedores
//   ort-smoke <dir> [--runs N] [--threads N] [--dump]
//
// <dir>/manifest.txt, una orden por línea (rutas relativas a <dir>):
//   model <fichero.onnx>
//   in  <nombre> <fichero.bin> <d0,d1,...>      float32 little-endian
//   out <nombre> <ref.bin> [argmax|thr=<v>]      referencia float32 (salida de ORT CPU en el Mac)
//   ref2 <nombre> <ref.bin> [argmax|thr=<v>]     segunda referencia opcional (Core ML / PyTorch)
//   runs_per_minute <k>                          inferencias por minuto de audio (tiempo por minuto)
// Salida: líneas TF:... resumidas (una por métrica).
import COnnxRuntime
import Foundation

guard let apiPtr = tf_ort_api() else {
    print("ERROR GetApi(ORT_API_VERSION=\(ORT_API_VERSION)) devolvió NULL: DLL más antigua que las cabeceras")
    exit(2)
}
let api = apiPtr.pointee

#if arch(arm64)
let archName = "arm64"
#else
let archName = "x64"
#endif

func fail(_ msg: String) -> Never {
    print("ERROR \(msg)")
    exit(1)
}

func check(_ status: OpaquePointer?, _ what: String) {
    guard let status else { return }
    let msg = String(cString: api.GetErrorMessage!(status)!)
    api.ReleaseStatus!(status)
    fail("\(what): \(msg)")
}

func cstr(_ s: String) -> UnsafePointer<CChar> {
    let u = Array(s.utf8CString)
    let p = UnsafeMutablePointer<CChar>.allocate(capacity: u.count)
    p.initialize(from: u, count: u.count)
    return UnsafePointer(p)
}

func gb(_ bytes: Int) -> String { String(format: "%.2f", Double(bytes) / 1_073_741_824) }
func secs(_ d: Duration) -> Double {
    Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
}

// MARK: versión y proveedores

var providers: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
var nProviders: Int32 = 0
check(api.GetAvailableProviders!(&providers, &nProviders), "GetAvailableProviders")
let providerNames = (0..<Int(nProviders)).map { String(cString: providers![$0]!) }
check(api.ReleaseAvailableProviders!(providers, nProviders), "ReleaseAvailableProviders")

var env: OpaquePointer?
check(api.CreateEnv!(ORT_LOGGING_LEVEL_WARNING, "ort-smoke", &env), "CreateEnv")
print("TF:ORT arch=\(archName) version=\(String(cString: tf_ort_version())) api=\(ORT_API_VERSION)")
print("TF:DLL \(String(cString: tf_loaded_ort_path()))")
print("TF:PROVIDERS \(providerNames.joined(separator: ","))")

let args = Array(CommandLine.arguments.dropFirst())
guard let dir = args.first else { exit(0) }
func opt(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
let runs = Int(opt("--runs") ?? "3") ?? 3
let threads = Int(opt("--threads") ?? "0") ?? 0
let dump = args.contains("--dump")

// MARK: manifiesto

struct Input { let name: String; let file: String; let shape: [Int64] }
struct Ref { let name: String; let file: String; let mode: String?; let tag: String }
var modelFile = ""
var inputs: [Input] = []
var refs: [Ref] = []
var outNames: [String] = []
var runsPerMinute = 0.0
let manifestPath = dir + "/manifest.txt"
guard let manifest = try? String(contentsOfFile: manifestPath, encoding: .utf8) else { fail("no se lee \(manifestPath)") }
for line in manifest.split(whereSeparator: \.isNewline) {
    let f = line.split(separator: " ").map(String.init)
    guard let cmd = f.first, !cmd.hasPrefix("#") else { continue }
    switch cmd {
    case "model": modelFile = f[1]
    case "in": inputs.append(Input(name: f[1], file: f[2], shape: f[3].split(separator: ",").map { Int64($0)! }))
    case "out", "ref2":
        if cmd == "out" { outNames.append(f[1]) }
        refs.append(Ref(name: f[1], file: f[2], mode: f.count > 3 ? f[3] : nil, tag: cmd == "out" ? "mac_ort" : "ref2"))
    case "runs_per_minute": runsPerMinute = Double(f[1]) ?? 0
    default: fail("orden desconocida: \(cmd)")
    }
}

// MARK: sesión

var options: OpaquePointer?
check(api.CreateSessionOptions!(&options), "CreateSessionOptions")
check(api.SetSessionGraphOptimizationLevel!(options, ORT_ENABLE_ALL), "SetSessionGraphOptimizationLevel")
if threads > 0 { check(api.SetIntraOpNumThreads!(options, Int32(threads)), "SetIntraOpNumThreads") }
var session: OpaquePointer?
let clock = ContinuousClock()
let tCreate = clock.now
check(tf_create_session(apiPtr, env, dir + "/" + modelFile, options, &session), "CreateSession \(modelFile)")
let createS = secs(clock.now - tCreate)

var allocator: UnsafeMutablePointer<OrtAllocator>?
check(api.GetAllocatorWithDefaultOptions!(&allocator), "GetAllocatorWithDefaultOptions")

func describe(_ typeInfo: OpaquePointer?) -> String {
    var tensorInfo: OpaquePointer?
    check(api.CastTypeInfoToTensorInfo!(typeInfo, &tensorInfo), "CastTypeInfoToTensorInfo")
    guard let tensorInfo else { return "?" }
    var nd = 0
    check(api.GetDimensionsCount!(tensorInfo, &nd), "GetDimensionsCount")
    var dims = [Int64](repeating: 0, count: nd)
    check(api.GetDimensions!(tensorInfo, &dims, nd), "GetDimensions")
    var et = ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED
    check(api.GetTensorElementType!(tensorInfo, &et), "GetTensorElementType")
    return "\(dims.map(String.init).joined(separator: "x"))/t\(et.rawValue)"
}

func ioList(input: Bool) -> [String] {
    var n = 0
    check(input ? api.SessionGetInputCount!(session, &n) : api.SessionGetOutputCount!(session, &n), "SessionGetCount")
    return (0..<n).map { i in
        var name: UnsafeMutablePointer<CChar>?
        check(input ? api.SessionGetInputName!(session, i, allocator, &name)
                    : api.SessionGetOutputName!(session, i, allocator, &name), "SessionGetName")
        let s = String(cString: name!)
        check(api.AllocatorFree!(allocator, name), "AllocatorFree")
        var ti: OpaquePointer?
        check(input ? api.SessionGetInputTypeInfo!(session, i, &ti) : api.SessionGetOutputTypeInfo!(session, i, &ti),
              "SessionGetTypeInfo")
        defer { api.ReleaseTypeInfo!(ti) }
        return "\(s):\(describe(ti))"
    }
}
print("TF:IO in=[\(ioList(input: true).joined(separator: " "))] out=[\(ioList(input: false).joined(separator: " "))]")
if outNames.isEmpty { outNames = ioList(input: false).map { String($0.split(separator: ":")[0]) } }

// MARK: tensores de entrada (memoria propia, viva toda la ejecución)

var memInfo: OpaquePointer?
check(api.CreateCpuMemoryInfo!(OrtArenaAllocator, OrtMemTypeDefault, &memInfo), "CreateCpuMemoryInfo")

func readFloats(_ file: String) -> [Float] {
    guard let d = FileManager.default.contents(atPath: dir + "/" + file) else { fail("no se lee \(file)") }
    return d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}

var inputValues: [OpaquePointer?] = []
for inp in inputs {
    let floats = readFloats(inp.file)
    let expected = inp.shape.reduce(1, *)
    guard floats.count == expected else { fail("\(inp.file): \(floats.count) floats, la forma pide \(expected)") }
    let buf = UnsafeMutablePointer<Float>.allocate(capacity: floats.count)
    buf.initialize(from: floats, count: floats.count)
    var value: OpaquePointer?
    check(api.CreateTensorWithDataAsOrtValue!(memInfo, buf, floats.count * 4, inp.shape, inp.shape.count,
                                              ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &value), "CreateTensor \(inp.name)")
    inputValues.append(value)
}
let inNamesC: [UnsafePointer<CChar>?] = inputs.map { cstr($0.name) }
let outNamesC: [UnsafePointer<CChar>?] = outNames.map { cstr($0) }

// MARK: ejecución

func runOnce() -> (Double, [OpaquePointer?]) {
    var outs = [OpaquePointer?](repeating: nil, count: outNamesC.count)
    let t = clock.now
    check(api.Run!(session, nil, inNamesC, inputValues, inputValues.count, outNamesC, outNamesC.count, &outs), "Run")
    return (secs(clock.now - t), outs)
}
func release(_ outs: [OpaquePointer?]) { outs.forEach { api.ReleaseValue!($0) } }

let (firstS, firstOuts) = runOnce()
release(firstOuts)
var times: [Double] = []
var lastOuts: [OpaquePointer?] = []
for i in 0..<max(runs, 1) {
    let (t, outs) = runOnce()
    times.append(t)
    if i == max(runs, 1) - 1 { lastOuts = outs } else { release(outs) }
}
let median = times.sorted()[times.count / 2]
var timing = "TF:TIME arch=\(archName) threads=\(threads)"
    + String(format: " create=%.2fs first=%.3fs median=%.3fs", createS, firstS, median) + " runs=\(times.count)"
if runsPerMinute > 0 { timing += String(format: " per_min=%.1fs", median * runsPerMinute) }
print(timing + " peak_ws=\(gb(tf_peak_working_set()))GB")

// MARK: comparación

func outputFloats(_ value: OpaquePointer?) -> (UnsafeBufferPointer<Float>, [Int64]) {
    var info: OpaquePointer?
    check(api.GetTensorTypeAndShape!(value, &info), "GetTensorTypeAndShape")
    defer { api.ReleaseTensorTypeAndShapeInfo!(info) }
    var count = 0
    check(api.GetTensorShapeElementCount!(info, &count), "GetTensorShapeElementCount")
    var nd = 0
    check(api.GetDimensionsCount!(info, &nd), "GetDimensionsCount")
    var dims = [Int64](repeating: 0, count: nd)
    check(api.GetDimensions!(info, &dims, nd), "GetDimensions")
    var et = ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED
    check(api.GetTensorElementType!(info, &et), "GetTensorElementType")
    guard et == ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT else { fail("salida no float32 (tipo \(et.rawValue))") }
    var p: UnsafeMutableRawPointer?
    check(api.GetTensorMutableData!(value, &p), "GetTensorMutableData")
    return (UnsafeBufferPointer(start: p!.bindMemory(to: Float.self, capacity: count), count: count), dims)
}

for (k, name) in outNames.enumerated() {
    let (out, dims) = outputFloats(lastOuts[k])
    if dump {
        let file = "\(dir)/\(name.replacingOccurrences(of: ":", with: "_")).\(archName).out.bin"
        FileManager.default.createFile(atPath: file, contents: Data(buffer: out))
    }
    for ref in refs where ref.name == name {
        let r = readFloats(ref.file)
        guard r.count == out.count else { fail("\(ref.file): \(r.count) floats, la salida tiene \(out.count)") }
        var maxAbs: Float = 0, sumAbs = 0.0, sumRef = 0.0, sumErr = 0.0
        for i in 0..<r.count {
            let d = out[i] - r[i]
            maxAbs = max(maxAbs, abs(d))
            sumAbs += Double(abs(d))
            sumRef += Double(r[i]) * Double(r[i])
            sumErr += Double(d) * Double(d)
        }
        let snr = sumErr > 0 ? 10 * log10(sumRef / sumErr) : .infinity
        var line = "TF:DIFF arch=\(archName) out=\(name) vs=\(ref.tag)"
            + String(format: " max=%.3g mean=%.3g snr=%.1fdB", Double(maxAbs), sumAbs / Double(r.count), snr)
        if ref.mode == "argmax", let last = dims.last, last > 0 {
            let c = Int(last), rows = r.count / c
            var same = 0
            for row in 0..<rows {
                let o = (0..<c).max { out[row * c + $0] < out[row * c + $1] }!
                let e = (0..<c).max { r[row * c + $0] < r[row * c + $1] }!
                if o == e { same += 1 }
            }
            line += " argmax_igual=\(same)/\(rows)"
        } else if let mode = ref.mode, mode.hasPrefix("thr="), let thr = Float(mode.dropFirst(4)) {
            var same = 0, pos = 0
            for i in 0..<r.count {
                if (out[i] > thr) == (r[i] > thr) { same += 1 }
                if r[i] > thr { pos += 1 }
            }
            line += " umbral_igual=\(same)/\(r.count) positivos_ref=\(pos)"
        }
        print(line)
    }
}
release(lastOuts)
exit(0)
