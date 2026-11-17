import Compression
import Foundation
import XCTest
@testable import SourceKit

// Páginas y pistas SINTÉTICAS hechas a mano; nada de datos reales de Songsterr.

private func page(_ stateJSON: String, encoded: Bool) -> String {
    let body = encoded
        ? stateJSON.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        : stateJSON
    return "<html><head><script id=\"state\" type=\"application/json\">\(body)</script></head><body></body></html>"
}

// Misma estructura que el endpoint real /api/songs: array de objetos con songId, artist, title, tracks, isJunk…
private let searchJSON = """
[{"songId":101,"artistId":1,"artist":"Grupo A","title":"Tema Uno","hasChords":true,"hasPlayer":true,"tracks":[{"partId":0}],"defaultTrack":0,"isJunk":false},
 {"songId":102,"artistId":2,"artist":"Grupo B","title":"Tema Dos","tracks":[],"isJunk":false},
 {"songId":103,"artist":"Grupo C","title":"Basura","tracks":[],"isJunk":true},
 {"songId":101,"artist":"Grupo A","title":"Tema Uno","tracks":[],"isJunk":false}]
"""

private let songState = """
{"meta":{"current":{"songId":7,"revisionId":900,"artist":"Grupo A","title":"Tema Uno","image":"v0-1-abc_D",
 "tracks":[
  {"instrumentId":29,"instrument":"Overdriven Guitar","name":"Rítmica","partId":0,"tuning":[64,59,55,50,45,40],"isGuitar":true},
  {"instrumentId":33,"instrument":"Bass","name":"Bajo","partId":1,"tuning":[43,38,33,28],"isBassGuitar":true},
  {"instrumentId":1024,"instrument":"Drums","name":"Batería","partId":2,"isDrums":true}]}}}
"""

private struct StubLoader: SongsterrPageLoading {
    var pages: [String: String]
    func html(for url: URL) async throws -> String {
        guard let p = pages[url.absoluteString] else { throw SongsterrError.offline }
        return p
    }
}

private final class CountingHTTP: HTTPFetching, @unchecked Sendable {
    var script: [Result<Data, SourceError>]
    private(set) var urls: [URL] = []
    private(set) var headers: [[String: String]] = []
    init(_ script: [Result<Data, SourceError>]) { self.script = script }
    func data(from url: URL, headers: [String: String]) async throws -> Data {
        urls.append(url)
        self.headers.append(headers)
        guard !script.isEmpty else { throw SourceError.httpStatus(500) }
        return try script.removeFirst().get()
    }
}

final class SongsterrReaderTests: XCTestCase {
    func testSearchJSON() throws {
        let r = try SongsterrReader.parseSearch(json: Data(searchJSON.utf8))
        XCTAssertEqual(r, [SongsterrSearchResult(songId: 101, artist: "Grupo A", title: "Tema Uno"),
                           SongsterrSearchResult(songId: 102, artist: "Grupo B", title: "Tema Dos")])
    }

    func testSearchWithoutResultsOrUnknownFormat() {
        XCTAssertThrowsError(try SongsterrReader.parseSearch(json: Data("[]".utf8))) {
            XCTAssertEqual($0 as? SongsterrError, .noResults)
        }
        for bad in ["{}", "nope", #"[{"title":"x"}]"#] {
            XCTAssertThrowsError(try SongsterrReader.parseSearch(json: Data(bad.utf8)), bad) {
                guard case .unknownFormat = $0 as? SongsterrError else { return XCTFail("\($0)") }
            }
        }
    }

    func testSongWithSeveralTracks() throws {
        let s = try SongsterrReader.parseSong(html: page(songState, encoded: true))
        XCTAssertEqual(s.songId, 7)
        XCTAssertEqual(s.revisionId, 900)
        XCTAssertEqual(s.artist, "Grupo A")
        XCTAssertEqual(s.tracks.count, 3)
        XCTAssertEqual(s.tracks[0].name, "Rítmica")
        XCTAssertEqual(s.tracks[0].tuning, [64, 59, 55, 50, 45, 40])
        XCTAssertTrue(s.tracks[0].isGuitar)
        XCTAssertTrue(s.tracks[1].isBass)
        XCTAssertNil(s.tracks[2].tuning)
        XCTAssertTrue(s.tracks[2].isDrums)
        XCTAssertEqual(s.tracks[1].url.absoluteString, "https://dqsljvtekg760.cloudfront.net/7/900/v0-1-abc_D/1.json")
        XCTAssertTrue(s.tracks.allSatisfy { SongsterrReader.isValidTrackURL($0.url) })
    }

    func testScriptContentEntryPoint() throws {
        let encoded = songState.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let state = try SongsterrReader.stateJSON(fromScriptContent: "  \(encoded)\n")
        XCTAssertEqual(try SongsterrReader.parseSong(state: state).tracks.count, 3)
    }

    func testUnknownFormat() {
        let cases = ["<html></html>", page("not json", encoded: false), page("[1,2]", encoded: false),
                     page(#"{"meta":{"current":{"songId":1}}}"#, encoded: false),
                     page(#"{"meta":{"current":{"songId":1,"revisionId":2,"image":"../x","tracks":[{}]}}}"#, encoded: false),
                     page(#"{"other":{}}"#, encoded: false)]
        for html in cases {
            XCTAssertThrowsError(try SongsterrReader.parseSong(html: html), html) {
                guard case .unknownFormat = $0 as? SongsterrError else { return XCTFail("\($0)") }
            }
        }
    }

    func testHostValidation() throws {
        XCTAssertTrue(SongsterrReader.isSongsterrHost("songsterr.com"))
        XCTAssertTrue(SongsterrReader.isSongsterrHost("www.songsterr.com"))
        for bad in ["songsterr.com.evil.net", "evilsongsterr.com", "songsterr.com@evil.net", "notsongsterr.com", ""] {
            XCTAssertFalse(SongsterrReader.isSongsterrHost(bad), bad)
        }
        XCTAssertFalse(SongsterrReader.isCDNHost("dqsljvtekg760.cloudfront.net.evil.net"))
        XCTAssertFalse(SongsterrReader.isCDNHost("evil.cloudfront.net"))
        XCTAssertEqual(try SongsterrReader.songURL(from: " https://www.songsterr.com/a/wsa/x-tab-s50624 ").path,
                       "/a/wsa/x-tab-s50624")
        for bad in ["https://songsterr.com.evil.net/a/wsa/x-tab-s1", "http://www.songsterr.com/a/wsa/x-tab-s1",
                    "https://evil.net/?h=songsterr.com", "https://user@www.songsterr.com/a/wsa/x-tab-s1"] {
            XCTAssertThrowsError(try SongsterrReader.songURL(from: bad), bad) {
                XCTAssertEqual($0 as? SongsterrError, .invalidHost)
            }
        }
        XCTAssertThrowsError(try SongsterrReader.songURL(from: "https://www.songsterr.com/")) {
            guard case .unknownFormat = $0 as? SongsterrError else { return XCTFail("\($0)") }
        }
        XCTAssertNil(SongsterrReader.trackURL(songId: 1, revisionId: 2, image: "a", partId: 0, cdnHost: "evil.net"))
    }

    func testSearchAPIURL() {
        let u = SongsterrReader.searchAPIURL(artist: "Platero y Tú", title: "El roce")
        XCTAssertEqual(u?.host, "www.songsterr.com")
        XCTAssertEqual(u?.path, "/api/songs")
        let items = URLComponents(url: u!, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.first { $0.name == "pattern" }?.value, "Platero y Tú El roce")
        XCTAssertNil(SongsterrReader.searchAPIURL(artist: " ", title: ""))
    }
}

final class SongsterrClientTests: XCTestCase {
    private func client(http: CountingHTTP, pages: [String: String] = [:]) -> SongsterrClient {
        SongsterrClient(loader: StubLoader(pages: pages), fetcher: http, retryDelay: .milliseconds(1))
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("songsterr-tests-\(UUID().uuidString)")
    }

    private func song() throws -> SongsterrSong { try SongsterrReader.parseSong(html: page(songState, encoded: false)) }

    func testSearchAndSongViaLoader() async throws {
        let http = CountingHTTP([.success(Data(searchJSON.utf8))])
        let c = client(http: http, pages: ["https://www.songsterr.com/a/wsa/x-tab-s7": page(songState, encoded: true)])
        let r = try await c.search(artist: "A", title: "B")
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(http.urls.first?.path, "/api/songs")
        let s = try await c.song(link: "https://www.songsterr.com/a/wsa/x-tab-s7")
        XCTAssertEqual(s.tracks.count, 3)
        do { _ = try await c.song(link: "https://songsterr.com.evil.net/a/x-tab-s7"); XCTFail() } catch {
            XCTAssertEqual(error as? SongsterrError, .invalidHost)
        }
    }

    func testDownloadCachesAndSkipsExisting() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let http = CountingHTTP([.success(Data(#"{"measures":[]}"#.utf8)), .success(Data(#"{"measures":[1]}"#.utf8))])
        let c = client(http: http)
        let tracks = Array(try song().tracks.prefix(2))
        let files = try await c.downloadTracks(tracks, to: dir)
        XCTAssertEqual(Set(files.keys), [0, 1])
        XCTAssertEqual(http.urls.count, 2)
        XCTAssertNotNil(http.headers[0]["Accept-Language"])
        _ = try await c.downloadTracks(tracks, to: dir)
        XCTAssertEqual(http.urls.count, 2, "la segunda vez sale de la caché")
    }

    func testSingleRetryOn429ThenGivesUp() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tracks = [try song().tracks[0]]
        let http = CountingHTTP([.failure(.httpStatus(429)), .failure(.httpStatus(429)), .failure(.httpStatus(429))])
        do { _ = try await client(http: http).downloadTracks(tracks, to: dir); XCTFail() } catch {
            XCTAssertEqual(error as? SongsterrError, .rateLimited)
        }
        XCTAssertEqual(http.urls.count, 2, "un intento y un solo reintento")

        let ok = CountingHTTP([.failure(.httpStatus(429)), .success(Data("{}".utf8))])
        let files = try await client(http: ok).downloadTracks(tracks, to: dir)
        XCTAssertEqual(files.count, 1)
    }

    func testOfflineAndNotFoundAndBadJSON() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tracks = [try song().tracks[0]]
        let off = CountingHTTP([.failure(.offline), .failure(.offline)])
        do { _ = try await client(http: off).downloadTracks(tracks, to: dir); XCTFail() } catch {
            XCTAssertEqual(error as? SongsterrError, .offline)
        }
        let nf = CountingHTTP([.failure(.httpStatus(404))])
        do { _ = try await client(http: nf).downloadTracks(tracks, to: dir); XCTFail() } catch {
            XCTAssertEqual(error as? SongsterrError, .httpStatus(404))
        }
        XCTAssertEqual(nf.urls.count, 1, "404 no se reintenta")
        let bad = CountingHTTP([.success(Data("<html>".utf8))])
        do { _ = try await client(http: bad).downloadTracks(tracks, to: dir); XCTFail() } catch {
            guard case .unknownFormat = error as? SongsterrError else { return XCTFail("\(error)") }
        }
    }

    func testRejectsForeignTrackURL() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let t = SongsterrTrack(index: 0, partId: 0, name: "", instrument: "", instrumentId: 0, tuning: nil, isDrums: false,
                               isBass: false, isGuitar: true, url: URL(string: "https://evil.net/0.json")!)
        let http = CountingHTTP([])
        do { _ = try await client(http: http).downloadTracks([t], to: dir); XCTFail() } catch {
            XCTAssertEqual(error as? SongsterrError, .invalidHost)
        }
        XCTAssertTrue(http.urls.isEmpty)
    }

    func testGunzipWithoutContentEncoding() throws {
        let json = Data(#"{"measures":[1,2,3]}"#.utf8)
        let deflated = try (json as NSData).compressed(using: .zlib) as Data
        var gz = Data([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 3])
        gz.append(deflated)
        gz.append(Data(repeating: 0, count: 8))  // CRC32 + ISIZE (no se verifican)
        XCTAssertEqual(SongsterrClient.gunzipIfNeeded(gz), json)
        XCTAssertEqual(SongsterrClient.gunzipIfNeeded(json), json)
    }
}
