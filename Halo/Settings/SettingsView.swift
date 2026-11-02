import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView()
            }
            Tab("Island", systemImage: "capsule") {
                IslandSettingsView()
            }
            Tab("Media", systemImage: "music.note") {
                MediaSettingsView()
            }
            Tab("Lyrics", systemImage: "quote.bubble") {
                LyricsSettingsView()
            }
            Tab("Devices", systemImage: "laptopcomputer") {
                DevicesSettingsView()
            }
            Tab("Diagnostics", systemImage: "stethoscope") {
                DiagnosticsSettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .frame(width: 520, height: 360)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage(PreferenceKey.showMenuBarIcon) private var showMenuBarIcon = true
    @State private var launchAtLogin = LaunchAtLogin()
    private let updates = AppServices.shared.updates

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                if launchAtLogin.requiresApproval {
                    Text("Allow \(AppInfo.name) in System Settings → General → Login Items & Extensions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = launchAtLogin.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section {
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
            } footer: {
                Text("You can always right-click the island to open the settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updates.checksAutomatically },
                    set: { updates.checksAutomatically = $0 }
                ))
                LabeledContent {
                    Button("Check for Updates…") {
                        updates.checkForUpdates()
                    }
                    .disabled(!updates.canCheck)
                } label: {
                    Text("Last check")
                    if let lastCheck = updates.lastCheck {
                        Text(lastCheck, format: .dateTime)
                    } else {
                        Text("Never")
                    }
                }
            } footer: {
                updatesFooter
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(updates.status != .ready)
            Section {
                LabeledContent("Version", value: "\(AppInfo.version) (\(AppInfo.build))")
                HStack {
                    Link("Project on GitHub", destination: AppInfo.repositoryURL)
                    Spacer()
                    Button("Quit \(AppInfo.name)") {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin.refresh() }
    }

    @ViewBuilder
    private var updatesFooter: some View {
        switch updates.status {
        case .disabledInDevelopment:
            Text("Updates are turned off in development builds.")
        case .ready:
            Text("Update checks only contact GitHub, where \(AppInfo.name) is published.")
        case .failed(let reason):
            Text("Updates are unavailable: \(reason)")
        }
    }
}

private struct IslandSettingsView: View {
    @AppStorage(PreferenceKey.displayMode) private var displayMode = DisplayMode.builtIn
    @AppStorage(PreferenceKey.expandOnHover) private var expandOnHover = true
    @AppStorage(PreferenceKey.hoverDelay) private var hoverDelay = 0.15
    @AppStorage(PreferenceKey.hideInFullScreen) private var hideInFullScreen = true
    @AppStorage(PreferenceKey.mediaWingsMode) private var mediaWingsMode = MediaWingsMode.always
    private let activities = AppServices.shared.activities
    private let menuBar = AppServices.shared.menuBar

    var body: some View {
        Form {
            Section {
                Picker("Show the island on", selection: $displayMode) {
                    Text("Built-in display").tag(DisplayMode.builtIn)
                    Text("Main display").tag(DisplayMode.main)
                    Text("All displays").tag(DisplayMode.all)
                }
                Toggle("Hide in full screen", isOn: $hideInFullScreen)
            } footer: {
                Text("On displays without a notch, a virtual island is shown at the top of the screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Expand on hover", isOn: $expandOnHover)
                LabeledContent("Hover delay") {
                    HStack {
                        Slider(value: $hoverDelay, in: 0...1, step: 0.05)
                        Text(hoverDelay, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                        Text("s")
                    }
                }
                .disabled(!expandOnHover)
            }
            Section {
                Picker("Show playback around the notch", selection: $mediaWingsMode) {
                    Text("Always").tag(MediaWingsMode.always)
                    Text("When there's room").tag(MediaWingsMode.automatic)
                    Text("Never").tag(MediaWingsMode.never)
                }
                if mediaWingsMode == .automatic, !menuBar.isTrusted {
                    LabeledContent {
                        HStack {
                            Button("Open System Settings") {
                                menuBar.openAccessSettings()
                            }
                            Button("Reopen \(AppInfo.name)") {
                                AppInfo.relaunch()
                            }
                        }
                    } label: {
                        Label("Permission required", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Turn on \(AppInfo.name) in System Settings to measure the menu bar, then reopen it. If it's already on, remove it from the list and add it back. Until then, playback is always shown.")
                    }
                }
            } footer: {
                Text("“When there's room” keeps the island at the size of the notch, low battery indicator included, whenever it would cover menu bar items. It uses the Accessibility permission to read the position of these items, nothing else. The player stays available by expanding the island.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { menuBar.refreshAccess() }
        .onChange(of: mediaWingsMode) { _, mode in
            activities.mediaWingsMode = mode
            if mode == .automatic {
                menuBar.requestAccess()
            }
        }
    }
}

private struct MediaSettingsView: View {
    @AppStorage(PreferenceKey.nowPlayingEnabled) private var nowPlayingEnabled = true
    private let nowPlaying = AppServices.shared.nowPlaying

    var body: some View {
        Form {
            Section {
                Toggle("Show what's playing", isOn: $nowPlayingEnabled)
                LabeledContent("Source") {
                    statusText
                }
            } footer: {
                Text("macOS restricts access to what's playing. Halo reads it through a system process (/usr/bin/perl), or falls back to Music and Spotify only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: nowPlayingEnabled) { _, enabled in
            nowPlaying.setEnabled(enabled)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch nowPlaying.status {
        case .disabled:
            Text("Disabled")
        case .starting:
            Text("Starting…")
        case .active(.mediaRemoteDirect):
            Label("MediaRemote (direct)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .active(.mediaRemoteHelper):
            Label("MediaRemote (via system process)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .active(.scripting):
            Label("Music and Spotify only", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .unavailable(let reason):
            Label("Unavailable: \(reason)", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }
}

private struct LyricsSettingsView: View {
    @AppStorage(PreferenceKey.lyricsEnabled) private var lyricsEnabled = true
    @State private var cacheCleared = false
    private let lyrics = AppServices.shared.lyrics

    var body: some View {
        Form {
            Section {
                Toggle("Show synced lyrics", isOn: $lyricsEnabled)
                LabeledContent("Current track") {
                    statusText
                }
            } footer: {
                Text("Lyrics come from LRCLIB, a free community database. Only the title, artist, album and duration of the track are sent. Results are kept on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Saved lyrics") {
                    Button(cacheCleared ? "Cleared" : "Clear") {
                        lyrics.clearCache()
                        cacheCleared = true
                    }
                    .disabled(cacheCleared)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: lyricsEnabled) { _, enabled in
            lyrics.setEnabled(enabled)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch lyrics.status {
        case .disabled:
            Text("Disabled")
        case .idle:
            Text("Nothing playing")
        case .searching:
            Text("Searching…")
        case .found:
            Label("Synced lyrics found", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .instrumental:
            Text("Instrumental")
        case .notFound:
            Text("No synced lyrics for this track")
        case .unavailable(let retryAt):
            Label("LRCLIB is unavailable, next try at \(retryAt.formatted(date: .omitted, time: .shortened))", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

private struct DevicesSettingsView: View {
    @AppStorage(PreferenceKey.powerAlertsEnabled) private var powerAlertsEnabled = true
    @AppStorage(PreferenceKey.lowBatteryAlertsEnabled) private var lowBatteryAlertsEnabled = true
    @AppStorage(PreferenceKey.lowBatteryThreshold) private var lowThreshold = 20
    @AppStorage(PreferenceKey.criticalBatteryThreshold) private var criticalThreshold = 10
    @AppStorage(PreferenceKey.lowBatteryIndicator) private var lowBatteryIndicator = true
    @AppStorage(PreferenceKey.bluetoothAudioEnabled) private var bluetoothAudioEnabled = true
    @AppStorage(PreferenceKey.bluetoothDisconnectAlertsEnabled) private var bluetoothDisconnectAlertsEnabled = true
    private let battery = AppServices.shared.battery
    private let activities = AppServices.shared.activities
    private let bluetooth = AppServices.shared.bluetooth

    var body: some View {
        Form {
            Section("Battery") {
                if let state = battery.state {
                    LabeledContent("Charge") {
                        Text(state.level, format: .percent)
                            .monospacedDigit()
                    }
                    Toggle("Alert when the power adapter is connected or disconnected", isOn: $powerAlertsEnabled)
                    Toggle("Alert when the battery is low", isOn: $lowBatteryAlertsEnabled)
                    Stepper(value: $lowThreshold, in: 10...50, step: 5) {
                        LabeledContent("Low battery", value: lowThreshold, format: .percent)
                    }
                    Stepper(value: $criticalThreshold, in: 5...(lowThreshold - 5), step: 5) {
                        LabeledContent("Very low battery", value: criticalThreshold, format: .percent)
                    }
                    .disabled(!lowBatteryAlertsEnabled)
                    Toggle("Show the charge on the island when the battery is low", isOn: $lowBatteryIndicator)
                } else {
                    Text("This Mac has no battery.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Alert when an audio device connects", isOn: $bluetoothAudioEnabled)
                Toggle("Also alert when it disconnects", isOn: $bluetoothDisconnectAlertsEnabled)
                    .disabled(!bluetoothAudioEnabled)
                bluetoothStatusRow
                ForEach(bluetooth.devices) { device in
                    BluetoothDeviceRow(device: device, bluetooth: bluetooth)
                }
            } header: {
                Text("Bluetooth audio")
            } footer: {
                Text("Battery levels and listening modes come from private system properties, so they may be missing on some devices or versions of macOS. Nothing leaves your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task(id: bluetooth.status) {
            guard bluetooth.status == .active else { return }
            await bluetooth.monitor()
        }
        .onChange(of: bluetoothAudioEnabled) { _, enabled in
            bluetooth.setEnabled(enabled)
        }
        .onChange(of: lowThreshold) { _, threshold in
            if criticalThreshold >= threshold {
                criticalThreshold = threshold - 5
            }
            battery.lowThreshold = threshold
        }
        .onChange(of: criticalThreshold) { _, threshold in
            battery.criticalThreshold = threshold
        }
        .onChange(of: lowBatteryIndicator) { _, shows in
            activities.showsLowBatteryIndicator = shows
        }
    }

    @ViewBuilder
    private var bluetoothStatusRow: some View {
        switch bluetooth.status {
        case .disabled:
            EmptyView()
        case .starting:
            LabeledContent("Status") { Text("Starting…") }
        case .poweredOff:
            LabeledContent("Status") { Text("Bluetooth is turned off") }
        case .unsupported:
            LabeledContent("Status") { Text("Not supported on this Mac") }
        case .denied:
            LabeledContent {
                Button("Open System Settings") {
                    bluetooth.openPrivacySettings()
                }
            } label: {
                Label("Permission required", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Allow \(AppInfo.name) under Privacy & Security → Bluetooth to detect your audio devices.")
            }
        case .active:
            if bluetooth.devices.isEmpty {
                LabeledContent("Status") { Text("No audio device connected") }
            }
        }
    }
}

/// A connected device: battery, volume and, on AirPods that report it, the listening mode.
private struct BluetoothDeviceRow: View {
    let device: BluetoothAudioDevice
    let bluetooth: BluetoothAudioService

    var body: some View {
        LabeledContent {
            if !device.battery.isEmpty {
                BluetoothBatteryRow(battery: device.battery)
                    .environment(\.colorScheme, .dark)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black, in: .rect(cornerRadius: 8))
            } else if !bluetooth.canReadBatteries {
                Text("Battery level unavailable")
            }
        } label: {
            Label(device.name, systemImage: device.symbol)
            if let volume = device.volume {
                Text("Volume \(Text(Double(volume) / 100, format: .percent))")
            }
        }
        if let mode = device.listeningMode, !device.supportedListeningModes.isEmpty {
            Picker("Listening mode (experimental)", selection: Binding(
                get: { mode },
                set: { bluetooth.setListeningMode($0, for: device.id) }
            )) {
                ForEach(device.supportedListeningModes) { mode in
                    Text(mode.title).tag(mode)
                }
            }
        }
    }
}

private extension ListeningMode {
    var title: LocalizedStringResource {
        switch self {
        case .off: "Off"
        case .noiseCancellation: "Noise Cancellation"
        case .transparency: "Transparency"
        case .adaptive: "Adaptive"
        }
    }
}
