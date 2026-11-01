import SwiftUI

/// Synced lyrics that scroll to keep the line being sung in the middle.
///
/// Instead of a timer, the view sleeps until the next line starts, and restarts whenever the
/// playback position or state changes (seek, pause, track change).
struct LyricsView: View {
    let lyrics: SyncedLyrics
    let nowPlaying: NowPlayingService

    @State private var currentIndex: Int?

    private struct SyncKey: Equatable {
        var position: PlaybackPosition?
        var isPlaying: Bool
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(lyrics.lines.indices, id: \.self) { index in
                        line(at: index)
                            .id(index)
                    }
                }
                // Lets the first and last lines reach the middle.
                .padding(.vertical, 26)
            }
            .scrollIndicators(.never)
            .scrollDisabled(true)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.3),
                        .init(color: .black, location: 0.7),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .onAppear {
                proxy.scrollTo(currentIndex ?? 0, anchor: .center)
            }
            .onChange(of: currentIndex) { _, index in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    proxy.scrollTo(index ?? 0, anchor: .center)
                }
            }
        }
        .task(id: SyncKey(position: nowPlaying.position, isPlaying: nowPlaying.isPlaying)) {
            await followPlayback()
        }
    }

    private func line(at index: Int) -> some View {
        let text = lyrics.lines[index].text
        let isCurrent = index == currentIndex
        return Text(verbatim: text.isEmpty ? "♪" : text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(isCurrent ? 1 : 0.35))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeOut(duration: 0.25), value: isCurrent)
    }

    private func followPlayback() async {
        while !Task.isCancelled {
            guard let elapsed = nowPlaying.elapsed(at: .now) else {
                currentIndex = nil
                return
            }
            let index = lyrics.lineIndex(at: elapsed)
            if index != currentIndex {
                currentIndex = index
            }
            guard nowPlaying.isPlaying, let next = lyrics.nextLineTime(after: index) else { return }
            try? await Task.sleep(for: .seconds(max(next - elapsed, 0.05)))
        }
    }
}
