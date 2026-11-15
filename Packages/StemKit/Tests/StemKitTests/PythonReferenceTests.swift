import XCTest
@testable import StemKit

/// Comparación con la referencia Python de P4 (sw_common.demix_np + stft_np/istft_np + postproceso
/// de compare.py vía coremlpub) usando máscaras constantes en lugar del modelo.
/// Solo si `TF_REF_DIR` apunta a la salida de un script que escribe `mix.wav` y los 6 `<stem>.wav`
/// con las máscaras de `gains`; `TF_REF_CHUNK` da el trozo (51 200 por defecto).
final class PythonReferenceTests: XCTestCase {
    static let gains: [(re: Float, im: Float)] = [(1, 0), (0.5, 0), (0, 1), (0, -1), (2, 0), (-0.7, 0.7)]

    func testMatchesPythonReferenceWithConstantMasks() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dirPath = env["TF_REF_DIR"] else { throw XCTSkip("TF_REF_DIR no definido") }
        let dir = URL(fileURLWithPath: dirPath)
        let chunk = Int(env["TF_REF_CHUNK"] ?? "") ?? 51_200
        let out = try makeTempDir("pyref")
        let model = ConstantMaskModel(frames: chunk / RoformerContract.hop + 1, gains: Self.gains)
        try RoformerSeparator(model: model).separate(input: dir.appendingPathComponent("mix.wav"), outputDirectory: out)
        for s in Stem.allCases {
            let ref = try AudioIO.readStereo(dir.appendingPathComponent(s.fileName))
            let est = try AudioIO.readStereo(out.appendingPathComponent(s.fileName))
            XCTAssertEqual(ref.frameCount, est.frameCount)
            var maxErr: Float = 0
            for k in 0..<ref.frameCount {
                maxErr = max(maxErr, abs(ref.left[k] - est.left[k]), abs(ref.right[k] - est.right[k]))
            }
            let snr = snrDB(ref, est)
            print("Swift frente a Python, trozo \(chunk), \(s.rawValue): SNR \(String(format: "%.1f", snr)) dB, "
                  + "error máximo \(maxErr)")
            XCTAssertGreaterThan(snr, 100, s.rawValue)
            XCTAssertLessThan(maxErr, 1e-4, s.rawValue)
        }
    }
}
