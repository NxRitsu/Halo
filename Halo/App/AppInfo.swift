import AppKit

/// Single source of truth for the app's identity at runtime.
/// The name itself is defined once, as `APP_NAME` in `project.yml`.
enum AppInfo {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Halo"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    static let repositoryURL = URL(string: "https://github.com/NxRitsu/Halo")!

    /// Quits and opens the app again, once this instance is gone. A running app doesn't notice that
    /// it was just given the Accessibility permission.
    @MainActor
    static func relaunch() {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        guard (try? shell.run()) != nil else { return }
        NSApp.terminate(nil)
    }
}
