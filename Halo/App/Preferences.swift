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
    static let mediaWingsMode = "mediaWingsMode"
    static let lyricsEnabled = "lyricsEnabled"
    static let powerAlertsEnabled = "powerAlertsEnabled"
    static let lowBatteryAlertsEnabled = "lowBatteryAlertsEnabled"
    static let lowBatteryThreshold = "lowBatteryThreshold"
    static let criticalBatteryThreshold = "criticalBatteryThreshold"
    static let lowBatteryIndicator = "lowBatteryIndicator"
    /// Version that last asked for the Accessibility permission. Not a setting.
    static let accessibilityPromptedBuild = "accessibilityPromptedBuild"
    static let bluetoothAudioEnabled = "bluetoothAudioEnabled"
    static let bluetoothDisconnectAlertsEnabled = "bluetoothDisconnectAlertsEnabled"
    static let weatherEnabled = "weatherEnabled"
    static let temperatureUnit = "temperatureUnit"
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

/// When the compact island shows media around the notch, where it covers part of the menu bar.
enum MediaWingsMode: String, CaseIterable, Identifiable {
    case always
    /// Only when no menu bar item would be covered. Needs the Accessibility permission.
    case automatic
    case never

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
            PreferenceKey.mediaWingsMode: MediaWingsMode.always.rawValue,
            PreferenceKey.lyricsEnabled: true,
            PreferenceKey.powerAlertsEnabled: true,
            PreferenceKey.lowBatteryAlertsEnabled: true,
            PreferenceKey.lowBatteryThreshold: 20,
            PreferenceKey.criticalBatteryThreshold: 10,
            PreferenceKey.lowBatteryIndicator: true,
            PreferenceKey.bluetoothAudioEnabled: true,
            PreferenceKey.bluetoothDisconnectAlertsEnabled: true,
            PreferenceKey.weatherEnabled: true,
            PreferenceKey.temperatureUnit: TemperatureUnit.system.rawValue,
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

    static var mediaWingsMode: MediaWingsMode {
        MediaWingsMode(rawValue: UserDefaults.standard.string(forKey: PreferenceKey.mediaWingsMode) ?? "") ?? .always
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

    static var bluetoothAudioEnabled: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKey.bluetoothAudioEnabled)
    }

    static var bluetoothDisconnectAlertsEnabled: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKey.bluetoothDisconnectAlertsEnabled)
    }

    static var weatherEnabled: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKey.weatherEnabled)
    }

    static var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: PreferenceKey.temperatureUnit) ?? "") ?? .system
    }
}
