// Referencia de decodificación con AVAudioFile (lo que hace AudioImporter) para la prueba c.
// uso: swift decref.swift <fichero>...
import AVFoundation

for path in CommandLine.arguments.dropFirst() {
    let f = try! AVAudioFile(forReading: URL(fileURLWithPath: path))
    let fmt = f.processingFormat
    let n = AVAudioFrameCount(f.length)
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n)!
    try! f.read(into: buf)
    let ch0 = buf.floatChannelData![0]
    var sum = 0.0, first = -1, peak: Float = 0
    for i in 0..<Int(buf.frameLength) {
        let v = ch0[i]
        sum += Double(v * v)
        peak = max(peak, abs(v))
        if first < 0 && abs(v) > 0.01 { first = i }
    }
    let rms = (sum / Double(buf.frameLength)).squareRoot()
    print(String(format: "%@: frames %d sr %.0f ch %d rms %.6f pico %.6f primera>0.01 %d",
                 (path as NSString).lastPathComponent, Int(buf.frameLength), fmt.sampleRate, Int(fmt.channelCount), rms, peak, first))
}
