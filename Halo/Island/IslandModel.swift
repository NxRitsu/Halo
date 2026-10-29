import Foundation

/// Observable state of one island, shared between its window controller and its SwiftUI view.
@MainActor
@Observable
final class IslandModel {
    var metrics: IslandMetrics
    var isExpanded = false

    /// Called when the user clicks the island.
    var onTap: () -> Void = {}

    init(metrics: IslandMetrics) {
        self.metrics = metrics
    }

    var layout: IslandLayout {
        isExpanded ? metrics.expanded : metrics.compact
    }
}
