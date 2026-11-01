import Foundation

/// What LRCLIB knows about a track.
enum LyricsLookupResult: Equatable, Sendable {
    case synced(String)
    case instrumental
    case notFound
}

/// Minimal client for the LRCLIB API (https://lrclib.net/docs).
///
/// Only the track title, artist, album and duration are sent. Requests identify Halo with a
/// User-Agent that links to the repository, as LRCLIB asks.
struct LRCLIBClient: Sendable {
    struct ServiceError: Error {
        let description: String
    }

    struct Query: Equatable, Sendable {
        var title: String
        var artist: String
        var album: String
        var duration: TimeInterval?
    }

    private struct Record: Decodable {
        var duration: Double?
        var instrumental: Bool?
        var syncedLyrics: String?
    }

    private static let baseURL = URL(string: "https://lrclib.net/api/")!
    /// Largest difference between the track and a search result for them to be considered the same recording.
    private static let durationTolerance: TimeInterval = 3

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpCookieStorage = nil
        // Results are cached on disk by `LyricsCache`.
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = [
            "User-Agent": "\(AppInfo.name)/\(AppInfo.version) (\(AppInfo.repositoryURL.absoluteString))",
        ]
        return URLSession(configuration: configuration)
    }()

    /// Looks up the exact track first, then falls back to a search.
    /// Throws `ServiceError` when the service is unreachable or overloaded.
    func lookUp(_ query: Query) async throws -> LyricsLookupResult {
        if let record: Record = try await request("get", query: query, includeAlbumAndDuration: true) {
            if record.instrumental == true { return .instrumental }
            if let lyrics = record.syncedLyrics, !lyrics.isEmpty { return .synced(lyrics) }
        }

        let records: [Record] = try await request("search", query: query, includeAlbumAndDuration: false) ?? []
        let candidates = records.filter { record in
            guard let duration = query.duration else { return true }
            return record.duration.map { abs($0 - duration) <= Self.durationTolerance } ?? false
        }
        if let lyrics = candidates.lazy.compactMap(\.syncedLyrics).first(where: { !$0.isEmpty }) {
            return .synced(lyrics)
        }
        return candidates.contains { $0.instrumental == true } ? .instrumental : .notFound
    }

    /// Returns nil when LRCLIB has no match.
    private func request<Response: Decodable>(
        _ endpoint: String, query: Query, includeAlbumAndDuration: Bool
    ) async throws -> Response? {
        var components = URLComponents(url: Self.baseURL.appending(path: endpoint), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "track_name", value: query.title),
            URLQueryItem(name: "artist_name", value: query.artist),
        ]
        if includeAlbumAndDuration {
            if !query.album.isEmpty {
                items.append(URLQueryItem(name: "album_name", value: query.album))
            }
            if let duration = query.duration {
                items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
            }
        }
        components.queryItems = items

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: components.url!)
        } catch {
            throw ServiceError(description: error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            do {
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                throw ServiceError(description: "Unexpected response")
            }
        case 429, 500...:
            throw ServiceError(description: "HTTP \(status)")
        default:
            // 404 (no match) or 400 (query rejected): nothing to retry.
            return nil
        }
    }
}
