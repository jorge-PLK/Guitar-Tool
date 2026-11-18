import XCTest
@testable import SourceKit

private final class Router: HTTPSending, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    var artistJSON: String
    init(artistJSON: String) { self.artistJSON = artistJSON }
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return _requests }
    var all: Int { requests.count }
    var artistSearches: Int { requests.filter { $0.url?.host == "api.spotify.com" }.count }
    var imageFetches: Int { requests.filter { $0.url?.host == "img.test" }.count }
    private func record(_ request: URLRequest) -> String {
        lock.lock(); defer { lock.unlock() }
        _requests.append(request)
        return artistJSON
    }
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let json = record(request)
        switch request.url?.host {
        case "accounts.spotify.com":
            return HTTPResponse(status: 200, data: Data(#"{"access_token":"T","expires_in":3600}"#.utf8))
        case "api.spotify.com": return HTTPResponse(status: 200, data: Data(json.utf8))
        default: return HTTPResponse(status: 200, data: Data([1, 2, 3]))
        }
    }
}

private final class Clock: @unchecked Sendable { var date = Date(timeIntervalSince1970: 2_000_000) }

private func json(_ artists: [(String, [Int])]) -> String {
    let items = artists.map { name, widths in
        let imgs = widths.map { #"{"url":"https://img.test/\#($0).jpg","width":\#($0),"height":\#($0)}"# }.joined(separator: ",")
        return #"{"name":"\#(name)","images":[\#(imgs)]}"#
    }.joined(separator: ",")
    return #"{"artists":{"items":[\#(items)]}}"#
}

final class ArtistPhotoTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("artists-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func service(_ router: Router, clock: Clock = Clock(), creds: SpotifyCredentials? = SpotifyCredentials(clientID: "fake-id", clientSecret: "fake-secret")) -> ArtistPhotoService {
        let tokens = SpotifyTokenProvider(credentials: { creds }, http: router, now: { clock.date })
        return ArtistPhotoService(client: SpotifySearchClient(tokens: tokens, http: router), http: router,
                                  directory: dir, now: { clock.date })
    }

    func testExactMatchOverOtherResults() throws {
        let data = Data(json([("Metallica Tribute", [640, 300]), ("metállica ", [640, 320, 160]), ("Metallica", [999])]).utf8)
        XCTAssertEqual(try ArtistImagePicker.pick(from: data, artist: "Metallica")?.absoluteString, "https://img.test/160.jpg")
        XCTAssertNil(try ArtistImagePicker.pick(from: data, artist: "Metal"))
    }

    func testImageSizeChoice() throws {
        let a = Data(json([("X", [640, 300, 64, 200])]).utf8)
        XCTAssertEqual(try ArtistImagePicker.pick(from: a, artist: "X")?.absoluteString, "https://img.test/200.jpg")
        let small = Data(json([("X", [64, 100])]).utf8)
        XCTAssertEqual(try ArtistImagePicker.pick(from: small, artist: "x")?.absoluteString, "https://img.test/100.jpg")
        XCTAssertNil(try ArtistImagePicker.pick(from: Data(json([("X", [])]).utf8), artist: "X"))
        XCTAssertThrowsError(try ArtistImagePicker.pick(from: Data("{}".utf8), artist: "X"))
    }

    func testQueryIsEncoded() {
        XCTAssertEqual(ArtistImagePicker.searchURL("AC/DC").absoluteString,
                       "https://api.spotify.com/v1/search?type=artist&limit=5&q=AC%2FDC")
    }

    func testCacheDoesNotRepeatRequest() async {
        let router = Router(artistJSON: json([("Metallica", [320])]))
        let s = service(router)
        let first = await s.photo(for: "Metallica")
        XCTAssertNotNil(first)
        XCTAssertEqual(router.artistSearches, 1)
        let again = await s.photo(for: " metállica")
        XCTAssertEqual(again, first)
        XCTAssertEqual(router.artistSearches, 1)
        // Un servicio nuevo (otro arranque) también la encuentra en disco.
        let other = service(router)
        let cached = await other.photo(for: "METALLICA")
        XCTAssertEqual(cached, first)
        XCTAssertEqual(router.artistSearches, 1)
        XCTAssertEqual(router.imageFetches, 1)
    }

    func testNegativeExpiresAfterSevenDays() async {
        let router = Router(artistJSON: json([("Otro", [320])]))
        let clock = Clock()
        let s = service(router, clock: clock)
        var r = await s.photo(for: "Nadie")
        XCTAssertNil(r)
        XCTAssertEqual(router.artistSearches, 1)
        clock.date.addTimeInterval(7 * 24 * 3600 - 60)
        r = await service(router, clock: clock).photo(for: "Nadie")
        XCTAssertNil(r)
        XCTAssertEqual(router.artistSearches, 1)
        clock.date.addTimeInterval(120)
        r = await service(router, clock: clock).photo(for: "Nadie")
        XCTAssertNil(r)
        XCTAssertEqual(router.artistSearches, 2)
    }

    func testNoCredentialsNoRequest() async {
        let router = Router(artistJSON: json([("A", [320])]))
        let s = service(router, creds: nil)
        let r = await s.photo(for: "A")
        XCTAssertNil(r)
        XCTAssertEqual(router.all, 0)
        // Un fallo no deja negativa en disco: se reintenta en el siguiente arranque.
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testNetworkFailureIsNotRecordedAsMiss() async {
        struct Down: HTTPSending { func send(_ r: URLRequest) async throws -> HTTPResponse { throw SourceError.offline } }
        let tokens = SpotifyTokenProvider(credentials: { SpotifyCredentials(clientID: "a", clientSecret: "b") }, http: Down())
        let s = ArtistPhotoService(client: SpotifySearchClient(tokens: tokens, http: Down()), http: Down(), directory: dir)
        let r = await s.photo(for: "A")
        XCTAssertNil(r)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testFileNameIsStable() {
        XCTAssertEqual(ArtistPhotoService.fileStem("Metallica"), ArtistPhotoService.fileStem("  metállica"))
        XCTAssertNotEqual(ArtistPhotoService.fileStem("AC/DC"), ArtistPhotoService.fileStem("AC DC"))
        XCTAssertFalse(ArtistPhotoService.fileStem("AC/DC").contains("/"))
    }
}
