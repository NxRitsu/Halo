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
        }
        .tabViewStyle(.sidebarAdaptable)
        .frame(width: 520, height: 360)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage(PreferenceKey.showMenuBarIcon) private var showMenuBarIcon = true
    @State private var launchAtLogin = LaunchAtLogin()

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
}

private struct IslandSettingsView: View {
    @AppStorage(PreferenceKey.displayMode) private var displayMode = DisplayMode.builtIn
    @AppStorage(PreferenceKey.expandOnHover) private var expandOnHover = true
    @AppStorage(PreferenceKey.hoverDelay) private var hoverDelay = 0.15
    @AppStorage(PreferenceKey.hideInFullScreen) private var hideInFullScreen = true

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
        }
        .formStyle(.grouped)
    }
}
