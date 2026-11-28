import Foundation

/// Canalización productor/consumidor con cola acotada: uno o varios hilos propios producen los elementos `0..<count` y
/// el llamador los recoge en orden con `next()`. Sirve a la exportación de Windows (decodificar, componer y codificar en
/// hilos distintos). Con `workers > 1` los elementos se producen en paralelo (cada hilo coge el siguiente índice libre)
/// pero se entregan siempre en orden. Se producen como mucho `capacity` elementos por delante del consumidor; con la
/// cola llena los hilos esperan. `stop()` los despierta y espera a que acaben, así que tras él nadie toca ya lo que usaba
/// `produce`.
final class FramePipeline<Item: Sendable>: @unchecked Sendable {
    /// Elementos por delante del consumidor como máximo (memoria acotada: cada uno lleva las tomas ya en BGRA).
    static var defaultCapacity: Int { 6 }

    private let count: Int
    private let capacity: Int
    private let workers: Int
    private let produce: @Sendable (_ index: Int, _ worker: Int) throws -> Item
    private let cond = NSCondition()
    private var results: [Int: Item] = [:]
    private var nextClaim = 0
    private var consumed = 0
    private var failure: Error?
    private var stopped = false
    private var started = false
    private var running = 0

    init(count: Int, capacity: Int = FramePipeline.defaultCapacity, workers: Int = 1,
         produce: @escaping @Sendable (_ index: Int, _ worker: Int) throws -> Item) {
        self.count = count
        self.capacity = max(1, capacity)
        self.workers = max(1, workers)
        self.produce = produce
    }

    convenience init(count: Int, capacity: Int = FramePipeline.defaultCapacity, produce: @escaping @Sendable (Int) throws -> Item) {
        self.init(count: count, capacity: capacity, workers: 1) { i, _ in try produce(i) }
    }

    /// Arranca los hilos productores (una sola vez).
    func start() {
        cond.lock()
        guard !started else { cond.unlock(); return }
        started = true
        running = workers
        cond.unlock()
        for w in 0..<workers {
            let thread = Thread { [self] in run(worker: w) }
            thread.stackSize = 4 << 20
            thread.name = "ToneForge.export.producer.\(w)"
            thread.start()
        }
    }

    private func run(worker: Int) {
        defer { cond.lock(); running -= 1; cond.broadcast(); cond.unlock() }
        while true {
            cond.lock()
            while !stopped && failure == nil && nextClaim < count && nextClaim - consumed >= capacity { cond.wait() }
            if stopped || failure != nil || nextClaim >= count { cond.unlock(); return }
            let i = nextClaim
            nextClaim += 1
            cond.unlock()
            do {
                let item = try produce(i, worker)
                cond.lock()
                results[i] = item
                cond.broadcast()
                cond.unlock()
            } catch {
                cond.lock()
                if failure == nil { failure = error }
                cond.broadcast()
                cond.unlock()
                return
            }
        }
    }

    /// Siguiente elemento en orden; espera si aún no está. Lanza el error del productor (tras entregar lo ya producido)
    /// o `CancellationError` si se paró la canalización.
    func next() throws -> Item {
        cond.lock()
        defer { cond.unlock() }
        while results[consumed] == nil && !stopped && !(started && running == 0) { cond.wait() }
        if stopped { throw CancellationError() }
        if let item = results.removeValue(forKey: consumed) {
            consumed += 1
            cond.broadcast()
            return item
        }
        if let failure { throw failure }
        throw CancellationError()
    }

    /// Para los productores y espera a que terminen (idempotente). Los `next()` pendientes lanzan `CancellationError`.
    func stop() {
        cond.lock()
        stopped = true
        results.removeAll()
        cond.broadcast()
        while started && running > 0 { cond.wait() }
        cond.unlock()
    }
}
