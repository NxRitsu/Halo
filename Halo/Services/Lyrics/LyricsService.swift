import Foundation
import OSLog

/// Finds synced lyrics for the track that is playing, from the disk cache or from LRCLIB.
///
/// One lookup per track at most: results (including "no lyrics") are cached on disk. When LRCLIB
/// is unreachable or overloaded, requests stop for an exponentially growing delay (30 s up to 1 h).
///
/// LRCLIB answers "503 ServerOverloaded" when a lookup finds nothing, so a single 503 is taken
/// as "no lyrics" (cached for a day only). Several in a row, for different tracks, are taken as
/// a real overload.
@MainActor
@Observable
final class LyricsService {
    enum Status: Equatable {
        case disabled
        /// Nothing is playing.
        case idle
        case searching
        case found
        case instrumental
        case notFound
        case unavailable(retryAt: Date)
    }

    private(set) var status = Status.disabled
    /// Lyrics of the current track, when it has synced lyrics.
    private(set) var lyrics: SyncedLyrics?

    /// Waits for the track to settle before querying the network, so skipping through tracks doesn't send a burst of requests.
    private static let requestDelay: Duration = .milliseconds(600)
    private static let initialRetryDelay: TimeInterval = 30
    private static let maximumRetryDelay: TimeInterval = 3600
    private static let busyLifetime: TimeInterval = 24 * 3600
    private static let busyResponsesBeforeBackoff = 3

    @ObservationIgnored private let nowPlaying: NowPlayingService
    @ObservationIgnored private let client = LRCLIBClient()
    @ObservationIgnored private let cache = LyricsCache()
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Halo", category: "Lyrics")
    @ObservationIgnored private var isEnabled = false
    @ObservationIgnored private var currentQuery: LRCLIBClient.Query?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var failureCount = 0
    @ObservationIgnored private var consecutiveBusyResponses = 0
    @ObservationIgnored private var retryDate: Date?

    init(nowPlaying: NowPlayingService) {
        self.nowPlaying = nowPlaying
        observeTrack()
    }

    #if DEBUG
    /// Shows made-up lyrics, for the images of the README.
    func showSample(_ lyrics: SyncedLyrics?) {
        self.lyrics = lyrics
    }
    #endif

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        reset()
        status = enabled ? .idle : .disabled
        trackChanged()
    }

    func clearCache() {
        cache.removeAll()
    }

    // MARK: - Track changes

    private func observeTrack() {
        withObservationTracking {
            _ = nowPlaying.track
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.trackChanged()
                self.observeTrack()
            }
        }
    }

    private func trackChanged() {
        let query = isEnabled ? nowPlaying.track.flatMap(Self.query(for:)) : nil
        guard query != currentQuery else { return }
        reset()
        currentQuery = query
        if let query {
            load(query)
        } else {
            status = isEnabled ? .idle : .disabled
        }
    }

    private func reset() {
        loadTask?.cancel()
        loadTask = nil
        currentQuery = nil
        lyrics = nil
    }

    private static func query(for track: NowPlayingTrack) -> LRCLIBClient.Query? {
        let title = track.title.trimmingCharacters(in: .whitespaces)
        let artist = track.artist.trimmingCharacters(in: .whitespaces)
        // LRCLIB needs both; web videos often have no artist.
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        return LRCLIBClient.Query(
            title: title,
            artist: artist,
            album: track.album.trimmingCharacters(in: .whitespaces),
            duration: track.duration
        )
    }

    // MARK: - Loading

    private func load(_ query: LRCLIBClient.Query) {
        if let cached = cache.result(for: query) {
            apply(cached)
            return
        }

        if let retryDate, retryDate > .now {
            // The service failed recently: wait before trying again.
            status = .unavailable(retryAt: retryDate)
            loadTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(retryDate.timeIntervalSinceNow))
                guard let self, !Task.isCancelled, self.currentQuery == query else { return }
                self.load(query)
            }
            return
        }

        status = .searching
        loadTask = Task { [weak self, client] in
            try? await Task.sleep(for: Self.requestDelay)
            guard !Task.isCancelled else { return }
            do {
                let result = try await client.lookUp(query)
                guard let self else { return }
                self.failureCount = 0
                self.consecutiveBusyResponses = 0
                self.retryDate = nil
                self.cache.store(result, for: query)
                if self.currentQuery == query {
                    self.apply(result)
                }
            } catch LRCLIBClient.ServiceError.busy {
                guard let self, !Task.isCancelled else { return }
                self.consecutiveBusyResponses += 1
                if self.consecutiveBusyResponses < Self.busyResponsesBeforeBackoff {
                    self.cache.store(.notFound, for: query, lifetime: Self.busyLifetime)
                    if self.currentQuery == query {
                        self.apply(.notFound)
                    }
                } else if self.currentQuery == query {
                    self.requestFailed(query, error: LRCLIBClient.ServiceError.busy)
                }
            } catch {
                guard let self, !Task.isCancelled, self.currentQuery == query else { return }
                self.requestFailed(query, error: error)
            }
        }
    }

    private func requestFailed(_ query: LRCLIBClient.Query, error: Error) {
        failureCount += 1
        let delay = min(Self.initialRetryDelay * pow(2, Double(failureCount - 1)), Self.maximumRetryDelay)
        retryDate = Date.now.addingTimeInterval(delay)
        logger.error("LRCLIB request failed (\(String(describing: error), privacy: .public)), retrying in \(Int(delay)) s")
        load(query)
    }

    private func apply(_ result: LyricsLookupResult) {
        switch result {
        case .synced(let text):
            lyrics = SyncedLyrics(lrc: text)
            status = lyrics != nil ? .found : .notFound
        case .instrumental:
            lyrics = nil
            status = .instrumental
        case .notFound:
            lyrics = nil
            status = .notFound
        }
    }
}
