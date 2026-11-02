import SwiftUI

/// Temporary alert below the notch: power adapter connected or disconnected, or low battery.
struct BatteryAlertView: View {
    let event: BatteryEvent
    let battery: BatteryService

    /// Charge drawn by the glyph: grows from empty to the actual charge when the adapter is connected.
    @State private var fill: Double?

    var body: some View {
        if let state = battery.state {
            let tint = BatteryGlyph.tint(for: state, low: battery.lowThreshold, critical: battery.criticalThreshold)
            HStack(spacing: 14) {
                BatteryGlyph(state: state, tint: tint, fill: fill)
                    .frame(width: 46, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(state))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    if let detail = detail(state) {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(state.level, format: .percent)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .contentTransition(.numericText(value: Double(state.level)))
            }
            .frame(maxHeight: .infinity)
            .onAppear {
                guard event == .pluggedIn else { return }
                fill = 0
                withAnimation(.easeOut(duration: 1.1).delay(0.15)) {
                    fill = Double(state.level) / 100
                } completion: {
                    fill = nil
                }
            }
        }
    }

    private func title(_ state: BatteryState) -> LocalizedStringResource {
        switch event {
        case .pluggedIn:
            if state.isCharged || state.level >= 100 { return "Fully charged" }
            return state.isCharging ? "Charging" : "Plugged in"
        case .unplugged:
            return "On battery"
        case .low:
            return "Low battery"
        }
    }

    private func detail(_ state: BatteryState) -> LocalizedStringResource? {
        if let time = state.timeToFull {
            return "Full in \(Self.format(time))"
        }
        if let time = state.timeToEmpty {
            return "\(Self.format(time)) remaining"
        }
        switch event {
        case .pluggedIn where state.isPluggedIn && !state.isCharging && !state.isCharged && state.level < 100:
            return "Charging on hold"
        case .low:
            return "Connect your power adapter"
        default:
            return nil
        }
    }

    private static func format(_ time: TimeInterval) -> String {
        Duration.seconds(time).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
