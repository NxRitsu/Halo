import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let islandManager = IslandManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.register()
        AppServices.shared.start()
        islandManager.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Launching the app again (Finder, Spotlight) opens the settings, since there is no Dock icon.
        SettingsWindowController.shared.show()
        return false
    }
}
