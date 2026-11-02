import SwiftUI

/// A battery outline filled up to the charge level, with a bolt while plugged in.
struct BatteryGlyph: View {
    let state: BatteryState
    let tint: Color
    /// Charge drawn, from 0 to 1. Defaults to the actual charge; animatable for the charging effect.
    var fill: Double?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let capWidth = max(size.width * 0.07, 1.5)
            let bodyWidth = size.width - capWidth - 1
            let lineWidth = max(size.height * 0.09, 1)
            let inset = lineWidth + max(size.height * 0.08, 1)
            let radius = size.height * 0.3
            let level = fill ?? Double(state.level) / 100

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.45), lineWidth: lineWidth)
                    .frame(width: bodyWidth)
                RoundedRectangle(cornerRadius: max(radius - inset, 1), style: .continuous)
                    .fill(tint)
                    .frame(width: max((bodyWidth - inset * 2) * level, 0))
                    .padding(inset)
                if state.isPluggedIn {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: size.height * 0.62, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                        .frame(width: bodyWidth)
                }
                Capsule()
                    .fill(.white.opacity(0.45))
                    .frame(width: capWidth, height: size.height * 0.36)
                    .offset(x: bodyWidth + 1)
            }
            .frame(width: size.width, height: size.height, alignment: .leading)
        }
    }

    /// Green while plugged in, red at or below the critical threshold, orange when low, white otherwise.
    static func tint(for state: BatteryState?, low: Int, critical: Int) -> Color {
        guard let state else { return .white }
        if state.isPluggedIn { return .green }
        if state.level <= critical { return .red }
        if state.level <= low { return .orange }
        return .white
    }
}
