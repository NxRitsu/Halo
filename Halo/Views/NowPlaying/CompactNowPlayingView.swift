import SwiftUI

/// Compact island while media is playing: artwork left of the notch, equalizer right of it.
struct CompactNowPlayingView: View {
    let nowPlaying: NowPlayingService
    let layout: IslandLayout
    let wingWidth: CGFloat

    var body: some View {
        let artworkSize = layout.height - 12
        HStack(spacing: 0) {
            ArtworkView(image: nowPlaying.artwork, size: artworkSize)
                .frame(width: wingWidth)
            Spacer(minLength: 0)
            EqualizerView(
                isAnimating: nowPlaying.isPlaying,
                color: nowPlaying.artworkTint ?? .white
            )
            .frame(width: 16, height: artworkSize * 0.75)
            .frame(width: wingWidth)
        }
        .padding(.horizontal, layout.earRadius)
        .frame(width: layout.totalWidth, height: layout.height)
    }
}
