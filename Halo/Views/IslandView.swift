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
        } else if let alert = model.content.alert {
            alertView(alert)
                .id(alert.id)
                .padding(.top, model.metrics.base.height + 2)
                .padding(.horizontal, layout.earRadius + 18)
                .padding(.bottom, 6)
                .frame(width: layout.totalWidth, height: layout.height, alignment: .top)
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
        } else if model.content.compactHasWings {
            CompactWingsView(
                nowPlaying: model.nowPlaying,
                battery: model.battery,
                content: model.content,
                layout: layout,
                wingWidth: model.metrics.wingWidth
            )
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func alertView(_ alert: IslandAlert) -> some View {
        switch alert.event {
        case .battery(let event):
            BatteryAlertView(event: event, battery: model.battery)
        case .bluetooth(let event):
            BluetoothAlertView(event: event, bluetooth: model.bluetooth)
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
