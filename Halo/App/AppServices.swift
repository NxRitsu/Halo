import Foundation

/// Long-lived services shared by the islands and the settings.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let nowPlaying = NowPlayingService()
    let lyrics: LyricsService
    let battery = BatteryService()
    let activities: ActivityCoordinator

    private init() {
        lyrics = LyricsService(nowPlaying: nowPlaying)
        activities = ActivityCoordinator(nowPlaying: nowPlaying, lyrics: lyrics, battery: battery)
    }

    func start() {
        nowPlaying.setEnabled(Preferences.nowPlayingEnabled)
        lyrics.setEnabled(Preferences.lyricsEnabled)
        battery.lowThreshold = Preferences.lowBatteryThreshold
        battery.criticalThreshold = Preferences.criticalBatteryThreshold
        activities.showsLowBatteryIndicator = Preferences.lowBatteryIndicator
        activities.showsMediaWings = Preferences.mediaWingsEnabled
    }
}
