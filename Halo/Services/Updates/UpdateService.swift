import Foundation
import OSLog
import Sparkle

/// Checks for and installs new versions with Sparkle.
///
/// Sparkle asks for consent on the second launch before checking automatically. Only the request
/// for the appcast and, if there's an update, its download reach GitHub: no system profile is sent.
/// Development builds don't start the updater, so they are never replaced by a release.
@MainActor
@Observable
final class UpdateService: NSObject {
    enum Status: Equatable {
        case disabledInDevelopment
        case ready
        case failed(String)
    }

    private(set) var status = Status.disabledInDevelopment
    private(set) var canCheck = false
    private(set) var lastCheck: Date?

    var checksAutomatically: Bool {
        get {
            access(keyPath: \.checksAutomatically)
            return controller?.updater.automaticallyChecksForUpdates ?? false
        }
        set {
            withMutation(keyPath: \.checksAutomatically) {
                controller?.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Halo", category: "Updates")

    func start() {
        #if !DEBUG
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        do {
            try controller.updater.start()
            status = .ready
            observeUpdater(controller.updater)
        } catch {
            logger.error("Couldn't start the updater: \(error.localizedDescription, privacy: .public)")
            status = .failed(error.localizedDescription)
        }
        #endif
    }

    func checkForUpdates() {
        controller?.updater.checkForUpdates()
    }

    /// Sparkle changes these on the main thread, including when the user answers its consent prompt.
    private func observeUpdater(_ updater: SPUUpdater) {
        canCheck = updater.canCheckForUpdates
        lastCheck = updater.lastUpdateCheckDate
        observations = [
            updater.observe(\.canCheckForUpdates) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self, let updater = self.controller?.updater else { return }
                    self.canCheck = updater.canCheckForUpdates
                    self.lastCheck = updater.lastUpdateCheckDate
                }
            },
            updater.observe(\.automaticallyChecksForUpdates) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    self?.withMutation(keyPath: \.checksAutomatically) {}
                }
            },
        ]
    }
}

extension UpdateService: SPUStandardUserDriverDelegate {
    /// Halo has no Dock icon, so Sparkle needs to know that a scheduled update shouldn't steal
    /// focus: it shows the window behind the active app instead.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}
