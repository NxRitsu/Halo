import Foundation

/// Long-lived services shared by the islands and the settings.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let nowPlaying = NowPlayingService()
    let lyrics: LyricsService
    let battery = BatteryService()
    let bluetooth = BluetoothAudioService()
    let menuBar = MenuBarSpaceMonitor()
    let weather = WeatherService()
    let activities: ActivityCoordinator
    let updates = UpdateService()

    private init() {
        lyrics = LyricsService(nowPlaying: nowPlaying)
        activities = ActivityCoordinator(nowPlaying: nowPlaying, lyrics: lyrics, battery: battery, bluetooth: bluetooth, menuBar: menuBar)
    }

    func start() {
        nowPlaying.setEnabled(Preferences.nowPlayingEnabled)
        lyrics.setEnabled(Preferences.lyricsEnabled)
        battery.lowThreshold = Preferences.lowBatteryThreshold
        battery.criticalThreshold = Preferences.criticalBatteryThreshold
        bluetooth.setEnabled(Preferences.bluetoothAudioEnabled)
        weather.setEnabled(Preferences.weatherEnabled)
        activities.showsLowBatteryIndicator = Preferences.lowBatteryIndicator
        activities.mediaWingsMode = Preferences.mediaWingsMode
        updates.start()
    }
}
