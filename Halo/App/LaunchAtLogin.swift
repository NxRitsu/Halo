import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp` to register Halo as a login item.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var isEnabled = false
    private(set) var requiresApproval = false
    private(set) var errorMessage: String?

    init() {
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        requiresApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }
}
