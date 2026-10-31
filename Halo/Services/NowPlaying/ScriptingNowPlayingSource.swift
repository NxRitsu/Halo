import AppKit

/// Last resort source for Apple Music and Spotify, used when MediaRemote is unavailable.
///
/// Both apps broadcast their state through distributed notifications, which need no permission.
/// Commands are sent with AppleScript, which asks the user for Automation permission once.
/// Artwork and other players (browsers…) are not supported.
@MainActor
final class ScriptingNowPlayingSource: NowPlayingSource {
    private enum Player: String, CaseIterable {
        case music = "com.apple.Music"
        case spotify = "com.spotify.client"

        var notificationName: Notification.Name {
            switch self {
            case .music: Notification.Name("com.apple.Music.playerInfo")
            case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
            }
        }
    }

    let method = NowPlayingMethod.scripting
    private var observers: [NSObjectProtocol] = []
    private var activePlayer: Player?

    func start(_ handler: @escaping @MainActor (NowPlayingEvent) -> Void) {
        let center = DistributedNotificationCenter.default()
        for player in Player.allCases {
            let token = center.addObserver(forName: player.notificationName, object: nil, queue: .main) { [weak self] notification in
                let info = notification.userInfo ?? [:]
                let state = info["Player State"] as? String ?? ""
                let title = info["Name"] as? String ?? ""
                let artist = info["Artist"] as? String ?? ""
                let album = info["Album"] as? String ?? ""
                // Music reports "Total Time" and Spotify "Duration", both in milliseconds.
                let milliseconds = (info["Total Time"] as? Double) ?? (info["Duration"] as? Double)
                let position = info["Playback Position"] as? Double
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if state == "Stopped" || title.isEmpty {
                        if self.activePlayer == player {
                            handler(.empty)
                        }
                        return
                    }
                    self.activePlayer = player
                    handler(.snapshot(NowPlayingSnapshot(
                        title: title,
                        artist: artist,
                        album: album,
                        duration: milliseconds.map { $0 / 1000 },
                        elapsed: position,
                        timestamp: position == nil ? nil : .now,
                        isPlaying: state == "Playing",
                        bundleIdentifier: player.rawValue,
                        artworkIdentifier: nil,
                        artworkData: nil
                    )))
                }
            }
            observers.append(token)
        }
        handler(.ready)
    }

    func stop() {
        observers.forEach(DistributedNotificationCenter.default().removeObserver)
        observers.removeAll()
        activePlayer = nil
    }

    func send(_ command: MediaCommand) {
        guard let player = activePlayer else { return }
        let statement = switch command {
        case .play: "play"
        case .pause: "pause"
        case .togglePlayPause: "playpause"
        case .nextTrack: "next track"
        case .previousTrack: "previous track"
        case .seek(let position): "set player position to \(position)"
        }
        let source = "tell application id \"\(player.rawValue)\" to \(statement)"
        NSAppleScript(source: source)?.executeAndReturnError(nil)
    }
}
