import AppKit
import SwiftUI

/// Hosts the settings in a regular window.
///
/// The SwiftUI `Settings` scene cannot be opened reliably from an agent app (no Dock icon,
/// no app menu), so the window is managed here and opened from the island or the menu bar.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        window.title = String(localized: "\(AppInfo.name) Settings")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
