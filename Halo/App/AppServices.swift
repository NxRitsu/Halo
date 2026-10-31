import Foundation

/// Long-lived services shared by the islands and the settings.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let nowPlaying = NowPlayingService()
    let activities: ActivityCoordinator

    private init() {
        activities = ActivityCoordinator(nowPlaying: nowPlaying)
    }

    func start() {
        nowPlaying.setEnabled(Preferences.nowPlayingEnabled)
    }
}
