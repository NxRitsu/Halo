import SwiftUI

/// Shown while files are dragged over the island: releasing them opens the AirDrop window.
struct AirDropZoneView: View {
    let drop: IslandDrop
    let airDrop: AirDropService

    var body: some View {
        let isReady = drop != .unavailable

        HStack(spacing: 14) {
            icon
                .frame(width: 40, height: 40)
                .opacity(isReady ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 2) {
                Text(isReady ? "Drop to send with AirDrop" : "AirDrop isn't available")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                detail
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(isReady ? 0.35 : 0.15), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        if let image = airDrop.icon {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "dot.radiowaves.up.forward")
                .font(.system(size: 26))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch drop {
        case .ready(let fileCount):
            Text("^[\(fileCount) file](inflect: true)")
        case .unavailable:
            Text("This Mac can't send files with AirDrop.")
        }
    }
}
