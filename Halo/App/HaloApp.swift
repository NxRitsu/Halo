import SwiftUI

@main
struct HaloApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(PreferenceKey.showMenuBarIcon) private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            Button("Settings…") {
                SettingsWindowController.shared.show()
            }
            .keyboardShortcut(",")
            Divider()
            Button("Quit \(AppInfo.name)") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: "capsule.fill")
        }
    }
}
