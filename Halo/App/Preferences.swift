import Foundation

/// UserDefaults keys and default values. Views read them through `@AppStorage`,
/// AppKit code through `Preferences`.
enum PreferenceKey {
    static let showMenuBarIcon = "showMenuBarIcon"
    static let displayMode = "displayMode"
    static let expandOnHover = "expandOnHover"
    static let hoverDelay = "hoverDelay"
    static let hideInFullScreen = "hideInFullScreen"
    static let nowPlayingEnabled = "nowPlayingEnabled"
    static let mediaWingsEnabled = "mediaWingsEnabled"
    static let lyricsEnabled = "lyricsEnabled"
    static let powerAlertsEnabled = "powerAlertsEnabled"
    static let lowBatteryAlertsEnabled = "lowBatteryAlertsEnabled"
    static let lowBatteryThreshold = "lowBatteryThreshold"
    static let criticalBatteryThreshold = "criticalBatteryThreshold"
    static let lowBatteryIndicator = "lowBatteryIndicator"
}

/// Which displays show an island.
enum DisplayMode: String, CaseIterable, Identifiable {
    /// The built-in display (the one with the notch), or the main display when it is closed.
    case builtIn
    /// The main display only (the one with the menu bar).
    case main
    /// Every connected display.
    case all

    var id: String { rawValue }
}

enum Preferences {
    static var defaults: [String: Any] {
        [
            PreferenceKey.showMenuBarIcon: true,
            PreferenceKey.displayMode: DisplayMode.builtIn.rawValue,
            PreferenceKey.expandOnHover: true,
            PreferenceKey.hoverDelay: 0.15,
            PreferenceKey.hideInFullScreen: true,
            PreferenceKey.nowPlayingEnabled: true,
            PreferenceKey.mediaWingsEnabled: true,
            PreferenceKey.lyricsEnabled: true,
            PreferenceKey.powerAlertsEnabled: true,
            PreferenceKey.lowBatteryAlertsEnabled: true,
            PreferenceKey.lowBatteryThreshold: 20,
            PreferenceKey.criticalBatteryThreshold: 10,
            PreferenceKey.lowBatteryIndicator: true,
        ]
    }

    static func register() {
        UserDefaults.standard.register(defaults: defaults)
    }

    static var displayMode: DisplayMode {
        DisplayMode(rawValue: UserDefaults.standard.string(forKey: PreferenceKey.displayMode) ?? "") ?? .builtIn
    }

    static var expandOnHover: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKey.expandOnHover)
    }

    static var hoverDelay: Double {
        UserDefaults.standard.double(forKey: PreferenceKey.hoverDelay)
    }

    static var hideInFullScreen: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKey.hideInFullScreen)
    }

    static var nowPlayingEnabled: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKey.nowPlayingEnabled)
    }

    static var mediaWingsEnabled: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKey.mediaWingsEnabled)
    }

    static var lyricsEnabled: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKey.lyricsEnabled)
    }

    static var powerAlertsEnabled: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKey.powerAlertsEnabled)
    }

    static var lowBatteryAlertsEnabled: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKey.lowBatteryAlertsEnabled)
    }

    static var lowBatteryThreshold: Int {
        UserDefaults.standard.integer(forKey: PreferenceKey.lowBatteryThreshold)
    }

    static var criticalBatteryThreshold: Int {
        UserDefaults.standard.integer(forKey: PreferenceKey.criticalBatteryThreshold)
    }

    static var lowBatteryIndicator: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKey.lowBatteryIndicator)
    }
}
