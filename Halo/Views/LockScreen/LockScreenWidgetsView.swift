import SwiftUI

/// Widgets on the lock screen: what's playing with its lyrics, the weather, the battery and the
/// connected audio devices. They can't be used, only read.
struct LockScreenWidgetsView: View {
    let nowPlaying: NowPlayingService
    let lyrics: LyricsService
    let weather: WeatherService
    let battery: BatteryService
    let bluetooth: BluetoothAudioService

    @AppStorage(PreferenceKey.lockScreenNowPlaying) private var showsNowPlaying = true
    @AppStorage(PreferenceKey.lockScreenLyrics) private var showsLyrics = true
    @AppStorage(PreferenceKey.lockScreenWeather) private var showsWeather = true
    @AppStorage(PreferenceKey.lockScreenBattery) private var showsBattery = true
    @AppStorage(PreferenceKey.lockScreenAudioDevices) private var showsAudioDevices = true

    var body: some View {
        VStack(spacing: 10) {
            if showsNowPlaying, let track = nowPlaying.track {
                NowPlayingWidget(
                    track: track,
                    nowPlaying: nowPlaying,
                    lyrics: showsLyrics ? lyrics.lyrics : nil
                )
                .transition(.opacity)
            }
            HStack(spacing: 10) {
                if showsWeather, let report = weather.report(at: .now) {
                    WeatherWidget(report: report)
                }
                if showsBattery, let state = battery.state {
                    BatteryWidget(state: state, battery: battery)
                }
                if showsAudioDevices {
                    ForEach(bluetooth.devices.filter { !$0.battery.isEmpty }) { device in
                        AudioDeviceWidget(device: device)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .frame(width: LockScreenService.windowSize.width, height: LockScreenService.windowSize.height, alignment: .top)
        .animation(.easeOut(duration: 0.3), value: nowPlaying.track)
    }
}

/// Background shared by the widgets, as the opacity setting asks: nothing at 0, then glass that
/// fades in up to `glassThreshold`, then glass that gets darker up to 1.
private struct WidgetBackground: ViewModifier {
    private static let glassThreshold = 0.3

    @AppStorage(PreferenceKey.lockScreenOpacity) private var opacity = 0.25

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let glass = min(opacity / Self.glassThreshold, 1)
        let darkness = max(opacity - Self.glassThreshold, 0) / (1 - Self.glassThreshold) * 0.6
        content
            // Keeps the text readable on the wallpaper while the glass is faint.
            .shadow(color: .black.opacity(0.5 * (1 - glass)), radius: 3)
            .padding(14)
            .background {
                ZStack {
                    Color.clear
                        .glassEffect(.regular, in: shape)
                        .opacity(glass)
                    shape.fill(.black.opacity(darkness))
                }
            }
    }
}

private extension View {
    func lockScreenWidget() -> some View {
        modifier(WidgetBackground())
    }
}

private struct NowPlayingWidget: View {
    let track: NowPlayingTrack
    let nowPlaying: NowPlayingService
    let lyrics: SyncedLyrics?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ArtworkView(image: nowPlaying.artwork, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: track.title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(verbatim: track.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: nowPlaying.isPlaying ? "play.fill" : "pause.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
            }
            if let lyrics {
                LyricsView(lyrics: lyrics, nowPlaying: nowPlaying)
                    .frame(height: 70)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lockScreenWidget()
    }
}

private struct WeatherWidget: View {
    let report: WeatherReport
    @AppStorage(PreferenceKey.temperatureUnit) private var unit = TemperatureUnit.system

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: report.symbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 20))
                Text(verbatim: unit.text(celsius: report.temperature))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
            }
            Text(verbatim: "\(unit.text(celsius: report.minimum)) · \(unit.text(celsius: report.maximum))")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
            // The license of the data asks for a credit wherever they are displayed.
            Text(verbatim: "Open-Meteo")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
        .monospacedDigit()
        .lockScreenWidget()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(report.condition.title))
    }
}

private struct BatteryWidget: View {
    let state: BatteryState
    let battery: BatteryService

    var body: some View {
        let tint = BatteryGlyph.tint(for: state, low: battery.lowThreshold, critical: battery.criticalThreshold)
        VStack(spacing: 6) {
            BatteryGlyph(state: state, tint: tint)
                .frame(width: 34, height: 16)
            HStack(spacing: 3) {
                if state.isPluggedIn {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                }
                Text(state.level, format: .percent)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .frame(minHeight: 56)
        .lockScreenWidget()
    }
}

private struct AudioDeviceWidget: View {
    let device: BluetoothAudioDevice

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.symbol)
                .font(.system(size: 22))
            BluetoothBatteryRow(battery: device.battery)
        }
        .frame(minHeight: 56)
        .lockScreenWidget()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: device.name))
    }
}
