//
//  SteamGridDBClient.swift
//  SteamShortcutConverter
//
//  REST client for https://www.steamgriddb.com/api/v2, with client-side rate
//  limiting (max 1 req/s) and a single retry on HTTP 429. URLSession/clock/sleep
//  are injected so tests never touch the real network or wall clock.
//

import Foundation

final class SteamGridDBClient: ArtworkProvider {

    enum ClientError: LocalizedError {
        case invalidResponse
        case httpError(Int)
        case apiFailure([String])

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid response from SteamGridDB."
            case .httpError(let code):
                return "SteamGridDB HTTP error \(code)."
            case .apiFailure(let errors):
                return "SteamGridDB error: \(errors.joined(separator: ", "))"
            }
        }
    }

    private struct Envelope<T: Codable>: Codable {
        let success: Bool
        let data: T?
        let errors: [String]?
    }

    private let apiKey: String
    private let session: URLSession
    private let baseURL: URL
    private let minInterval: TimeInterval
    private let now: () -> Date
    private let sleep: (TimeInterval) async -> Void

    private var lastRequestTime: Date?

    init(
        apiKey: String,
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://www.steamgriddb.com/api/v2")!,
        minInterval: TimeInterval = 1.0,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    ) {
        self.apiKey = apiKey
        self.session = session
        self.baseURL = baseURL
        self.minInterval = minInterval
        self.now = now
        self.sleep = sleep
    }

    // MARK: - ArtworkProvider

    func searchGame(term: String) async throws -> [SGDBGame] {
        let url = baseURL
            .appendingPathComponent("search")
            .appendingPathComponent("autocomplete")
            .appendingPathComponent(term)
        return try await getDecoded(url, as: [SGDBGame].self)
    }

    func getIcons(gameId: Int) async throws -> [SGDBImage] {
        let url = baseURL
            .appendingPathComponent("icons")
            .appendingPathComponent("game")
            .appendingPathComponent("\(gameId)")
        return try await getDecoded(url, as: [SGDBImage].self)
    }

    func getGrids(gameId: Int) async throws -> [SGDBImage] {
        let url = baseURL
            .appendingPathComponent("grids")
            .appendingPathComponent("game")
            .appendingPathComponent("\(gameId)")
        return try await getDecoded(url, as: [SGDBImage].self)
    }

    func downloadImage(url: URL) async throws -> Data {
        // Image CDN fetch — not throttled (throttle governs the API endpoints).
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard http.statusCode == 200 else { throw ClientError.httpError(http.statusCode) }
        return data
    }

    // MARK: - Request plumbing

    private func getDecoded<T: Codable>(_ url: URL, as type: T.Type) async throws -> T {
        let data = try await get(url)
        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        guard envelope.success, let value = envelope.data else {
            throw ClientError.apiFailure(envelope.errors ?? ["unknown"])
        }
        return value
    }

    private func get(_ url: URL) async throws -> Data {
        await throttle()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }

        if http.statusCode == 429 {
            let retryAfter = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? minInterval
            await sleep(retryAfter)
            await throttle()
            let (retryData, retryResponse) = try await session.data(for: request)
            guard let retryHTTP = retryResponse as? HTTPURLResponse else { throw ClientError.invalidResponse }
            guard retryHTTP.statusCode == 200 else { throw ClientError.httpError(retryHTTP.statusCode) }
            return retryData
        }

        guard http.statusCode == 200 else { throw ClientError.httpError(http.statusCode) }
        return data
    }

    /// Enforce a minimum spacing between API requests.
    private func throttle() async {
        if let last = lastRequestTime {
            let elapsed = now().timeIntervalSince(last)
            if elapsed < minInterval {
                await sleep(minInterval - elapsed)
            }
        }
        lastRequestTime = now()
    }
}
