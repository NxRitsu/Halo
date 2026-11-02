#if DEBUG
import AppKit
import SwiftUI

/// Scenes for the images of the README, shown by `scripts/render-visuals.sh`.
///
/// They host the real island views, with sample content instead of the system's: the track,
/// lyrics and artwork below are made up. The window around them only provides the backdrop.
/// None of this is part of release builds.
@MainActor
enum VisualScenes {
    private static var window: NSWindow?

    static func show(_ name: String) {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) else {
            print("Rendering the images needs a display with a notch")
            exit(1)
        }
        let metrics = IslandMetrics(screen: screen)
        let services = SampleServices()
        let view: AnyView
        switch name {
        case "player":
            services.playSampleTrack()
            view = AnyView(PlayerScene(island: services.island(metrics, expanded: true, content: IslandContent(expanded: .nowPlaying, showsLyrics: true))))
        case "compact":
            services.playSampleTrack()
            view = AnyView(CompactScene(island: services.island(metrics, expanded: false, content: IslandContent(expanded: .nowPlaying, compactShowsMedia: true))))
        case "battery":
            services.setCharging()
            view = AnyView(BatteryScene(island: services.island(metrics, expanded: false, content: IslandContent(alert: IslandAlert(event: .pluggedIn, id: 1)))))
        default:
            print("Unknown scene: \(name)")
            exit(1)
        }

        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        window.level = .floating
        window.hasShadow = false
        window.center()
        window.orderFrontRegardless()
        self.window = window
        print("window=\(window.windowNumber)")
        fflush(stdout)
    }
}

@MainActor
private final class SampleServices {
    let nowPlaying = NowPlayingService()
    let lyrics: LyricsService
    let battery = BatteryService()

    init() {
        lyrics = LyricsService(nowPlaying: nowPlaying)
    }

    func island(_ metrics: IslandMetrics, expanded: Bool, content: IslandContent) -> IslandModel {
        let model = IslandModel(metrics: metrics, content: content, nowPlaying: nowPlaying, lyrics: lyrics, battery: battery)
        model.isExpanded = expanded
        return model
    }

    func playSampleTrack() {
        let artwork = ImageRenderer(content: SampleArtwork().frame(width: 112, height: 112))
        artwork.scale = 1
        nowPlaying.showSample(
            track: NowPlayingTrack(title: "Midnight Signal", artist: "Halo Sessions", album: "Sample", duration: 214),
            artwork: artwork.nsImage,
            tint: NSColor(red: 1, green: 0.62, blue: 0.45, alpha: 1),
            elapsed: 54
        )
        lyrics.showSample(SyncedLyrics(lrc: """
        [00:40.00]Streetlights fade behind the rain
        [00:46.00]Radio hums your name again
        [00:52.00]We drive until the morning comes
        [01:30.00]Chasing echoes, chasing suns
        [01:36.00]Midnight signal, calling through
        """))
    }

    func setCharging() {
        battery.showSample(BatteryState(level: 64, isPluggedIn: true, isCharging: true, isCharged: false, timeToFull: 48 * 60))
    }
}

private struct SampleArtwork: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.16, green: 0.09, blue: 0.42), Color(red: 0.95, green: 0.33, blue: 0.42), Color(red: 1, green: 0.72, blue: 0.42)], startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(Color(red: 1, green: 0.87, blue: 0.62))
                .frame(width: 50, height: 50)
                .offset(y: 16)
            Rectangle()
                .fill(Color(red: 0.08, green: 0.05, blue: 0.22))
                .frame(height: 34)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

// MARK: - Scenes

private struct PlayerScene: View {
    let island: IslandModel

    var body: some View {
        SceneBackdrop(island: island, scale: 1.25) {
            VStack(spacing: 12) {
                Spacer(minLength: 0)
                Text(verbatim: "Your notch, brought to life.")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                Text(verbatim: "What's playing and synced lyrics, right where you already look.")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                HStack(spacing: 10) {
                    FeaturePill(text: "Free and open source")
                    FeaturePill(text: "Native Swift")
                    FeaturePill(text: "~0% CPU at rest")
                    FeaturePill(text: "No telemetry")
                }
                .padding(.top, 10)
                .padding(.bottom, 44)
            }
        }
        .frame(width: 1200, height: 675)
    }
}

private struct CompactScene: View {
    let island: IslandModel

    var body: some View {
        SceneBackdrop(island: island, scale: 2.4) {
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                Text(verbatim: "Always there. Never in the way.")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                Text(verbatim: "Artwork and a live equalizer around the notch, with a mode that keeps your menus clear.")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.bottom, 44)
            }
        }
        .frame(width: 1200, height: 400)
    }
}

private struct BatteryScene: View {
    let island: IslandModel

    var body: some View {
        SceneBackdrop(island: island, scale: 1.9) {
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                Text(verbatim: "A glance, then it's gone.")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                Text(verbatim: "Charging and low battery alerts show for three seconds, then step aside.")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.bottom, 44)
            }
        }
        .frame(width: 1200, height: 400)
    }
}

/// An abstract wallpaper and a menu bar, with the island at the top and a caption over them.
private struct SceneBackdrop<Caption: View>: View {
    let island: IslandModel
    let scale: CGFloat
    @ViewBuilder let caption: Caption

    var body: some View {
        ZStack(alignment: .top) {
            Wallpaper()
            caption
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            SampleMenuBar(width: 1200 / scale, isCondensed: scale > 1.5)
                .scaleEffect(scale, anchor: .top)
            IslandView(model: island)
                .frame(width: 600, height: 300, alignment: .top)
                .scaleEffect(scale, anchor: .top)
        }
        .clipped()
    }
}

private struct Wallpaper: View {
    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.55, 0.45], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                Color(red: 0.06, green: 0.05, blue: 0.20), Color(red: 0.13, green: 0.09, blue: 0.36), Color(red: 0.05, green: 0.12, blue: 0.30),
                Color(red: 0.32, green: 0.12, blue: 0.48), Color(red: 0.62, green: 0.20, blue: 0.50), Color(red: 0.10, green: 0.26, blue: 0.52),
                Color(red: 0.86, green: 0.36, blue: 0.40), Color(red: 0.98, green: 0.58, blue: 0.36), Color(red: 0.42, green: 0.26, blue: 0.56),
            ]
        )
    }
}

private struct SampleMenuBar: View {
    let width: CGFloat
    /// Zoomed in, only what fits beside the island.
    let isCondensed: Bool

    var body: some View {
        HStack(spacing: isCondensed ? 12 : 18) {
            Text(verbatim: "Finder").fontWeight(.bold)
            ForEach(isCondensed ? ["File"] : ["File", "Edit", "View", "Go"], id: \.self) { item in
                Text(verbatim: item)
            }
            Spacer()
            Image(systemName: "wifi")
            if !isCondensed {
                Image(systemName: "magnifyingglass")
            }
            Text(verbatim: isCondensed ? "9:41" : "Mon 9:41")
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(width: width, height: 32)
        .background(.white.opacity(0.08))
    }
}

private struct FeaturePill: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.white.opacity(0.14), in: .capsule)
    }
}
#endif
