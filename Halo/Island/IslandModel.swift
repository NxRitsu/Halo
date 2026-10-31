import Foundation

/// Observable state of one island, shared between its window controller and its SwiftUI view.
@MainActor
@Observable
final class IslandModel {
    var metrics: IslandMetrics
    var isExpanded = false
    var content: IslandContent
    let nowPlaying: NowPlayingService

    /// Called when the user clicks the island.
    var onTap: () -> Void = {}

    init(metrics: IslandMetrics, content: IslandContent, nowPlaying: NowPlayingService) {
        self.metrics = metrics
        self.content = content
        self.nowPlaying = nowPlaying
    }

    var layout: IslandLayout {
        metrics.layout(expanded: isExpanded, content: content)
    }
}
