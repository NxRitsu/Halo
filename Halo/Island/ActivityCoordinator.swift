import Foundation

/// What an island shows in each of its states.
struct IslandContent: Equatable {
    enum Activity: Equatable {
        case idle
        case nowPlaying
    }

    /// Activity shown when the island is expanded.
    var expanded = Activity.idle
    /// Whether the compact island shows the now playing "wings" around the notch.
    var compactShowsMedia = false
}

/// Decides what the islands display, by priority:
/// temporary alerts (later phases) > media playing > idle.
@MainActor
@Observable
final class ActivityCoordinator {
    private(set) var content = IslandContent()

    @ObservationIgnored private let nowPlaying: NowPlayingService
    @ObservationIgnored private var pendingMediaHide: Task<Void, Never>?

    init(nowPlaying: NowPlayingService) {
        self.nowPlaying = nowPlaying
        observe()
    }

    private func observe() {
        withObservationTracking {
            update()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observe()
            }
        }
    }

    private func update() {
        let hasTrack = nowPlaying.track != nil
        let isPlaying = hasTrack && nowPlaying.isPlaying

        let expanded: IslandContent.Activity = hasTrack ? .nowPlaying : .idle
        if content.expanded != expanded {
            content.expanded = expanded
        }

        if isPlaying {
            pendingMediaHide?.cancel()
            pendingMediaHide = nil
            if !content.compactShowsMedia {
                content.compactShowsMedia = true
            }
        } else if content.compactShowsMedia, pendingMediaHide == nil {
            // Wait a little before hiding the wings: track changes briefly report a paused state.
            pendingMediaHide = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                self.pendingMediaHide = nil
                self.content.compactShowsMedia = false
            }
        }
    }
}
