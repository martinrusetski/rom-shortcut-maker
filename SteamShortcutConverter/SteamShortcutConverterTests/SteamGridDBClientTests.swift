//
//  SteamGridDBClientTests.swift
//  SteamShortcutConverterTests
//
//  Tests for SteamGridDBClient using a stubbed URLProtocol (no real network)
//  and injected clock/sleep (no real waiting).
//

import XCTest
@testable import SteamShortcutConverter

// MARK: - Mock URLProtocol

final class MockURLProtocol: URLProtocol {
    /// Returns (response, body) for a request, or throws to simulate failure.
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "MockURLProtocol", code: -1))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Sleep recorder

final class SleepRecorder {
    private(set) var durations: [TimeInterval] = []
    func record(_ duration: TimeInterval) { durations.append(duration) }
}

final class SteamGridDBClientTests: XCTestCase {

    var session: URLSession!
    var recorder: SleepRecorder!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        recorder = SleepRecorder()
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        session = nil
        recorder = nil
        super.tearDown()
    }

    private func makeClient(fixedNow: Date = Date(timeIntervalSince1970: 1000)) -> SteamGridDBClient {
        SteamGridDBClient(
            apiKey: "test-key",
            session: session,
            minInterval: 1.0,
            now: { fixedNow },
            sleep: { [recorder] seconds in recorder?.record(seconds) }
        )
    }

    private func response(_ url: URL, status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
    }

    private func envelope(_ jsonDataArray: String) -> Data {
        "{\"success\":true,\"data\":\(jsonDataArray)}".data(using: .utf8)!
    }

    // MARK: - Parsing

    func testSearchParsesCannedJSON() async throws {
        MockURLProtocol.handler = { request in
            let body = self.envelope("[{\"id\":42,\"name\":\"Chrono Trigger\"}]")
            return (self.response(request.url!, status: 200), body)
        }
        let games = try await makeClient().searchGame(term: "Chrono Trigger")
        XCTAssertEqual(games, [SGDBGame(id: 42, name: "Chrono Trigger")])
    }

    func testGetIconsParsesAndFiltersPNG() async throws {
        MockURLProtocol.handler = { request in
            let body = self.envelope("""
            [{"id":1,"url":"https://cdn.example/icon.png","thumb":null,"score":5,"mime":"image/png"},
             {"id":2,"url":"https://cdn.example/icon.jpg","thumb":null,"score":9,"mime":"image/jpeg"}]
            """)
            return (self.response(request.url!, status: 200), body)
        }
        let icons = try await makeClient().getIcons(gameId: 42)
        XCTAssertEqual(icons.count, 2)
        XCTAssertTrue(icons[0].isPNG)
        XCTAssertFalse(icons[1].isPNG)
    }

    // MARK: - Rate limiting

    func testRateLimitThrottleRespected() async throws {
        MockURLProtocol.handler = { request in
            (self.response(request.url!, status: 200), self.envelope("[]"))
        }
        let client = makeClient()
        _ = try await client.getIcons(gameId: 1)   // first: no throttle sleep
        _ = try await client.getIcons(gameId: 2)   // second: must wait ~minInterval
        XCTAssertEqual(recorder.durations, [1.0])
    }

    func test429RetriesOnceThenSucceeds() async throws {
        let calls = Box(0)
        MockURLProtocol.handler = { request in
            calls.value += 1
            if calls.value == 1 {
                return (self.response(request.url!, status: 429, headers: ["Retry-After": "2"]), Data())
            }
            return (self.response(request.url!, status: 200), self.envelope("[{\"id\":7,\"name\":\"X\"}]"))
        }
        let games = try await makeClient().searchGame(term: "X")
        XCTAssertEqual(games.first?.id, 7)
        XCTAssertTrue(recorder.durations.contains(2.0))   // Retry-After honored
        XCTAssertEqual(calls.value, 2)                    // exactly one retry
    }

    func testNon200SurfacesError() async throws {
        MockURLProtocol.handler = { request in
            (self.response(request.url!, status: 500), Data())
        }
        do {
            _ = try await makeClient().searchGame(term: "X")
            XCTFail("expected error")
        } catch {
            // expected
        }
    }

    // MARK: - Selection strategy

    func testFetchArtworkPrefersIcon() async throws {
        MockURLProtocol.handler = { request in
            let path = request.url!.path
            let body: Data
            if path.contains("autocomplete") {
                body = self.envelope("[{\"id\":5,\"name\":\"Game\"}]")
            } else if path.contains("/icons/") {
                body = self.envelope("[{\"id\":7,\"url\":\"https://cdn.example/icon.png\",\"thumb\":null,\"score\":10,\"mime\":\"image/png\"}]")
            } else if path.contains("/grids/") {
                body = self.envelope("[]")
            } else {
                return (self.response(request.url!, status: 200), Data([0x89, 0x50, 0x4E, 0x47]))
            }
            return (self.response(request.url!, status: 200), body)
        }
        let result = try await makeClient().fetchArtwork(forTitle: "Game")
        XCTAssertEqual(result?.sourceType, .icon)
        XCTAssertEqual(result?.sgdbImageId, 7)
    }

    func testFetchArtworkFallsBackToGrid() async throws {
        MockURLProtocol.handler = { request in
            let path = request.url!.path
            let body: Data
            if path.contains("autocomplete") {
                body = self.envelope("[{\"id\":5,\"name\":\"Game\"}]")
            } else if path.contains("/icons/") {
                body = self.envelope("[]")   // no icons -> fall back
            } else if path.contains("/grids/") {
                body = self.envelope("[{\"id\":9,\"url\":\"https://cdn.example/grid.png\",\"thumb\":null,\"score\":3,\"mime\":\"image/png\"}]")
            } else {
                return (self.response(request.url!, status: 200), Data([0x89, 0x50, 0x4E, 0x47]))
            }
            return (self.response(request.url!, status: 200), body)
        }
        let result = try await makeClient().fetchArtwork(forTitle: "Game")
        XCTAssertEqual(result?.sourceType, .grid)
        XCTAssertEqual(result?.sgdbImageId, 9)
        XCTAssertEqual(result?.data, Data([0x89, 0x50, 0x4E, 0x47]))
    }
}

/// Reference box for mutable state captured by escaping closures.
final class Box<T> {
    var value: T
    init(_ value: T) { self.value = value }
}
