// Lee un MP4 de la prueba d con AVAssetReader: duración, códecs, fotograma blanco y clic (escritos en t = 1,000 s).
// uso: swift mp4check.swift <mp4>...
import AVFoundation

for path in CommandLine.arguments.dropFirst() {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let dur = CMTimeGetSeconds(asset.duration)
    let vt = asset.tracks(withMediaType: .video).first!
    let at = asset.tracks(withMediaType: .audio).first
    func fourcc(_ t: AVAssetTrack) -> String {
        let d = t.formatDescriptions.first as! CMFormatDescription
        let c = CMFormatDescriptionGetMediaSubType(d)
        return String(bytes: [24, 16, 8, 0].map { UInt8((c >> $0) & 0xff) }, encoding: .ascii) ?? "?"
    }
    let reader = try! AVAssetReader(asset: asset)
    let vo = AVAssetReaderTrackOutput(track: vt, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
    reader.add(vo)
    var ao: AVAssetReaderTrackOutput?
    if let at {
        ao = AVAssetReaderTrackOutput(track: at, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
                                                                   AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false])
        reader.add(ao!)
    }
    reader.startReading()
    var frames = 0, whiteT = -1.0, whiteY = 0.0, firstVT = -1.0
    while let sb = vo.copyNextSampleBuffer() {
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
        let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
        if firstVT < 0 { firstVT = t }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0), h = CVPixelBufferGetHeightOfPlane(pb, 0), w = CVPixelBufferGetWidthOfPlane(pb, 0)
        var sum = 0
        for y in Swift.stride(from: 0, to: h, by: 4) { for x in Swift.stride(from: 0, to: w, by: 4) { sum += Int(base[y * stride + x]) } }
        CVPixelBufferUnlockBaseAddress(pb, .readOnly)
        let mean = Double(sum) / Double((h / 4) * (w / 4))
        if mean > whiteY { whiteY = mean; whiteT = t }
        frames += 1
    }
    var clickT = -1.0, firstAT = -1.0, nSamples = 0
    if let ao {
        while let sb = ao.copyNextSampleBuffer(), clickT < 0 {
            let t0 = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
            if firstAT < 0 { firstAT = t0 }
            let bb = CMSampleBufferGetDataBuffer(sb)!
            var len = 0
            var ptr: UnsafeMutablePointer<CChar>?
            CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &len, dataPointerOut: &ptr)
            let f = UnsafeRawPointer(ptr!).assumingMemoryBound(to: Float.self)
            let n = len / 8   // estéreo f32
            for i in 0..<n where abs(f[2 * i]) > 0.5 { clickT = t0 + Double(i) / 48_000; break }
            nSamples += n
        }
    }
    print((path as NSString).lastPathComponent)
    print(String(format: "  duración %.3f s, vídeo %@ %d fotogramas (primero %.4f s), audio %@", dur, fourcc(vt), frames, firstVT, at.map(fourcc) ?? "-"))
    print(String(format: "  blanco en %.4f s (Y %.0f), clic en %.4f s (primer audio %.4f s) → desfase A/V clic − blanco %+.1f ms",
                 whiteT, whiteY, clickT, firstAT, (clickT - whiteT) * 1e3))
}
