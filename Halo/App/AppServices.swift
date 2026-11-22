import SwiftUI

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
    let airDrop = AirDropService()
    let activities: ActivityCoordinator
    let updates = UpdateService()
    let lockScreen: LockScreenService

    private init() {
        lyrics = LyricsService(nowPlaying: nowPlaying)
        activities = ActivityCoordinator(nowPlaying: nowPlaying, lyrics: lyrics, battery: battery, bluetooth: bluetooth, menuBar: menuBar)
        let (nowPlaying, lyrics, weather, battery, bluetooth) = (nowPlaying, lyrics, weather, battery, bluetooth)
        lockScreen = LockScreenService {
            AnyView(LockScreenWidgetsView(nowPlaying: nowPlaying, lyrics: lyrics, weather: weather, battery: battery, bluetooth: bluetooth))
        }
    }

    func start() {
        nowPlaying.setEnabled(Preferences.nowPlayingEnabled)
        lyrics.setEnabled(Preferences.lyricsEnabled)
        battery.lowThreshold = Preferences.lowBatteryThreshold
        battery.criticalThreshold = Preferences.criticalBatteryThreshold
        bluetooth.setEnabled(Preferences.bluetoothAudioEnabled)
        weather.setEnabled(Preferences.weatherEnabled)
        airDrop.start()
        lockScreen.setEnabled(Preferences.lockScreenEnabled)
        activities.showsLowBatteryIndicator = Preferences.lowBatteryIndicator
        activities.mediaWingsMode = Preferences.mediaWingsMode
        updates.start()
    }
}
