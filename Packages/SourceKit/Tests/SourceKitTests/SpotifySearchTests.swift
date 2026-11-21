import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import SourceKit

private final class ScriptedSender: HTTPSending, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [Result<HTTPResponse, Error>]
    private var _requests: [URLRequest] = []
    init(_ script: [Result<HTTPResponse, Error>]) { self.script = script }
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return _requests }
    var tokenRequests: Int { requests.filter { $0.url?.host == "accounts.spotify.com" }.count }
    var searchRequests: Int { requests.filter { $0.url?.host == "api.spotify.com" }.count }
    func send(_ request: URLRequest) async throws -> HTTPResponse { try next(request) }
    private func next(_ request: URLRequest) throws -> HTTPResponse {
        lock.lock(); defer { lock.unlock() }
        _requests.append(request)
        guard !script.isEmpty else { return HTTPResponse(status: 500) }
        return try script.removeFirst().get()
    }
}

private final class Clock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_000_000)
}

private let fakeCreds = SpotifyCredentials(clientID: "fake-id-123", clientSecret: "fake-secret-XYZ")

private func tokenResponse(_ t: String, expires: Int = 3600) -> Result<HTTPResponse, Error> {
    .success(HTTPResponse(status: 200, data: Data(#"{"access_token":"\#(t)","token_type":"Bearer","expires_in":\#(expires)}"#.utf8)))
}
private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)))
}
private func ok() throws -> Result<HTTPResponse, Error> { .success(HTTPResponse(status: 200, data: try fixture("spotify_search.json"))) }
private func status(_ s: Int, _ headers: [String: String] = [:]) -> Result<HTTPResponse, Error> {
    .success(HTTPResponse(status: s, headers: headers, data: Data("cuerpo con fake-secret-XYZ".utf8)))
}

final class ImportQueryTests: XCTestCase {
    func testLinks() {
        XCTAssertEqual(ImportQuery.classify("https://www.youtube.com/watch?v=dQw4w9WgXcQ"), .link("https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        XCTAssertEqual(ImportQuery.classify("  https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC "), .link("https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"))
        XCTAssertEqual(ImportQuery.classify("open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"), .link("https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"))
        XCTAssertEqual(ImportQuery.classify("youtu.be/dQw4w9WgXcQ"), .link("https://youtu.be/dQw4w9WgXcQ"))
        XCTAssertEqual(ImportQuery.classify("www.example.com"), .link("https://www.example.com"))
        XCTAssertEqual(ImportQuery.classify("spotify:track:4uLU6hMCjMI75M1A2tKUQC"), .link("spotify:track:4uLU6hMCjMI75M1A2tKUQC"))
    }
    func testSearches() {
        XCTAssertEqual(ImportQuery.classify("metallica one"), .search("metallica one"))
        XCTAssertEqual(ImportQuery.classify("AC/DC T.N.T."), .search("AC/DC T.N.T."))
        XCTAssertEqual(ImportQuery.classify("https://"), .search("https://"))
        XCTAssertEqual(ImportQuery.classify("www.youtube.com es un sitio"), .search("www.youtube.com es un sitio"))
    }
    func testEmpty() {
        XCTAssertEqual(ImportQuery.classify(""), .empty)
        XCTAssertEqual(ImportQuery.classify("  \n "), .empty)
    }
}

final class DotEnvTests: XCTestCase {
    func testParse() {
        let text = """
        # comentario
        SPOTIFY_CLIENT_ID = abc

        export SPOTIFY_CLIENT_SECRET="se cret"
        QUOTED='x y'
        sin igual
        =vacia
        EMPTY=
        URL=a=b
        """
        let d = DotEnv.parse(text)
        XCTAssertEqual(d["SPOTIFY_CLIENT_ID"], "abc")
        XCTAssertEqual(d["SPOTIFY_CLIENT_SECRET"], "se cret")
        XCTAssertEqual(d["QUOTED"], "x y")
        XCTAssertEqual(d["EMPTY"], "")
        XCTAssertEqual(d["URL"], "a=b")
        XCTAssertNil(d["sin igual"])
        XCTAssertEqual(d.count, 5)
    }
}

final class SpotifyCredentialsTests: XCTestCase {
    private func dir(_ env: String?) throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        if let env { try env.write(to: d.appendingPathComponent(".env"), atomically: true, encoding: .utf8) }
        return d
    }
    func testPrecedence() throws {
        let support = try dir("SPOTIFY_CLIENT_ID=file-id\nSPOTIFY_CLIENT_SECRET=file-secret")
        let fallback = try dir("SPOTIFY_CLIENT_ID=def-id\nSPOTIFY_CLIENT_SECRET=def-secret")
        // fichero del support dir manda sobre el por defecto
        XCTAssertEqual(SpotifyCredentials.load(supportDir: support, defaultSupportDir: fallback, environment: [:]),
                       SpotifyCredentials(clientID: "file-id", clientSecret: "file-secret"))
        // entorno variable a variable
        XCTAssertEqual(SpotifyCredentials.load(supportDir: support, defaultSupportDir: fallback,
                                               environment: ["SPOTIFY_CLIENT_ID": "env-id"]),
                       SpotifyCredentials(clientID: "env-id", clientSecret: "file-secret"))
    }
    func testFallbackWhenSupportFileMissing() throws {
        let support = try dir(nil)
        let fallback = try dir("SPOTIFY_CLIENT_ID=def-id\nSPOTIFY_CLIENT_SECRET=def-secret")
        XCTAssertEqual(SpotifyCredentials.load(supportDir: support, defaultSupportDir: fallback, environment: [:]),
                       SpotifyCredentials(clientID: "def-id", clientSecret: "def-secret"))
    }
    func testMissing() throws {
        let none = try dir(nil)
        XCTAssertNil(SpotifyCredentials.load(supportDir: none, defaultSupportDir: none, environment: [:]))
        XCTAssertNil(SpotifyCredentials.load(supportDir: none, defaultSupportDir: none,
                                             environment: ["SPOTIFY_CLIENT_ID": "x"]))
    }
    func testDescriptionHidesSecret() {
        XCTAssertFalse("\(fakeCreds)".contains("fake-secret-XYZ"))
    }
}

final class SpotifySearchClientTests: XCTestCase {
    private func make(_ script: [Result<HTTPResponse, Error>], clock: Clock = Clock(),
                      creds: SpotifyCredentials? = fakeCreds) -> (SpotifySearchClient, ScriptedSender, SpotifyTokenProvider) {
        let sender = ScriptedSender(script)
        let provider = SpotifyTokenProvider(credentials: { creds }, http: sender, now: { clock.date })
        return (SpotifySearchClient(tokens: provider, http: sender), sender, provider)
    }

    func testTokenRequestShape() async throws {
        let (client, sender, _) = make([tokenResponse("T1"), try ok()])
        _ = try await client.search("x")
        let t = sender.requests[0]
        XCTAssertEqual(t.httpMethod, "POST")
        XCTAssertEqual(String(data: t.httpBody ?? Data(), encoding: .utf8), "grant_type=client_credentials")
        let basic = Data("fake-id-123:fake-secret-XYZ".utf8).base64EncodedString()
        XCTAssertEqual(t.value(forHTTPHeaderField: "Authorization"), "Basic \(basic)")
        XCTAssertEqual(sender.requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer T1")
    }

    func testTokenReusedThenRenewedAfterExpiry() async throws {
        let clock = Clock()
        let (client, sender, _) = make([tokenResponse("T1", expires: 3600), try ok(), try ok(), tokenResponse("T2"), try ok()], clock: clock)
        _ = try await client.search("a")
        clock.date += 3500  // dentro de expires_in - 60
        _ = try await client.search("b")
        XCTAssertEqual(sender.tokenRequests, 1)
        clock.date += 100   // pasa de 3540
        _ = try await client.search("c")
        XCTAssertEqual(sender.tokenRequests, 2)
        XCTAssertEqual(sender.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer T2")
    }

    func test401RenewsOnceAndRetries() async throws {
        let (client, sender, _) = make([tokenResponse("T1"), status(401), tokenResponse("T2"), try ok()])
        let r = try await client.search("x")
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(sender.tokenRequests, 2)
        XCTAssertEqual(sender.searchRequests, 2)
    }

    func test401TwiceIsRejected() async throws {
        let (client, sender, _) = make([tokenResponse("T1"), status(401), tokenResponse("T2"), status(401)])
        do { _ = try await client.search("x"); XCTFail() } catch {
            XCTAssertEqual(error as? SpotifySearchError, .rejected(401))
            XCTAssertFalse(error.localizedDescription.contains("fake-secret-XYZ"))
        }
        XCTAssertEqual(sender.searchRequests, 2)
    }

    func test403NoRetry() async throws {
        let (client, sender, _) = make([tokenResponse("T1"), status(403)])
        do { _ = try await client.search("x"); XCTFail() } catch {
            XCTAssertEqual(error as? SpotifySearchError, .rejected(403))
        }
        XCTAssertEqual(sender.searchRequests, 1)
    }

    func test429RetryAfter() async throws {
        let (client, _, _) = make([tokenResponse("T1"), status(429, ["Retry-After": "7"])])
        do { _ = try await client.search("x"); XCTFail() } catch {
            XCTAssertEqual(error as? SpotifySearchError, .rateLimited(retryAfter: 7))
            XCTAssertEqual(error.localizedDescription, "Spotify pide esperar 7 s")
        }
    }

    func testMissingCredentialsAndRereadAfterRejection() async throws {
        let (noKey, sender, _) = make([], creds: nil)
        do { _ = try await noKey.search("x"); XCTFail() } catch {
            XCTAssertEqual(error as? SpotifySearchError, .missingCredentials)
        }
        XCTAssertTrue(sender.requests.isEmpty)
        // rechazo del token: la próxima búsqueda vuelve a cargar la clave
        final class Box: @unchecked Sendable { var calls = 0 }
        let box = Box()
        let s = ScriptedSender([status(401), tokenResponse("T"), try ok()])
        let provider = SpotifyTokenProvider(credentials: { box.calls += 1; return fakeCreds }, http: s)
        let client = SpotifySearchClient(tokens: provider, http: s)
        do { _ = try await client.search("x"); XCTFail() } catch {
            XCTAssertEqual(error as? SpotifySearchError, .rejected(401))
        }
        _ = try await client.search("x")
        XCTAssertEqual(box.calls, 2)
    }

    func testNetworkError() async throws {
        let (client, _, _) = make([.failure(SourceError.offline)])
        do { _ = try await client.search("x"); XCTFail() } catch {
            XCTAssertEqual(error as? SpotifySearchError, .network)
        }
    }

    func testParseFixture() async throws {
        let (client, _, _) = make([tokenResponse("T1"), try ok()])
        let r = try await client.search("one")
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0].id, "4uLU6hMCjMI75M1A2tKUQC")
        XCTAssertEqual(r[0].artists, ["Metallica", "Invitado"])
        XCTAssertEqual(r[0].artistsText, "Metallica, Invitado")
        XCTAssertEqual(r[0].album, "...And Justice for All")
        XCTAssertEqual(r[0].year, 1988)
        XCTAssertEqual(r[0].durationText, "7:27")
        XCTAssertEqual(r[0].imageURL?.absoluteString, "https://img/64.jpg")
        XCTAssertEqual(r[1].year, 1999)
        XCTAssertNil(r[1].imageURL)
        XCTAssertEqual(r[0].appURL.absoluteString, "spotify:track:4uLU6hMCjMI75M1A2tKUQC")
    }

    func testBadResponse() async throws {
        let (client, _, _) = make([tokenResponse("T1"), .success(HTTPResponse(status: 200, data: Data("{}".utf8)))])
        do { _ = try await client.search("x"); XCTFail() } catch {
            XCTAssertEqual(error as? SpotifySearchError, .badResponse)
        }
    }

    func testQueryIsEncoded() {
        let url = SpotifySearchClient.searchURL("AC/DC & Co+ canción")
        XCTAssertEqual(url.absoluteString,
            "https://api.spotify.com/v1/search?type=track&limit=10&q=AC%2FDC%20%26%20Co%2B%20canci%C3%B3n")
    }

    func testErrorMessagesHaveNoSecret() {
        for e in [SpotifySearchError.missingCredentials, .rejected(401), .rateLimited(retryAfter: 3), .network, .badResponse] {
            XCTAssertFalse((e.errorDescription ?? "").contains("fake-secret-XYZ"))
        }
        XCTAssertEqual(SpotifySearchError.missingCredentials.errorDescription, "Búsqueda en Spotify no disponible: falta la clave (.env)")
        XCTAssertEqual(SpotifySearchError.network.errorDescription, "Sin conexión con Spotify")
    }
}
