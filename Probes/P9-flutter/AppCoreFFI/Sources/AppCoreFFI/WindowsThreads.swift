import CAppCoreFFI
import Foundation

// P9 prueba 7: autodiagnóstico de si la cola principal de Swift se drena (Windows: vía 1 o vía 2).

extension CoreState {
    /// 0 lanzada; 1 núcleo sin arrancar. Nunca bloquea al que llama: la espera ocurre en un hilo aparte y el
    /// resultado sale como evento `probe.mainactor` por el sumidero.
    func debugMainActorSelftest(timeoutMs: Int32) -> Int32 {
        guard isStarted else { return 1 }
        let thread = Thread { [self] in
            let actorSem = DispatchSemaphore(value: 0)
            let mainSem = DispatchSemaphore(value: 0)
            let t0 = tf_debug_now_ns()
            Task { @MainActor in actorSem.signal() }
            DispatchQueue.main.async { mainSem.signal() }
            let deadline = DispatchTime.now() + .milliseconds(Int(max(timeoutMs, 0)))
            let mainActor = actorSem.wait(timeout: deadline) == .success
            let dispatchMain = mainSem.wait(timeout: deadline) == .success
            let ms = (tf_debug_now_ns() - t0) / 1_000_000
            emit("{\"event\":\"probe.mainactor\",\"payload\":{\"mainActor\":\(mainActor),\"dispatchMain\":\(dispatchMain),\"ms\":\(ms)}}")
        }
        thread.name = "tf-debug-mainactor"
        thread.start()
        return 0
    }
}
