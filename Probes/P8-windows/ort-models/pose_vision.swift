// Referencia de Vision para el encuadre (P8, parte 7.3): mismos fotogramas que pose.py.
// Uso: swiftc -O pose_vision.swift -o out/pose/pose_vision && out/pose/pose_vision <video> <outdir> <t1> <t2> ...
// Escribe <outdir>/frame_<i>.png (imagen ya orientada) y <outdir>/vision.json con las 10 articulaciones de
// GuitarFramer (persona más grande, confianza >= 0.3, normalizadas con origen arriba a la izquierda), igual
// que GuitarFramer.joints(in:) de VideoKit. Además ms por fotograma de la petición de Vision.
import AVFoundation
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

let a = CommandLine.arguments
guard a.count >= 4 else { print("uso: pose_vision <video> <outdir> <t>..."); exit(2) }
let url = URL(fileURLWithPath: a[1]), out = URL(fileURLWithPath: a[2])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
gen.appliesPreferredTrackTransform = true
gen.requestedTimeToleranceBefore = .zero
gen.requestedTimeToleranceAfter = .zero
let names: [(String, VNHumanBodyPoseObservation.JointName)] = [
    ("leftWrist", .leftWrist), ("rightWrist", .rightWrist), ("leftElbow", .leftElbow), ("rightElbow", .rightElbow),
    ("leftShoulder", .leftShoulder), ("rightShoulder", .rightShoulder), ("neck", .neck), ("root", .root),
    ("leftHip", .leftHip), ("rightHip", .rightHip)]
var frames: [[String: Any]] = []
for (i, ts) in a[3...].enumerated() {
    let t = CMTime(seconds: Double(ts)!, preferredTimescale: 600)
    let img = try gen.copyCGImage(at: t, actualTime: nil)
    let png = out.appendingPathComponent("frame_\(i).png")
    let dst = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, img, nil)
    CGImageDestinationFinalize(dst)
    var ms: [Double] = []
    var best: [String: [Double]] = [:]
    for _ in 0..<4 {
        let req = VNDetectHumanBodyPoseRequest()
        let t0 = Date()
        try VNImageRequestHandler(cgImage: img, orientation: .up).perform([req])
        ms.append(Date().timeIntervalSince(t0) * 1000)
        best = [:]
        var bestArea = -1.0
        for obs in req.results ?? [] {
            var j: [String: [Double]] = [:]
            for (k, n) in names {
                guard let p = try? obs.recognizedPoint(n), p.confidence >= 0.3 else { continue }
                j[k] = [Double(p.location.x), 1 - Double(p.location.y), Double(p.confidence)]
            }
            guard !j.isEmpty else { continue }
            let xs = j.values.map { $0[0] }, ys = j.values.map { $0[1] }
            let area = (xs.max()! - xs.min()!) * (ys.max()! - ys.min()!)
            if area > bestArea { bestArea = area; best = j }
        }
    }
    frames.append(["t": Double(ts)!, "png": png.lastPathComponent, "w": img.width, "h": img.height,
                   "joints": best, "ms_first": ms[0], "ms_median": ms.dropFirst().sorted()[1]])
}
let data = try JSONSerialization.data(withJSONObject: ["video": url.lastPathComponent, "frames": frames],
                                      options: [.prettyPrinted, .sortedKeys])
try data.write(to: out.appendingPathComponent("vision.json"))
print("vision: \(frames.count) fotogramas -> \(out.path)/vision.json")
