import AppKit
import ImageIO
import OSLog

/// Track currently loaded in the system's now playing session.
struct NowPlayingTrack: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval?
    var bundleIdentifier: String?

    /// Whether both describe the same media, even if details such as the duration were refined.
    func isSameMedia(as other: NowPlayingTrack) -> Bool {
        title == other.title && artist == other.artist && bundleIdentifier == other.bundleIdentifier
    }
}

/// Playback position, extrapolated from the last report while playing.
struct PlaybackPosition: Equatable {
    var elapsed: TimeInterval
    var date: Date
    var isAdvancing: Bool

    func elapsed(at now: Date, duration: TimeInterval?) -> TimeInterval {
        let value = isAdvancing ? elapsed + now.timeIntervalSince(date) : elapsed
        return min(max(value, 0), duration ?? .infinity)
    }
}

/// Observes the system's now playing session and sends playback commands.
///
/// Source selection, as MediaRemote access depends on the macOS version:
/// 1. MediaRemote in Halo's process, if it answers (blocked since macOS 15.4);
/// 2. MediaRemote through the helper running in `/usr/bin/perl`;
/// 3. Apple Music and Spotify notifications and AppleScript.
@MainActor
@Observable
final class NowPlayingService {
    enum Status: Equatable {
        case disabled
        case starting
        case active(NowPlayingMethod)
        case unavailable(String)
    }

    /// Largest size at which artwork is displayed, in points.
    static let artworkDisplaySize: CGFloat = 56

    private(set) var status = Status.starting
    private(set) var track: NowPlayingTrack?
    private(set) var isPlaying = false
    private(set) var position: PlaybackPosition?
    private(set) var artwork: NSImage?
    /// Average color of the artwork, brightened for use on a black background.
    private(set) var artworkTint: NSColor?
    /// Whether Halo's controls can reach the app on screen. When they can't, they are disabled:
    /// macOS would otherwise send them to the app it considers current, such as a paused video.
    private(set) var isControllable = true

    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Halo", category: "NowPlaying")
    @ObservationIgnored private var source: NowPlayingSource?
    @ObservationIgnored private var artworkIdentifier: String?
    /// Set when commands must bypass the source because it can't reach the app on screen.
    @ObservationIgnored private var scriptedPlayer: ScriptablePlayer?
    @ObservationIgnored private var pendingClear: Task<Void, Never>?
    @ObservationIgnored private var pendingArtworkClear: Task<Void, Never>?
    @ObservationIgnored private var optimisticPlayingState: (isPlaying: Bool, until: Date)?
    @ObservationIgnored private var restartAttempts = 0
    @ObservationIgnored private var restartTask: Task<Void, Never>?

    /// The process reading MediaRemote, when it is the source in use.
    var helperProcessIdentifier: pid_t? {
        (source as? HelperProcessMediaRemoteSource)?.processIdentifier
    }

    #if DEBUG
    /// Shows a made-up track, for the images of the README.
    func showSample(track: NowPlayingTrack, artwork: NSImage?, tint: NSColor, elapsed: TimeInterval) {
        self.track = track
        self.artwork = artwork
        artworkTint = tint
        isPlaying = true
        position = PlaybackPosition(elapsed: elapsed, date: .now, isAdvancing: true)
    }
    #endif

    // MARK: - Lifecycle

    func setEnabled(_ enabled: Bool) {
        if enabled {
            guard source == nil, restartTask == nil else { return }
            status = .starting
            Task { await start() }
        } else {
            stopSource()
            restartTask?.cancel()
            restartTask = nil
            clear()
            status = .disabled
        }
    }

    private func start() async {
        if await MediaRemoteHelper.isDirectlyAccessible() {
            use(DirectMediaRemoteSource())
        } else {
            use(HelperProcessMediaRemoteSource())
        }
    }

    private func use(_ newSource: NowPlayingSource) {
        stopSource()
        source = newSource
        logger.notice("Starting now playing source \(String(describing: newSource.method), privacy: .public)")
        newSource.start { [weak self, weak newSource] event in
            guard let self, let newSource, self.source === newSource else { return }
            self.handle(event, from: newSource)
        }
    }

    private func stopSource() {
        source?.stop()
        source = nil
    }

    private func handle(_ event: NowPlayingEvent, from source: NowPlayingSource) {
        switch event {
        case .ready:
            status = .active(source.method)
            restartAttempts = 0
        case .snapshot(let snapshot):
            apply(snapshot)
        case .empty:
            scheduleClear()
        case .failed(let reason):
            logger.error("Now playing source \(String(describing: source.method), privacy: .public) failed: \(reason, privacy: .public)")
            sourceFailed(source, reason: reason)
        }
    }

    private func sourceFailed(_ failedSource: NowPlayingSource, reason: String) {
        let wasActive = status == .active(failedSource.method)
        stopSource()
        switch failedSource.method {
        case .mediaRemoteDirect:
            use(HelperProcessMediaRemoteSource())
        case .mediaRemoteHelper where wasActive && restartAttempts < 3:
            // The helper worked before: restart it with an exponential backoff.
            restartAttempts += 1
            let delay = Duration.seconds(1 << restartAttempts)
            restartTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled else { return }
                self.restartTask = nil
                self.use(HelperProcessMediaRemoteSource())
            }
        case .mediaRemoteHelper:
            use(ScriptingNowPlayingSource())
        case .scripting:
            clear()
            status = .unavailable(reason)
        }
    }

    // MARK: - State

    private func apply(_ snapshot: NowPlayingSnapshot) {
        guard !snapshot.title.isEmpty || !snapshot.artist.isEmpty else {
            scheduleClear()
            return
        }
        pendingClear?.cancel()
        pendingClear = nil

        let newTrack = NowPlayingTrack(
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            duration: snapshot.duration,
            bundleIdentifier: snapshot.bundleIdentifier
        )
        let isSameMedia = track?.isSameMedia(as: newTrack) ?? false
        if newTrack != track {
            track = newTrack
        }

        let player = snapshot.isControllable ? nil : snapshot.bundleIdentifier.flatMap(ScriptablePlayer.init(rawValue:))
        scriptedPlayer = player
        let controllable = snapshot.isControllable || player != nil
        if controllable != isControllable {
            isControllable = controllable
        }

        var playing = snapshot.isPlaying
        if let optimistic = optimisticPlayingState {
            if Date.now < optimistic.until, optimistic.isPlaying != playing {
                // A stale report arrived right after a command: keep the optimistic state.
                playing = optimistic.isPlaying
            } else {
                optimisticPlayingState = nil
            }
        }
        if playing != isPlaying {
            isPlaying = playing
        }

        if let elapsed = snapshot.elapsed {
            let newPosition = PlaybackPosition(elapsed: elapsed, date: snapshot.timestamp ?? .now, isAdvancing: playing)
            if newPosition != position {
                position = newPosition
            }
        } else if position != nil, snapshot.duration == nil {
            position = nil
        }

        if let data = snapshot.artworkData {
            cancelArtworkClear()
            artworkIdentifier = snapshot.artworkIdentifier
            setArtwork(from: data)
        } else if snapshot.artworkIdentifier != nil {
            cancelArtworkClear()
        } else if !isSameMedia, artwork != nil {
            scheduleArtworkClear()
        }
    }

    /// Some apps report a new track or republish its info without artwork, and send the artwork
    /// right after. So missing artwork never removes the current one for the same track, and
    /// only removes it after a delay for a new track.
    private func scheduleArtworkClear() {
        guard pendingArtworkClear == nil else { return }
        pendingArtworkClear = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            self.pendingArtworkClear = nil
            self.artworkIdentifier = nil
            self.artwork = nil
            self.artworkTint = nil
        }
    }

    private func cancelArtworkClear() {
        pendingArtworkClear?.cancel()
        pendingArtworkClear = nil
    }

    /// Sources briefly report an empty session when playback moves from one app to another
    /// (for instance from a web video to a paused app). Wait before clearing, so the island
    /// doesn't flash "nothing playing".
    private func scheduleClear() {
        guard pendingClear == nil else { return }
        pendingClear = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            self.pendingClear = nil
            self.clear()
        }
    }

    private func clear() {
        pendingClear?.cancel()
        pendingClear = nil
        cancelArtworkClear()
        track = nil
        isPlaying = false
        position = nil
        artwork = nil
        artworkTint = nil
        artworkIdentifier = nil
        optimisticPlayingState = nil
        scriptedPlayer = nil
        isControllable = true
    }

    /// Decodes the artwork directly at its largest display size, so full-size images never stay in memory.
    private func setArtwork(from data: Data) {
        let maxPixelSize = Self.artworkDisplaySize * (NSScreen.screens.map(\.backingScaleFactor).max() ?? 2)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary)
        else {
            artwork = nil
            artworkTint = nil
            return
        }
        artwork = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        artworkTint = Self.tint(of: image)
    }

    private static func tint(of image: CGImage) -> NSColor? {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let color = NSColor(
            red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1
        )
        // Keep the hue, but make sure it stays readable on black.
        return NSColor(
            hue: color.hueComponent,
            saturation: min(color.saturationComponent, 0.7),
            brightness: max(color.brightnessComponent, 0.85),
            alpha: 1
        )
    }

    // MARK: - Commands

    func elapsed(at date: Date) -> TimeInterval? {
        position?.elapsed(at: date, duration: track?.duration)
    }

    func togglePlayPause() {
        guard isControllable else { return }
        let playing = !isPlaying
        setOptimisticPlaying(playing)
        send(playing ? .play : .pause)
    }

    func nextTrack() {
        guard isControllable else { return }
        send(.nextTrack)
        if position != nil {
            position = PlaybackPosition(elapsed: 0, date: .now, isAdvancing: false)
        }
    }

    func previousTrack() {
        guard isControllable else { return }
        send(.previousTrack)
    }

    func seek(to time: TimeInterval) {
        guard isControllable else { return }
        position = PlaybackPosition(elapsed: time, date: .now, isAdvancing: isPlaying)
        send(.seek(time))
    }

    private func send(_ command: MediaCommand) {
        if let scriptedPlayer {
            scriptedPlayer.send(command)
        } else {
            source?.send(command)
        }
    }

    private func setOptimisticPlaying(_ playing: Bool) {
        optimisticPlayingState = (playing, Date.now.addingTimeInterval(1.5))
        if let current = elapsed(at: .now) {
            position = PlaybackPosition(elapsed: current, date: .now, isAdvancing: playing)
        }
        isPlaying = playing
    }
}
