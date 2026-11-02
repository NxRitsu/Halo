import Foundation

/// A temporary alert shown on the compact island.
struct IslandAlert: Equatable {
    enum Event: Equatable {
        case battery(BatteryEvent)
        case bluetooth(BluetoothAudioEvent)
    }

    let event: Event
    /// Distinguishes two alerts for the same event, so the second one restarts the timer.
    let id: Int
}

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
    /// Whether the compact island shows the low battery indicator.
    var compactShowsBattery = false
    /// Whether the expanded player has room for synced lyrics.
    var showsLyrics = false
    /// Temporary alert, shown instead of the compact island for a few seconds.
    var alert: IslandAlert?

    /// Whether the compact island has content on both sides of the notch.
    var compactHasWings: Bool { compactShowsMedia || compactShowsBattery }
}

/// Decides what the islands display, by priority:
/// temporary alerts > media playing > idle.
@MainActor
@Observable
final class ActivityCoordinator {
    private static let alertDuration: Duration = .seconds(3)
    /// Long enough for the volume, which macOS only exposes 2 to 3 s after the connection.
    private static let connectionAlertDuration: Duration = .seconds(5)

    private(set) var content = IslandContent()
    /// Whether the compact island shows the charge when the battery is low.
    var showsLowBatteryIndicator = true
    /// When the compact island shows the artwork and equalizer around the notch while media
    /// plays. Otherwise, the media stays reachable by expanding the island.
    var mediaWingsMode = MediaWingsMode.always {
        didSet { menuBar.setEnabled(mediaWingsMode == .automatic) }
    }

    @ObservationIgnored private let nowPlaying: NowPlayingService
    @ObservationIgnored private let lyrics: LyricsService
    @ObservationIgnored private let battery: BatteryService
    @ObservationIgnored private let bluetooth: BluetoothAudioService
    @ObservationIgnored private let menuBar: MenuBarSpaceMonitor
    @ObservationIgnored private var pendingMediaHide: Task<Void, Never>?
    @ObservationIgnored private var alertTask: Task<Void, Never>?
    @ObservationIgnored private var alertCount = 0

    init(nowPlaying: NowPlayingService, lyrics: LyricsService, battery: BatteryService, bluetooth: BluetoothAudioService, menuBar: MenuBarSpaceMonitor) {
        self.nowPlaying = nowPlaying
        self.lyrics = lyrics
        self.battery = battery
        self.bluetooth = bluetooth
        self.menuBar = menuBar
        battery.onEvent = { [weak self] event in
            self?.batteryEvent(event)
        }
        bluetooth.onEvent = { [weak self] event in
            self?.bluetoothEvent(event)
        }
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

        let showsLyrics = hasTrack && lyrics.lyrics != nil
        if content.showsLyrics != showsLyrics {
            content.showsLyrics = showsLyrics
        }

        // The automatic mode keeps the menu bar clear, whatever the wings would show.
        let wingsCoverMenus = mediaWingsMode == .automatic && menuBar.wingsCoverMenus

        let showsBattery = showsLowBatteryIndicator && battery.isLow && !wingsCoverMenus
        if content.compactShowsBattery != showsBattery {
            content.compactShowsBattery = showsBattery
        }

        if mediaWingsMode == .never || wingsCoverMenus {
            pendingMediaHide?.cancel()
            pendingMediaHide = nil
            if content.compactShowsMedia {
                content.compactShowsMedia = false
            }
        } else if isPlaying {
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

    // MARK: - Alerts

    private func batteryEvent(_ event: BatteryEvent) {
        switch event {
        case .pluggedIn, .unplugged:
            guard Preferences.powerAlertsEnabled else { return }
        case .low:
            guard Preferences.lowBatteryAlertsEnabled else { return }
        }
        showAlert(.battery(event))
    }

    private func bluetoothEvent(_ event: BluetoothAudioEvent) {
        if event.kind == .disconnected, !Preferences.bluetoothDisconnectAlertsEnabled { return }
        showAlert(.bluetooth(event), duration: event.kind == .connected ? Self.connectionAlertDuration : Self.alertDuration)
    }

    private func showAlert(_ event: IslandAlert.Event, duration: Duration = alertDuration) {
        alertCount += 1
        content.alert = IslandAlert(event: event, id: alertCount)
        alertTask?.cancel()
        alertTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, !Task.isCancelled else { return }
            self.alertTask = nil
            self.content.alert = nil
        }
    }
}
