import SwiftUI

/// Seekable progress bar. It only grows while being dragged, and refreshes twice per second
/// only while playing and visible.
struct PlaybackProgressView: View {
    let nowPlaying: NowPlayingService
    @State private var dragFraction: Double?

    var body: some View {
        let duration = nowPlaying.track?.duration ?? 0
        TimelineView(.animation(minimumInterval: 0.5, paused: !nowPlaying.isPlaying || dragFraction != nil)) { context in
            let elapsed = dragFraction.map { $0 * duration } ?? nowPlaying.elapsed(at: context.date) ?? 0
            let fraction = duration > 0 ? min(max(elapsed / duration, 0), 1) : 0
            HStack(spacing: 10) {
                TimeLabel(seconds: elapsed)
                    .frame(width: 42, alignment: .leading)
                GeometryReader { geometry in
                    let isDragging = dragFraction != nil
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule().fill(.white).frame(width: geometry.size.width * fraction)
                    }
                    .frame(height: isDragging ? 8 : 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                dragFraction = min(max(value.location.x / geometry.size.width, 0), 1)
                            }
                            .onEnded { value in
                                let final = min(max(value.location.x / geometry.size.width, 0), 1)
                                // Seeking is only sent once, when the drag ends.
                                nowPlaying.seek(to: final * duration)
                                dragFraction = nil
                            }
                    )
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
                }
                .frame(height: 14)
                TimeLabel(seconds: -(duration - elapsed))
                    .frame(width: 42, alignment: .trailing)
            }
        }
    }
}

private struct TimeLabel: View {
    let seconds: TimeInterval

    var body: some View {
        let total = Int(abs(seconds).rounded(.down))
        let text = String(format: "%@%d:%02d", seconds < 0 ? "-" : "", total / 60, total % 60)
        Text(verbatim: text)
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.55))
    }
}
