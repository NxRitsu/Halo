import SwiftUI

/// Compact island with content left and right of the notch.
///
/// While media is playing: artwork on the left, equalizer on the right. When the battery is low,
/// its charge replaces the equalizer, and a battery glyph fills the left side if nothing is playing.
struct CompactWingsView: View {
    let nowPlaying: NowPlayingService
    let battery: BatteryService
    let content: IslandContent
    let layout: IslandLayout
    let wingWidth: CGFloat

    var body: some View {
        let artworkSize = layout.height - 12
        let batteryState = content.compactShowsBattery ? battery.state : nil
        HStack(spacing: 0) {
            Group {
                if content.compactShowsMedia {
                    ArtworkView(image: nowPlaying.artwork, size: artworkSize)
                } else if let batteryState {
                    BatteryGlyph(state: batteryState, tint: tint)
                        .frame(width: 24, height: 12)
                }
            }
            .frame(width: wingWidth)
            Spacer(minLength: 0)
            Group {
                if let batteryState {
                    Text(batteryState.level, format: .percent)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .fixedSize()
                } else if content.compactShowsMedia {
                    EqualizerView(
                        isAnimating: nowPlaying.isPlaying,
                        color: nowPlaying.artworkTint ?? .white
                    )
                    .frame(width: 16, height: artworkSize * 0.75)
                }
            }
            .frame(width: wingWidth)
        }
        .padding(.horizontal, layout.earRadius)
        .frame(width: layout.totalWidth, height: layout.height)
    }

    private var tint: Color {
        BatteryGlyph.tint(for: battery.state, low: battery.lowThreshold, critical: battery.criticalThreshold)
    }
}
