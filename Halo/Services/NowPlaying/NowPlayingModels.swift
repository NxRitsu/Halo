import Foundation

/// How now playing information is obtained.
enum NowPlayingMethod: Sendable, Equatable {
    /// MediaRemote, called from Halo's own process.
    case mediaRemoteDirect
    /// MediaRemote, called from `/usr/bin/perl` through the helper library.
    case mediaRemoteHelper
    /// Distributed notifications and AppleScript, for Apple Music and Spotify only.
    case scripting
}

enum MediaCommand: Sendable, Equatable {
    case play
    case pause
    case togglePlayPause
    case nextTrack
    case previousTrack
    case seek(TimeInterval)

    /// Command line understood by the MediaRemote helper.
    var helperLine: String {
        switch self {
        case .play: "play"
        case .pause: "pause"
        case .togglePlayPause: "toggle"
        case .nextTrack: "next"
        case .previousTrack: "previous"
        case .seek(let position): "seek \(position)"
        }
    }
}

/// One state of the now playing session, as reported by a source.
struct NowPlayingSnapshot: Sendable, Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval?
    var elapsed: TimeInterval?
    /// Moment at which `elapsed` was measured.
    var timestamp: Date?
    var isPlaying: Bool
    /// App that owns the playback (the browser for web content).
    var bundleIdentifier: String?
    var artworkIdentifier: String?
    /// Only present when the artwork changed since the previous snapshot.
    var artworkData: Data?
}

enum NowPlayingEvent: Sendable {
    case ready
    case snapshot(NowPlayingSnapshot)
    case empty
    case failed(String)

    /// Decodes one JSON message from the MediaRemote helper.
    init?(helperMessage data: Data) {
        guard let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = message["type"] as? String
        else { return nil }

        switch type {
        case "ready":
            self = .ready
        case "empty":
            self = .empty
        case "error":
            self = .failed(message["message"] as? String ?? "Unknown error")
        case "nowPlaying":
            let rate = message["rate"] as? Double ?? 0
            let duration = message["duration"] as? Double
            let parent = message["parentBundleIdentifier"] as? String
            self = .snapshot(NowPlayingSnapshot(
                title: message["title"] as? String ?? "",
                artist: message["artist"] as? String ?? "",
                album: message["album"] as? String ?? "",
                duration: duration.flatMap { $0 > 0 ? $0 : nil },
                elapsed: message["elapsed"] as? Double,
                timestamp: (message["timestamp"] as? Double).map(Date.init(timeIntervalSince1970:)),
                isPlaying: (message["playing"] as? Bool ?? false) || rate > 0,
                bundleIdentifier: parent ?? message["bundleIdentifier"] as? String,
                artworkIdentifier: message["artworkIdentifier"] as? String,
                artworkData: (message["artwork"] as? String).flatMap { Data(base64Encoded: $0) }
            ))
        default:
            return nil
        }
    }
}

/// A provider of now playing events and receiver of media commands.
@MainActor
protocol NowPlayingSource: AnyObject {
    var method: NowPlayingMethod { get }
    func start(_ handler: @escaping @MainActor (NowPlayingEvent) -> Void)
    func stop()
    func send(_ command: MediaCommand)
}
