import Foundation
import IOKit.ps
import OSLog

/// Charge level and power source of the internal battery.
struct BatteryState: Equatable {
    /// Charge, from 0 to 100.
    var level: Int
    /// Whether the Mac is connected to a power adapter.
    var isPluggedIn: Bool
    /// Plugged in and actually charging (macOS may hold the charge, for instance at 80 %).
    var isCharging: Bool
    var isCharged: Bool
    /// Estimated time until the battery is empty, when on battery and macOS has an estimate.
    var timeToEmpty: TimeInterval?
    /// Estimated time until the battery is full, while charging and macOS has an estimate.
    var timeToFull: TimeInterval?
}

/// Something worth a temporary alert on the island.
enum BatteryEvent: Equatable {
    case pluggedIn
    case unplugged
    /// The charge dropped to or below one of the low battery thresholds, while on battery.
    case low(threshold: Int)
}

/// Follows the internal battery through IOKit power source notifications. No polling: macOS
/// calls back whenever the charge, the power source or the time estimates change.
///
/// On Macs without a battery, `state` stays nil and no event is ever sent.
@MainActor
@Observable
final class BatteryService {
    private(set) var state: BatteryState?

    /// Charge at or below which the charge counts as low (alert and compact indicator).
    var lowThreshold = 20 {
        didSet { resetLowAlerts() }
    }
    /// Second, lower threshold that alerts again.
    var criticalThreshold = 10 {
        didSet { resetLowAlerts() }
    }

    /// Whether the charge is low and the Mac is on battery.
    var isLow: Bool {
        guard let state, !state.isPluggedIn else { return false }
        return state.level <= lowThreshold
    }

    /// Called on the main actor for each plug, unplug and low battery threshold crossing.
    @ObservationIgnored var onEvent: (BatteryEvent) -> Void = { _ in }

    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    /// Lowest threshold already alerted since the Mac was last unplugged, so each one alerts once.
    @ObservationIgnored private var lowestAlertedThreshold: Int?
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Halo", category: "Battery")

    init() {
        state = Self.readState()
        resetLowAlerts()
        #if DEBUG
        if ProcessInfo.processInfo.environment["HALO_SIMULATE_BATTERY_DRAIN"] != nil {
            simulateDrain()
            return
        }
        #endif
        startNotifications()
    }

    #if DEBUG
    /// Drains a fake battery from 23 % to 5 %, one percent per second, then plugs it in,
    /// to test the low battery alerts and indicator without waiting for the real battery.
    private func simulateDrain() {
        state = BatteryState(level: 23, isPluggedIn: false, isCharging: false, isCharged: false, timeToEmpty: 50 * 60)
        resetLowAlerts()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            for level in stride(from: 22, through: 5, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                self?.apply(BatteryState(
                    level: level, isPluggedIn: false, isCharging: false, isCharged: false,
                    timeToEmpty: TimeInterval(level * 130)
                ))
            }
            try? await Task.sleep(for: .seconds(4))
            self?.apply(BatteryState(level: 5, isPluggedIn: true, isCharging: true, isCharged: false, timeToFull: 95 * 60))
        }
    }
    #endif

    private func startNotifications() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        // The callback runs on the run loop the source is added to: the main one.
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue().powerSourcesChanged()
            }
        }, context)?.takeRetainedValue() else {
            logger.error("Power source notifications are unavailable")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }

    private func powerSourcesChanged() {
        apply(Self.readState())
    }

    private func apply(_ current: BatteryState?) {
        let previous = state
        guard current != previous else { return }
        state = current
        guard let previous, let current else { return }

        if current.isPluggedIn != previous.isPluggedIn {
            if current.isPluggedIn {
                lowestAlertedThreshold = nil
                onEvent(.pluggedIn)
            } else {
                // Thresholds already below the charge must not alert right after unplugging.
                resetLowAlerts()
                onEvent(.unplugged)
            }
            return
        }

        guard !current.isPluggedIn, current.level < previous.level else { return }
        // The lowest threshold crossed, if it hasn't alerted yet.
        let crossed = [criticalThreshold, lowThreshold]
            .sorted()
            .first { current.level <= $0 && previous.level > $0 }
        if let crossed, crossed < (lowestAlertedThreshold ?? .max) {
            lowestAlertedThreshold = crossed
            onEvent(.low(threshold: crossed))
        }
    }

    /// Marks the thresholds that are already at or above the current charge as alerted.
    private func resetLowAlerts() {
        guard let state, !state.isPluggedIn else {
            lowestAlertedThreshold = nil
            return
        }
        lowestAlertedThreshold = [criticalThreshold, lowThreshold].sorted().first { state.level <= $0 }
    }

    // MARK: - Reading

    private static func readState() -> BatteryState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  description[kIOPSIsPresentKey] as? Bool ?? true,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { continue }

            let isPluggedIn = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            return BatteryState(
                level: min(max(current * 100 / maximum, 0), 100),
                isPluggedIn: isPluggedIn,
                isCharging: isPluggedIn && isCharging,
                isCharged: description[kIOPSIsChargedKey] as? Bool ?? false,
                timeToEmpty: isPluggedIn ? nil : minutes(description[kIOPSTimeToEmptyKey]),
                timeToFull: isCharging ? minutes(description[kIOPSTimeToFullChargeKey]) : nil
            )
        }
        return nil
    }

    /// IOKit gives estimates in minutes, and -1 while it is still computing them.
    private static func minutes(_ value: Any?) -> TimeInterval? {
        guard let minutes = value as? Int, minutes > 0 else { return nil }
        return TimeInterval(minutes * 60)
    }
}
