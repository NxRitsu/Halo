import SwiftUI

/// Temporary alert below the notch: an audio device connected or disconnected.
struct BluetoothAlertView: View {
    let event: BluetoothAudioEvent
    let bluetooth: BluetoothAudioService

    var body: some View {
        // Details are still arriving when the alert appears, so the live device takes over.
        let device = bluetooth.devices.first { $0.id == event.device.id } ?? event.device
        let isConnected = event.kind == .connected

        HStack(spacing: 12) {
            Image(systemName: device.symbol)
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(isConnected ? 1 : 0.5))
                .frame(width: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                detail(device, isConnected: isConnected)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if isConnected, !device.battery.isEmpty {
                BluetoothBatteryRow(battery: device.battery)
                    .transition(.opacity)
            }
        }
        .frame(maxHeight: .infinity)
        .animation(.easeOut(duration: 0.25), value: device)
    }

    @ViewBuilder
    private func detail(_ device: BluetoothAudioDevice, isConnected: Bool) -> some View {
        HStack(spacing: 5) {
            Text(isConnected ? "Connected" : "Disconnected")
            if isConnected, let volume = device.volume {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 9))
                    .padding(.leading, 3)
                Text(Double(volume) / 100, format: .percent)
                    .monospacedDigit()
            }
        }
    }
}

/// Charge of each part of a device, as small gauges.
struct BluetoothBatteryRow: View {
    let battery: BluetoothBattery

    var body: some View {
        HStack(spacing: 8) {
            if let left = battery.left {
                gauge(left) { Text("L", comment: "Left earbud") }
            }
            if let right = battery.right {
                gauge(right) { Text("R", comment: "Right earbud") }
            }
            if let chargingCase = battery.chargingCase {
                gauge(chargingCase) { Image(systemName: "airpods.chargingcase.fill").font(.system(size: 7)) }
            }
            if let single = battery.single {
                gauge(single) { Image(systemName: "bolt.fill").font(.system(size: 7)) }
            }
        }
    }

    private func gauge(_ level: Int, @ViewBuilder label: () -> some View) -> some View {
        let tint = Self.tint(for: level)
        return VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.15), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: CGFloat(level) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                label()
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(width: 22, height: 22)
            Text(level, format: .number)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    private static func tint(for level: Int) -> Color {
        switch level {
        case ...10: .red
        case ...20: .orange
        default: .green
        }
    }
}
