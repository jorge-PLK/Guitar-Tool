// P6: render offline con AVAudioEngine: AVAudioPlayerNode -> AVAudioUnitTimePitch -> salida.
// Uso: applerender <in.wav> <out.wav> --rate <r> --pitch-cents <c> --overlap <n>
// Escribe en stdout una línea JSON con {"cpu_s", "frames", "seconds"}; cpu_s es el tiempo de CPU
// del proceso solo durante el bucle de render (sin arranque del motor ni E/S de fichero).
import AVFoundation
import Foundation

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(1)
}

var args = Array(CommandLine.arguments.dropFirst())
var rate: Float = 1
var pitchCents: Float = 0
var overlap: Float = 8
var positional: [String] = []
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--rate": rate = Float(args.removeFirst()) ?? 1
    case "--pitch-cents": pitchCents = Float(args.removeFirst()) ?? 0
    case "--overlap": overlap = Float(args.removeFirst()) ?? 8
    default: positional.append(a)
    }
}
guard positional.count == 2 else { fail("uso: applerender <in.wav> <out.wav> --rate r --pitch-cents c --overlap n") }

func cpuSeconds() -> Double {
    var ru = rusage()
    getrusage(RUSAGE_SELF, &ru)
    let u = Double(ru.ru_utime.tv_sec) + Double(ru.ru_utime.tv_usec) / 1e6
    let s = Double(ru.ru_stime.tv_sec) + Double(ru.ru_stime.tv_usec) / 1e6
    return u + s
}

do {
    let inFile = try AVAudioFile(forReading: URL(fileURLWithPath: positional[0]))
    let format = inFile.processingFormat
    let inFrames = AVAudioFrameCount(inFile.length)
    guard let inBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: inFrames) else { fail("sin memoria") }
    try inFile.read(into: inBuf)

    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let tp = AVAudioUnitTimePitch()
    tp.rate = rate
    tp.pitch = pitchCents
    tp.overlap = overlap
    engine.attach(player)
    engine.attach(tp)
    engine.connect(player, to: tp, format: format)
    engine.connect(tp, to: engine.mainMixerNode, format: format)

    let block: AVAudioFrameCount = 512
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: block)
    try engine.start()

    let lock = NSLock()
    var done = false
    // dataConsumed: el player ya ha entregado todo el buffer al TimePitch; la cola se renderiza después.
    player.scheduleBuffer(inBuf, at: nil, options: [], completionCallbackType: .dataConsumed) { _ in
        lock.lock(); done = true; lock.unlock()
    }
    player.play()

    // Duración esperada; se renderiza hasta que el player termina y se añade una cola corta
    // para vaciar el latido interno del TimePitch.
    let expected = Int(Double(inFrames) / Double(rate))
    let tailFrames = Int(0.5 * format.sampleRate)
    let outURL = URL(fileURLWithPath: positional[1])
    try? FileManager.default.removeItem(at: outURL)
    let outFile = try AVAudioFile(forWriting: outURL, settings: inFile.fileFormat.settings,
                                  commonFormat: .pcmFormatFloat32, interleaved: false)
    guard let outBuf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: block) else { fail("sin memoria") }

    var written = 0
    var cpu = 0.0
    var tailLeft = -1
    let cap = expected * 2 + tailFrames
    while written < cap {
        let t0 = cpuSeconds()
        let status = try engine.renderOffline(block, to: outBuf)
        cpu += cpuSeconds() - t0
        if status == .error { fail("renderOffline error") }
        if status == .success || status == .insufficientDataFromInputNode {
            try outFile.write(from: outBuf)
            written += Int(outBuf.frameLength)
        }
        lock.lock(); let d = done; lock.unlock()
        if d && tailLeft < 0 { tailLeft = tailFrames }
        if tailLeft >= 0 {
            tailLeft -= Int(block)
            if tailLeft <= 0 { break }
        }
    }
    player.stop()
    engine.stop()
    let secs = Double(written) / format.sampleRate
    print("{\"cpu_s\": \(cpu), \"frames\": \(written), \"seconds\": \(secs)}")
} catch {
    fail("error: \(error)")
}
