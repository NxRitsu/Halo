import SwiftUI

struct IslandView: View {
    let model: IslandModel

    var body: some View {
        let layout = model.layout
        let shape = IslandShape(earRadius: layout.earRadius, bottomRadius: layout.bottomRadius)

        shape
            .fill(.black)
            .frame(width: layout.totalWidth, height: layout.height)
            .overlay(alignment: .top) {
                content(layout: layout)
            }
            .clipShape(shape)
            .contentShape(shape)
            .onTapGesture { model.onTap() }
            .contextMenu {
                Button("Settings…") {
                    SettingsWindowController.shared.show()
                }
                Divider()
                Button("Quit \(AppInfo.name)") {
                    NSApp.terminate(nil)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func content(layout: IslandLayout) -> some View {
        if model.isExpanded {
            Group {
                switch model.content.expanded {
                case .nowPlaying:
                    ExpandedNowPlayingView(
                        nowPlaying: model.nowPlaying,
                        lyrics: model.content.showsLyrics ? model.lyrics.lyrics : nil
                    )
                case .idle:
                    ClockView()
                }
            }
            .padding(.top, model.metrics.base.height + 8)
            .padding(.horizontal, layout.earRadius + 22)
            .padding(.bottom, 16)
            .frame(width: layout.totalWidth, height: layout.height, alignment: .top)
            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
        } else if model.content.compactShowsMedia {
            CompactNowPlayingView(nowPlaying: model.nowPlaying, layout: layout, wingWidth: model.metrics.wingWidth)
                .transition(.opacity)
        }
    }
}

/// Expanded content when nothing else is going on.
private struct ClockView: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(alignment: .firstTextBaseline) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Spacer()
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
            .frame(maxHeight: .infinity)
        }
    }
}
