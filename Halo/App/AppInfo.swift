import Foundation

/// Single source of truth for the app's identity at runtime.
/// The name itself is defined once, as `APP_NAME` in `project.yml`.
enum AppInfo {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Halo"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    static let repositoryURL = URL(string: "https://github.com/NxRitsu/Halo")!
}
