import Dispatch
import Foundation
@_spi(Simulation) import StemKit
import Synchronization

/// tf-separate --model <.mlmodelc> --input <wav> --out <dir>
///
/// Separa un tema en 6 stems en este proceso (la app lo lanza aparte y lo vigila con MemoryGuard).
/// stdout: una línea JSON por evento — {"stage":"loading"}, {"stage":"separating","chunk":k,"of":n},
/// {"stage":"done","seconds":s}. Errores en stderr.
/// Códigos de salida: 0 bien, 1 error, 2 uso incorrecto, 143 interrumpido por SIGTERM (sin ficheros a medias).
///
/// Flags ocultos (tests de integración, sin modelo): --simulate [--sim-frames N] [--sim-delay-ms N].
@main
struct TFSeparate {
    static let exitFailure: Int32 = 1
    static let exitUsage: Int32 = 2
    static let exitTerminated: Int32 = 128 + SIGTERM

    final class CancelFlag: Sendable {
        private let value = Atomic<Bool>(false)
        func set() { value.store(true, ordering: .relaxed) }
        var isSet: Bool { value.load(ordering: .relaxed) }
    }

    static func emit(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    static func fail(_ message: String, code: Int32) -> Never {
        FileHandle.standardError.write(Data(("tf-separate: " + message + "\n").utf8))
        exit(code)
    }

    static func main() {
        var opts: [String: String] = [:]
        var simulate = false
        var args = CommandLine.arguments.dropFirst()
        while let a = args.popFirst() {
            switch a {
            case "--model", "--input", "--out", "--sim-frames", "--sim-delay-ms":
                guard let v = args.popFirst() else { fail("falta el valor de \(a)", code: exitUsage) }
                opts[a] = v
            case "--simulate":
                simulate = true
            default:
                fail("argumento desconocido \(a)\nuso: tf-separate --model <.mlmodelc> --input <wav> --out <dir>",
                     code: exitUsage)
            }
        }
        guard let input = opts["--input"], let out = opts["--out"], simulate || opts["--model"] != nil else {
            fail("uso: tf-separate --model <.mlmodelc> --input <wav> --out <dir>", code: exitUsage)
        }

        let cancel = CancelFlag()
        let source = installSigtermHandler(cancel)

        emit(#"{"stage":"loading"}"#)
        let separator: RoformerSeparator
        if simulate {
            let frames = Int(opts["--sim-frames"] ?? "") ?? 1151
            let delay = (Double(opts["--sim-delay-ms"] ?? "") ?? 0) / 1000
            separator = RoformerSeparator(simulatedFrames: frames, delayPerChunk: delay)
        } else {
            do {
                separator = try RoformerSeparator(compiledModelURL: URL(fileURLWithPath: opts["--model"]!))
            } catch {
                fail("no se pudo cargar el modelo: \(describe(error))", code: exitFailure)
            }
        }
        if cancel.isSet { fail("interrumpido por SIGTERM", code: exitTerminated) }

        let start = Date()
        do {
            try separator.separate(
                input: URL(fileURLWithPath: input), outputDirectory: URL(fileURLWithPath: out),
                progress: { k, n in emit(#"{"stage":"separating","chunk":\#(k),"of":\#(n)}"#) },
                cancel: { cancel.isSet })
        } catch SeparationError.cancelled {
            fail("interrumpido por SIGTERM", code: exitTerminated)
        } catch {
            #if os(Windows)
            // Parada ordenada: la inferencia cortada sale como error de ONNX Runtime (parte 7.8).
            if cancel.isSet { fail("interrumpido por el evento de parada", code: exitTerminated) }
            #endif
            fail(describe(error), code: exitFailure)
        }
        let seconds = Date().timeIntervalSince(start)
        emit(#"{"stage":"done","seconds":\#(String(format: "%.3f", seconds))}"#)
        withExtendedLifetime(source) {}
        exit(0)
    }

    /// SIGTERM solo levanta la bandera; el separador la consulta antes de cada trozo.
    /// `nonisolated`: el manejador corre en una cola global y no debe heredar el aislamiento de `main()`
    /// (si lo hereda, la comprobación de actor del runtime aborta el proceso al llegar la señal).
    ///
    /// Windows: la fuente se crea (P8), pero ningún proceso puede mandar SIGTERM a otro; la parada ordenada es el
    /// evento con nombre de `SeparationRunner` (`HelperStop`, parte 7.8), que levanta la misma bandera.
    nonisolated static func installSigtermHandler(_ flag: CancelFlag) -> DispatchSourceSignal {
        #if !os(Windows)
        signal(SIGTERM, SIG_IGN)
        #else
        HelperStop.watchParent { flag.set() }
        #endif
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        source.setEventHandler { flag.set() }
        source.resume()
        return source
    }

    static func describe(_ error: Error) -> String {
        if case SeparationError.invalidInput(let msg) = error { return "entrada no válida: \(msg)" }
        return "\(error)"
    }
}
