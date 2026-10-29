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
                if model.isExpanded {
                    ExpandedPlaceholderView()
                        .padding(.top, model.metrics.compact.height)
                        .padding(.horizontal, layout.earRadius + 24)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                }
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
}

/// Temporary content of the expanded island until activities are implemented.
private struct ExpandedPlaceholderView: View {
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
