import Foundation

/// Observable state of one island, shared between its window controller and its SwiftUI view.
@MainActor
@Observable
final class IslandModel {
    var metrics: IslandMetrics
    var isExpanded = false
    var content: IslandContent
    let nowPlaying: NowPlayingService
    let lyrics: LyricsService
    let battery: BatteryService
    let bluetooth: BluetoothAudioService

    /// Called when the user clicks the island.
    var onTap: () -> Void = {}

    init(metrics: IslandMetrics, content: IslandContent, nowPlaying: NowPlayingService, lyrics: LyricsService, battery: BatteryService, bluetooth: BluetoothAudioService) {
        self.metrics = metrics
        self.content = content
        self.nowPlaying = nowPlaying
        self.lyrics = lyrics
        self.battery = battery
        self.bluetooth = bluetooth
    }

    var layout: IslandLayout {
        metrics.layout(expanded: isExpanded, content: content)
    }
}
