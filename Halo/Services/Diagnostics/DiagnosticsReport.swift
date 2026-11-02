import AppKit

/// State of one part of Halo, for the Diagnostics tab and its report.
struct ServiceStatus: Identifiable {
    enum Level {
        case ok, neutral, warning, failure
    }

    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let level: Level
    /// Name and state in the report, always in English so that anyone can read reports.
    let reportName: String
    let reportValue: String

    var id: String { reportName }
}

/// Builds the report that people paste in bug reports. Nothing here is ever sent anywhere.
///
/// It must stay free of personal data: no track or artist, no name of the playing app, no file
/// path, no location, no name of a device or of the Mac.
@MainActor
enum DiagnosticsReport {
    static func services() -> [ServiceStatus] {
        let services = AppServices.shared
        return [
            nowPlayingStatus(services.nowPlaying),
            lyricsStatus(services.lyrics),
            batteryStatus(services.battery),
            menuBarStatus(services.menuBar),
            updatesStatus(services.updates),
            bluetoothStatus(services.bluetooth),
            ServiceStatus(
                title: "Location", detail: "Planned for a later version", level: .neutral,
                reportName: "Location", reportValue: "not used by this version"
            ),
        ]
    }

    static func text(app: ProcessUsage?, helper: ProcessUsage?) -> String {
        var lines = [
            "\(AppInfo.name) \(AppInfo.version) (\(AppInfo.build)), \(buildConfiguration)",
            "macOS \(macOSVersion), \(architecture), \(macModel)",
            "Language: \(Bundle.main.preferredLocalizations.first ?? "unknown")",
            "Displays: \(displays)",
            "",
            "Usage",
            "- CPU: \(cpuText(app?.cpu))",
            "- Memory: \(memoryText(app?.memory)), peak \(memoryText(app?.peakMemory))",
        ]
        if let helper {
            lines.append("- Media helper: CPU \(cpuText(helper.cpu)), memory \(memoryText(helper.memory))")
        }
        lines += ["", "Services"]
        lines += services().map { "- \($0.reportName): \($0.reportValue)" }
        lines += ["", "Settings"]
        lines += settings.map { "- \($0.name): \($0.value)" }
        return lines.joined(separator: "\n")
    }

    // MARK: - Services

    private static func nowPlayingStatus(_ nowPlaying: NowPlayingService) -> ServiceStatus {
        let title: LocalizedStringResource = "Now playing"
        let name = "Now playing"
        var session = ""
        if nowPlaying.track != nil {
            session = nowPlaying.isControllable ? ", media session open" : ", media session open, controls disabled"
        }
        switch nowPlaying.status {
        case .disabled:
            return ServiceStatus(title: title, detail: "Disabled", level: .neutral, reportName: name, reportValue: "disabled")
        case .starting:
            return ServiceStatus(title: title, detail: "Starting…", level: .neutral, reportName: name, reportValue: "starting")
        case .active(.mediaRemoteDirect):
            return ServiceStatus(title: title, detail: "MediaRemote (direct)", level: .ok, reportName: name, reportValue: "MediaRemote, direct\(session)")
        case .active(.mediaRemoteHelper):
            return ServiceStatus(title: title, detail: "MediaRemote (via system process)", level: .ok, reportName: name, reportValue: "MediaRemote, helper process\(session)")
        case .active(.scripting):
            return ServiceStatus(title: title, detail: "Music and Spotify only", level: .warning, reportName: name, reportValue: "fallback to Music and Spotify\(session)")
        case .unavailable(let reason):
            return ServiceStatus(title: title, detail: "Unavailable: \(reason)", level: .failure, reportName: name, reportValue: "unavailable: \(anonymized(reason))")
        }
    }

    private static func lyricsStatus(_ lyrics: LyricsService) -> ServiceStatus {
        let title: LocalizedStringResource = "Lyrics"
        let name = "Lyrics"
        switch lyrics.status {
        case .disabled:
            return ServiceStatus(title: title, detail: "Disabled", level: .neutral, reportName: name, reportValue: "disabled")
        case .idle:
            return ServiceStatus(title: title, detail: "Nothing playing", level: .neutral, reportName: name, reportValue: "idle")
        case .searching:
            return ServiceStatus(title: title, detail: "Searching…", level: .neutral, reportName: name, reportValue: "searching")
        case .found:
            return ServiceStatus(title: title, detail: "Synced lyrics found", level: .ok, reportName: name, reportValue: "found")
        case .instrumental:
            return ServiceStatus(title: title, detail: "Instrumental", level: .neutral, reportName: name, reportValue: "instrumental")
        case .notFound:
            return ServiceStatus(title: title, detail: "No synced lyrics for this track", level: .neutral, reportName: name, reportValue: "not found")
        case .unavailable(let retryAt):
            let time = retryAt.formatted(date: .omitted, time: .shortened)
            return ServiceStatus(title: title, detail: "LRCLIB is unavailable, next try at \(time)", level: .warning, reportName: name, reportValue: "LRCLIB unavailable, backing off")
        }
    }

    private static func bluetoothStatus(_ bluetooth: BluetoothAudioService) -> ServiceStatus {
        let title: LocalizedStringResource = "Bluetooth"
        let name = "Bluetooth"
        switch bluetooth.status {
        case .disabled:
            return ServiceStatus(title: title, detail: "Disabled", level: .neutral, reportName: name, reportValue: "disabled")
        case .starting:
            return ServiceStatus(title: title, detail: "Starting…", level: .neutral, reportName: name, reportValue: "starting")
        case .poweredOff:
            return ServiceStatus(title: title, detail: "Bluetooth is turned off", level: .neutral, reportName: name, reportValue: "turned off")
        case .denied:
            return ServiceStatus(title: title, detail: "Not allowed", level: .warning, reportName: name, reportValue: "permission denied")
        case .unsupported:
            return ServiceStatus(title: title, detail: "Not supported on this Mac", level: .neutral, reportName: name, reportValue: "not supported")
        case .active where bluetooth.canReadBatteries:
            return ServiceStatus(title: title, detail: "Working", level: .ok, reportName: name, reportValue: "working, \(bluetooth.devices.count) audio device(s) connected")
        case .active:
            return ServiceStatus(title: title, detail: "Working, without battery levels", level: .warning, reportName: name, reportValue: "working, battery properties unavailable, \(bluetooth.devices.count) audio device(s) connected")
        }
    }

    private static func batteryStatus(_ battery: BatteryService) -> ServiceStatus {
        guard let state = battery.state else {
            return ServiceStatus(title: "Battery", detail: "No battery", level: .neutral, reportName: "Battery", reportValue: "none")
        }
        return ServiceStatus(
            title: "Battery", detail: "Detected", level: .ok,
            reportName: "Battery", reportValue: state.isPluggedIn ? "detected, plugged in" : "detected, on battery"
        )
    }

    /// The permission only matters to the mode that measures the menu bar.
    private static func menuBarStatus(_ menuBar: MenuBarSpaceMonitor) -> ServiceStatus {
        let isNeeded = Preferences.mediaWingsMode == .automatic
        let title: LocalizedStringResource = "Menu bar access"
        let name = "Accessibility permission"
        if menuBar.isTrusted {
            return ServiceStatus(title: title, detail: "Allowed", level: isNeeded ? .ok : .neutral, reportName: name, reportValue: "allowed")
        }
        return ServiceStatus(title: title, detail: "Not allowed", level: isNeeded ? .warning : .neutral, reportName: name, reportValue: "not allowed")
    }

    private static func updatesStatus(_ updates: UpdateService) -> ServiceStatus {
        let title: LocalizedStringResource = "Updates"
        let name = "Updates"
        switch updates.status {
        case .disabledInDevelopment:
            return ServiceStatus(title: title, detail: "Turned off in development builds", level: .neutral, reportName: name, reportValue: "turned off in development builds")
        case .ready:
            return ServiceStatus(title: title, detail: "Working", level: .ok, reportName: name, reportValue: updates.checksAutomatically ? "working, automatic checks" : "working, manual checks")
        case .failed(let reason):
            return ServiceStatus(title: title, detail: "Unavailable: \(reason)", level: .failure, reportName: name, reportValue: "unavailable: \(anonymized(reason))")
        }
    }

    // MARK: - Report details

    private static var settings: [(name: String, value: String)] {
        [
            ("Show the island on", Preferences.displayMode.rawValue),
            ("Hide in full screen", onOff(Preferences.hideInFullScreen)),
            ("Expand on hover", onOff(Preferences.expandOnHover)),
            ("Playback around the notch", Preferences.mediaWingsMode.rawValue),
            ("Now playing", onOff(Preferences.nowPlayingEnabled)),
            ("Lyrics", onOff(Preferences.lyricsEnabled)),
            ("Power alerts", onOff(Preferences.powerAlertsEnabled)),
            ("Low battery alerts", onOff(Preferences.lowBatteryAlertsEnabled)),
            ("Bluetooth audio alerts", onOff(Preferences.bluetoothAudioEnabled)),
            ("Bluetooth disconnection alerts", onOff(Preferences.bluetoothDisconnectAlertsEnabled)),
        ]
    }

    private static func onOff(_ value: Bool) -> String {
        value ? "on" : "off"
    }

    private static var buildConfiguration: String {
        #if DEBUG
        "debug build"
        #else
        "release build"
        #endif
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }

    /// `operatingSystemVersionString` is translated, while reports stay in English.
    private static var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let number = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        return systemValue("kern.osversion").map { "\(number) (\($0))" } ?? number
    }

    /// Model identifier such as "Mac14,9". It is shared by every Mac of that model.
    private static var macModel: String {
        systemValue("hw.model") ?? "unknown model"
    }

    private static func systemValue(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }

    private static var displays: String {
        NSScreen.screens.map { screen in
            let notch = screen.safeAreaInsets.top > 0 ? ", notch" : ""
            return "\(Int(screen.frame.width))x\(Int(screen.frame.height)) @\(Int(screen.backingScaleFactor))x\(notch)"
        }
        .joined(separator: "; ")
    }

    private static func cpuText(_ cpu: Double?) -> String {
        cpu.map { String(format: "%.1f %%", $0 * 100) } ?? "not measured yet"
    }

    private static func memoryText(_ memory: UInt64?) -> String {
        memory.map { String(format: "%.1f MB", Double($0) / 1_048_576) } ?? "not measured yet"
    }

    /// Error messages may quote a file path, which would reveal the user name.
    private static func anonymized(_ text: String) -> String {
        text.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
