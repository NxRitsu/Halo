import Foundation

/// Long-lived services shared by the islands and the settings.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let nowPlaying = NowPlayingService()
    let lyrics: LyricsService
    let activities: ActivityCoordinator

    private init() {
        lyrics = LyricsService(nowPlaying: nowPlaying)
        activities = ActivityCoordinator(nowPlaying: nowPlaying, lyrics: lyrics)
    }

    func start() {
        nowPlaying.setEnabled(Preferences.nowPlayingEnabled)
        lyrics.setEnabled(Preferences.lyricsEnabled)
    }
}
