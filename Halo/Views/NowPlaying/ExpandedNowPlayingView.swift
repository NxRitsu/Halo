import AppKit
import SwiftUI

/// Expanded island while a track is loaded: artwork, title, progress and playback controls.
struct ExpandedNowPlayingView: View {
    let nowPlaying: NowPlayingService
    /// Synced lyrics of the track, when the island has room for them.
    let lyrics: SyncedLyrics?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 3) {
                    Text(nowPlaying.track?.title ?? "")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(nowPlaying.track?.artist ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                EqualizerView(isAnimating: nowPlaying.isPlaying, color: nowPlaying.artworkTint ?? .white)
                    .frame(width: 18, height: 16)
            }

            if let lyrics {
                LyricsView(lyrics: lyrics, nowPlaying: nowPlaying)
                    .id(lyrics)
                    .frame(height: IslandMetrics.lyricsHeight - 12)
                    .transition(.opacity)
            }

            if nowPlaying.track?.duration != nil {
                PlaybackProgressView(nowPlaying: nowPlaying)
            }

            if nowPlaying.isControllable {
                HStack(spacing: 30) {
                    IslandControlButton(systemImage: "backward.fill", size: 17) {
                        nowPlaying.previousTrack()
                    }
                    IslandControlButton(systemImage: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 22, prominent: true) {
                        nowPlaying.togglePlayPause()
                    }
                    IslandControlButton(systemImage: "forward.fill", size: 17) {
                        nowPlaying.nextTrack()
                    }
                }
            } else {
                controlsUnavailable
            }
        }
    }

    /// Shown instead of the controls while macOS sends media commands to another app.
    private var controlsUnavailable: some View {
        HStack(spacing: 12) {
            Text("macOS sends the controls to another app. Close it, or pause and resume in this app.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open App", action: openPlayerApp)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .frame(height: 40)
    }

    private var artwork: some View {
        ArtworkView(image: nowPlaying.artwork, size: NowPlayingService.artworkDisplaySize)
            .overlay(alignment: .bottomTrailing) {
                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                        .offset(x: 5, y: 5)
                }
            }
            .onTapGesture(perform: openPlayerApp)
    }

    private var appURL: URL? {
        nowPlaying.track?.bundleIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    }

    private var appIcon: NSImage? {
        appURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    private func openPlayerApp() {
        guard let appURL else { return }
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Round playback button with a hover highlight; the main one uses Liquid Glass.
private struct IslandControlButton: View {
    let systemImage: String
    let size: CGFloat
    var prominent = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(.white)
                .frame(width: prominent ? 40 : 34, height: prominent ? 40 : 34)
                .background {
                    if !prominent {
                        Circle().fill(.white.opacity(isHovering ? 0.12 : 0))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(ProminentGlass(enabled: prominent))
        .onHover { isHovering = $0 }
    }
}

private struct ProminentGlass: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
        }
    }
}
