import XCTest
@testable import AudioKit

/// Ficheros de stems soltados de forma determinista (plan, Fase 7c, «Pendiente tras el paso 7»): tras cerrar la sesión
/// y soltar o recargar el reproductor no queda ningún lector abierto, sin esperar a ningún `Task`. Con el reproductor
/// portátil, que es `StudyPlayer` en Windows: allí borrar un fichero abierto falla (violación de compartición), así que
/// `assertDeletableAndRewritable` falla de verdad si queda alguno; en el Mac borrar un abierto funciona y lo que prueba
/// es la referencia débil a cada `AudioFileReader`, que debe ser nil al volver de la llamada.
final class StemFileReleaseTests: XCTestCase {
    static let fs = 48_000.0
    /// Pasadas de soltar el reproductor mientras el hilo de E/S lo renderiza (busca la carrera con el render).
    static let dropRounds = 10

    final class WeakRef {
        weak var object: AnyObject?
        init(_ o: AnyObject) { object = o }
    }

    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("StemFileReleaseTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Backing de clics, un bajo senoidal y una toma desde 0,5 s: tres lectores.
    static func writeStems(in dir: URL, tag: String, seconds: Double = 2) throws -> (tracks: [Track], take: TakeTrack) {
        let n = Int(seconds * fs)
        let clicks = AlignmentCheck.backing(songSeconds: seconds, sampleRate: fs)
        let sine = (0..<n).map { Float(0.3 * sin(2 * Double.pi * 110 * Double($0) / fs)) }
        let backing = dir.appendingPathComponent("backing-\(tag).wav")
        let bass = dir.appendingPathComponent("bass-\(tag).wav")
        let take = dir.appendingPathComponent("take-\(tag).wav")
        try TakeFile.write([clicks, clicks], sampleRate: fs, to: backing)
        try TakeFile.write([sine], sampleRate: fs, to: bass)
        try TakeFile.write([Array(sine.prefix(n / 2))], sampleRate: fs, to: take)
        return ([Track(id: "backing", url: backing), Track(id: "bass", url: bass)],
                TakeTrack(id: "Tú", url: take, songStart: 0.5))
    }

    static func urls(_ s: (tracks: [Track], take: TakeTrack)) -> [URL] { s.tracks.map(\.url) + [s.take.url] }

    /// Referencias débiles a los lectores abiertos del motor (el array fuerte muere al volver).
    @MainActor
    static func weakReaders(_ p: PortableStudyPlayer) -> [WeakRef] {
        (p.engineForTests?.stemReadersForTests ?? []).map { WeakRef($0) }
    }

    static func alive(_ refs: [WeakRef]) -> Int { refs.filter { $0.object != nil }.count }

    /// Borra cada fichero y lo reescribe con otro contenido. En Windows, con un lector abierto, el borrado lanza.
    static func assertDeletableAndRewritable(_ urls: [URL], file: StaticString = #filePath, line: UInt = #line) {
        for (k, url) in urls.enumerated() {
            XCTAssertNoThrow(try FileManager.default.removeItem(at: url), "borrar \(url.lastPathComponent)",
                             file: file, line: line)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "sigue ahí \(url.lastPathComponent)",
                           file: file, line: line)
            let v = Float(k + 1) * 0.125
            XCTAssertNoThrow(try TakeFile.write([[Float](repeating: v, count: 256)], sampleRate: fs, to: url),
                             "reescribir \(url.lastPathComponent)", file: file, line: line)
            let back = try? TakeFile.read(url)
            XCTAssertEqual(back?.first?.count, 256, url.lastPathComponent, file: file, line: line)
            XCTAssertEqual(back?.first?.first ?? -1, v, url.lastPathComponent, file: file, line: line)
        }
    }

    /// Hilo de E/S simulado sin pausa (para que el render coincida con el cierre); para con `stop`.
    static func startPumping(_ io: SimulatedAudioIO) -> AudioSessionTests.Box<Bool> {
        let stop = AudioSessionTests.Box<Bool>()
        let t = Thread {
            while stop.get() != true {
                io.pump()
                Thread.sleep(forTimeInterval: 0.000_2)
            }
        }
        t.start()
        return stop
    }

    @MainActor
    static func waitForAnchor(_ s: AudioSession) async throws -> Bool {
        for _ in 0..<400 where s.playbackAnchor == nil { try await Task.sleep(for: .milliseconds(5)) }
        return s.playbackAnchor != nil
    }

    // MARK: Soltar el reproductor con la sesión abierta y renderizando

    /// La sesión sigue abierta y su hilo de E/S renderiza el reproductor alojado sin parar; se suelta el reproductor
    /// sonando. Al volver de `player = nil` los tres lectores están muertos y los ficheros se borran y reescriben, en
    /// las `dropRounds` pasadas. El render sigue entrando en el motor (la sesión aún lo retiene hasta cerrarse) sin
    /// tocar ningún lector: sigue bombeando 50 ms más sin fallo y el ancla desaparece.
    @MainActor
    func testDroppingHostedPlayerClosesStemsWhileSessionRenders() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let io = AudioSessionTests.rigIO(Self.fs)
        let s = AudioSessionTests.session(io, guitarIn: [1])
        try s.open()
        defer { s.close() }
        let stop = Self.startPumping(io)
        defer { stop.set(true) }

        var leftOpen = 0, anchored = 0
        for round in 0..<Self.dropRounds {
            let stems = try Self.writeStems(in: dir, tag: "\(round)")
            var player: PortableStudyPlayer? = PortableStudyPlayer(devices: SimulatedDeviceProvider(devices: [], defaultID: nil))
            try player!.load(tracks: stems.tracks)
            try player!.setTake(stems.take)
            try player!.attach(to: s)
            try player!.play()
            if try await Self.waitForAnchor(s) { anchored += 1 }
            let readers = Self.weakReaders(player!)
            XCTAssertEqual(readers.count, 3)
            XCTAssertEqual(Self.alive(readers), 3)

            player = nil
            leftOpen += Self.alive(readers)
            Self.assertDeletableAndRewritable(Self.urls(stems))
        }
        try await Task.sleep(for: .milliseconds(50))
        print("F7c F1 soltar alojado sonando: \(Self.dropRounds) pasadas, \(anchored) con ancla, \(leftOpen) lectores abiertos al volver")
        XCTAssertEqual(anchored, Self.dropRounds, "el render debe haber arrancado antes de soltar")
        XCTAssertEqual(leftOpen, 0, "lectores vivos tras soltar el reproductor")
        XCTAssertNil(s.playbackAnchor, "el motor cerrado ya no da ancla")
        XCTAssertTrue(s.isOpen)
    }

    // MARK: Cerrar la sesión con el reproductor vivo, y recargarlo

    /// `close()` suelta ya el render alojado (ancla nil al volver, antes seguía hasta que el `Task` desenganchaba). El
    /// reproductor vivo conserva su tema (como en el Mac: sus lectores siguen abiertos) y vuelve a su salida como antes.
    /// Al cargar otro tema los lectores viejos mueren al volver de `load` y sus ficheros se borran y reescriben; al
    /// soltar el reproductor, los nuevos.
    @MainActor
    func testClosingSessionReleasesHostedRendererAndReloadClosesOldStems() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let io = AudioSessionTests.rigIO(Self.fs)
        let s = AudioSessionTests.session(io, guitarIn: [1])
        try s.open()
        let stop = Self.startPumping(io)
        defer { stop.set(true) }

        let first = try Self.writeStems(in: dir, tag: "a")
        var player: PortableStudyPlayer? = PortableStudyPlayer(devices: SimulatedDeviceProvider(devices: [], defaultID: nil))
        try player!.load(tracks: first.tracks)
        try player!.setTake(first.take)
        try player!.attach(to: s)
        try player!.play()
        let anchored = try await Self.waitForAnchor(s)
        XCTAssertTrue(anchored)
        let old = Self.weakReaders(player!)
        XCTAssertEqual(old.count, 3)

        s.close()
        XCTAssertNil(s.playbackAnchor, "la sesión cerrada ya no retiene el render alojado")
        XCTAssertEqual(Self.alive(old), 3, "el reproductor vivo conserva su tema")
        for _ in 0..<200 where player!.isHosted { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(player!.isHosted, "vuelve a su propia salida al cerrarse la sesión, como antes")

        let second = try Self.writeStems(in: dir, tag: "b")
        try player!.load(tracks: second.tracks)
        let oldOpen = Self.alive(old)
        Self.assertDeletableAndRewritable(Self.urls(first))
        let fresh = Self.weakReaders(player!)
        XCTAssertEqual(fresh.count, 2)

        player = nil
        let freshOpen = Self.alive(fresh)
        Self.assertDeletableAndRewritable(second.tracks.map(\.url))
        print("F7c F1 cerrar sesión y recargar: ancla tras close \(s.playbackAnchor == nil ? "nil" : "viva"), lectores viejos abiertos tras load \(oldOpen), nuevos tras soltar \(freshOpen)")
        XCTAssertEqual(oldOpen, 0, "lectores del tema anterior vivos tras load")
        XCTAssertEqual(freshOpen, 0, "lectores vivos tras soltar el reproductor")
    }

    // MARK: Salida propia sonando

    /// Con salida propia sonando, el `AudioIO` retiene el motor en su cierre de render (WASAPI hasta que se pare). Al
    /// soltar el reproductor los lectores mueren igual al volver, y el render que sigue llegando no hace nada.
    @MainActor
    func testDroppingPlayerOnOwnOutputClosesStemsWhileIORetainsEngine() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let io = SimulatedAudioIO(sampleRate: Self.fs, inputs: [], latencySamples: 0, declaredLatencySamples: 0)
        let stems = try Self.writeStems(in: dir, tag: "own")
        var player: PortableStudyPlayer? = PortableStudyPlayer(devices: SimulatedDeviceProvider(devices: [], defaultID: nil),
                                                               outputIO: { _ in io })
        try player!.load(tracks: stems.tracks)
        try player!.setTake(stems.take)
        try player!.play()
        for _ in 0..<40 { io.pump() }
        XCTAssertNotNil(player!.playbackAnchor)
        let readers = Self.weakReaders(player!)
        XCTAssertEqual(Self.alive(readers), 3)

        player = nil
        let open = Self.alive(readers)
        Self.assertDeletableAndRewritable(Self.urls(stems))
        for _ in 0..<40 { io.pump() }
        print("F7c F1 soltar con salida propia sonando: \(open) lectores abiertos al volver")
        XCTAssertEqual(open, 0)
        io.stop()
    }
}
