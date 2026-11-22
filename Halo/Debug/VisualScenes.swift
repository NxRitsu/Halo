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
    /// Monday, June 9, 9:41 AM: the time of the sample menu bar and lock screen.
    private(set) static var fixedDate: Date?

    static func show(_ name: String) {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) else {
            print("Rendering the images needs a display with a notch")
            exit(1)
        }
        let metrics = IslandMetrics(screen: screen)
        fixedDate = Calendar.current.date(from: DateComponents(year: 2025, month: 6, day: 9, hour: 9, minute: 41))
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
            view = AnyView(BatteryScene(island: services.island(metrics, expanded: false, content: IslandContent(alert: IslandAlert(event: .battery(.pluggedIn), id: 1)))))
        case "airpods":
            let event = BluetoothAudioEvent(kind: .connected, device: services.showSampleHeadphones())
            view = AnyView(BluetoothScene(island: services.island(metrics, expanded: false, content: IslandContent(alert: IslandAlert(event: .bluetooth(event), id: 1)))))
        case "weather":
            services.showSampleWeather()
            view = AnyView(WeatherScene(island: services.island(metrics, expanded: true, content: IslandContent(expanded: .idle))))
        case "lockscreen":
            services.playSampleTrack()
            services.showSampleWeather()
            services.setCharging()
            _ = services.showSampleHeadphones()
            view = AnyView(LockScreenScene(services: services))
        case "airdrop":
            let island = services.island(metrics, expanded: false, content: IslandContent())
            island.drop = .ready(fileCount: 3)
            view = AnyView(AirDropScene(island: island))
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

        // Writes the scene to a file, for when screen recording isn't allowed.
        if let output = ProcessInfo.processInfo.environment["HALO_VISUAL_SCENE_PNG"] {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
                }
                exit(0)
            }
        }
    }
}

@MainActor
private final class SampleServices {
    let nowPlaying = NowPlayingService()
    let lyrics: LyricsService
    let battery = BatteryService()
    let bluetooth = BluetoothAudioService()
    let weather = WeatherService()
    let airDrop = AirDropService()

    init() {
        lyrics = LyricsService(nowPlaying: nowPlaying)
    }

    func island(_ metrics: IslandMetrics, expanded: Bool, content: IslandContent) -> IslandModel {
        let model = IslandModel(metrics: metrics, content: content, nowPlaying: nowPlaying, lyrics: lyrics, battery: battery, bluetooth: bluetooth, weather: weather, airDrop: airDrop)
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

    func showSampleHeadphones() -> BluetoothAudioDevice {
        let device = BluetoothAudioDevice(
            id: "sample",
            name: "Sample's AirPods Pro",
            symbol: "airpods.pro",
            battery: BluetoothBattery(left: 92, right: 18, chargingCase: 64),
            volume: 40,
            listeningMode: .noiseCancellation,
            supportedListeningModes: ListeningMode.allCases
        )
        bluetooth.showSample(device)
        return device
    }

    func showSampleWeather() {
        weather.showSample(WeatherReport(temperature: 18.4, code: 2, isDay: true, minimum: 11.2, maximum: 21.6, fetchedAt: .now))
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
//
// Every scene shares the same backdrop and caption, at 1200 points wide: 675 high for the two
// large ones, 400 for the others.

private struct PlayerScene: View {
    let island: IslandModel

    var body: some View {
        SceneBackdrop(island: island, scale: 1.25) {
            SceneCaption(title: "Your notch, brought to life.", subtitle: "What's playing and synced lyrics, right where you already look.", isLarge: true) {
                HStack(spacing: 10) {
                    FeaturePill(text: "Free and open source")
                    FeaturePill(text: "Native Swift")
                    FeaturePill(text: "~0% CPU at rest")
                    FeaturePill(text: "No telemetry")
                }
                .padding(.top, 10)
            }
        }
        .frame(width: 1200, height: 675)
    }
}

private struct CompactScene: View {
    let island: IslandModel

    var body: some View {
        SceneBackdrop(island: island, scale: 2.4) {
            SceneCaption(title: "Always there. Never in the way.", subtitle: "Artwork and a live equalizer around the notch, with a mode that keeps your menus clear.")
        }
        .frame(width: 1200, height: 400)
    }
}

private struct BatteryScene: View {
    let island: IslandModel

    var body: some View {
        SceneBackdrop(island: island, scale: 1.9) {
            SceneCaption(title: "A glance, then it's gone.", subtitle: "Charging and low battery alerts show for three seconds, then step aside.")
        }
        .frame(width: 1200, height: 400)
    }
}

private struct BluetoothScene: View {
    let island: IslandModel

    var body: some View {
        SceneBackdrop(island: island, scale: 1.9) {
            SceneCaption(title: "Connected, at a glance.", subtitle: "Each earbud and the case, as soon as your AirPods connect.")
        }
        .frame(width: 1200, height: 400)
    }
}

private struct WeatherScene: View {
    let island: IslandModel

    var body: some View {
        SceneBackdrop(island: island, scale: 1.6) {
            SceneCaption(title: "Nothing playing? The weather's there.", subtitle: "Current temperature and the day's range, from your approximate location.")
        }
        .frame(width: 1200, height: 400)
    }
}

private struct AirDropScene: View {
    let island: IslandModel

    var body: some View {
        SceneBackdrop(island: island, scale: 1.6) {
            SceneCaption(title: "Drop it on the notch.", subtitle: "Drag files onto the island and send them with AirDrop, without digging through the Finder.")
        }
        .frame(width: 1200, height: 400)
    }
}

/// The lock screen: the same wallpaper, the date and time macOS draws, and Halo's widgets.
private struct LockScreenScene: View {
    let services: SampleServices

    var body: some View {
        ZStack(alignment: .top) {
            Wallpaper()
            VStack(spacing: 0) {
                Text(verbatim: "Monday, June 9")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(verbatim: "9:41")
                    .font(.system(size: 92, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                LockScreenWidgetsView(nowPlaying: services.nowPlaying, lyrics: services.lyrics, weather: services.weather, battery: services.battery, bluetooth: services.bluetooth)
                    .scaleEffect(1.2, anchor: .top)
                    .frame(height: 260, alignment: .top)
                    .padding(.top, 6)
            }
            .padding(.top, 28)
            SceneCaption(title: "Locked, still in the loop.", subtitle: "What's playing, lyrics, weather and battery on your lock screen. Gone when you unlock.")
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(width: 1200, height: 675)
        .clipped()
    }
}

/// Title and subtitle at the bottom of a scene, with optional content below them.
private struct SceneCaption<Accessory: View>: View {
    let title: String
    let subtitle: String
    var isLarge = false
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(spacing: isLarge ? 12 : 10) {
            Spacer(minLength: 0)
            Text(verbatim: title)
                .font(.system(size: isLarge ? 52 : 42, weight: .bold, design: .rounded))
            Text(verbatim: subtitle)
                .font(.system(size: isLarge ? 21 : 19, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
            accessory
        }
        .padding(.bottom, 44)
    }
}

extension SceneCaption where Accessory == EmptyView {
    init(title: String, subtitle: String, isLarge: Bool = false) {
        self.init(title: title, subtitle: subtitle, isLarge: isLarge) { EmptyView() }
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
