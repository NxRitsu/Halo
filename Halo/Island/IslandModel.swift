import Foundation

/// Files dragged over the island, which it offers to send with AirDrop.
enum IslandDrop: Equatable {
    case ready(fileCount: Int)
    /// This Mac can't send them: the drop is refused.
    case unavailable
}

/// Observable state of one island, shared between its window controller and its SwiftUI view.
@MainActor
@Observable
final class IslandModel {
    var metrics: IslandMetrics
    var isExpanded = false
    var content: IslandContent
    /// Files dragged over the island. They take the place of any other content.
    var drop: IslandDrop?
    let nowPlaying: NowPlayingService
    let lyrics: LyricsService
    let battery: BatteryService
    let bluetooth: BluetoothAudioService
    let weather: WeatherService
    let airDrop: AirDropService

    /// Called when the user clicks the island.
    var onTap: () -> Void = {}

    init(metrics: IslandMetrics, content: IslandContent, nowPlaying: NowPlayingService, lyrics: LyricsService, battery: BatteryService, bluetooth: BluetoothAudioService, weather: WeatherService, airDrop: AirDropService) {
        self.metrics = metrics
        self.content = content
        self.nowPlaying = nowPlaying
        self.lyrics = lyrics
        self.battery = battery
        self.bluetooth = bluetooth
        self.weather = weather
        self.airDrop = airDrop
    }

    var layout: IslandLayout {
        metrics.layout(expanded: isExpanded, content: content, drop: drop)
    }
}
