import AppKit
import OSLog

/// Creates one island per eligible display and keeps them in sync with screens, Spaces and settings.
@MainActor
final class IslandManager {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Halo", category: "Island")
    private var controllers: [CGDirectDisplayID: IslandWindowController] = [:]
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var lastDisplayMode: DisplayMode?
    private var lastHideInFullScreen: Bool?
    private var fullScreenRecheck: Task<Void, Never>?

    func start() {
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { $0.rebuild() }
        observe(NotificationCenter.default, UserDefaults.didChangeNotification) { $0.preferencesChanged() }

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { $0.spaceChanged() }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { $0.spaceChanged() }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.rebuild() }

        lastDisplayMode = Preferences.displayMode
        lastHideInFullScreen = Preferences.hideInFullScreen
        rebuild()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping @Sendable @MainActor (IslandManager) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
        observers.append((center, token))
    }

    // MARK: - Displays

    private func eligibleScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        switch Preferences.displayMode {
        case .all:
            return screens
        case .main:
            return screens.first.map { [$0] } ?? []
        case .builtIn:
            if let builtIn = screens.first(where: \.isBuiltIn) {
                return [builtIn]
            }
            return screens.first.map { [$0] } ?? []
        }
    }

    private func rebuild() {
        var screensByID: [CGDirectDisplayID: NSScreen] = [:]
        for screen in eligibleScreens() {
            if let id = screen.displayID {
                screensByID[id] = screen
            }
        }

        for (id, controller) in controllers where screensByID[id] == nil {
            controller.close()
            controllers[id] = nil
        }
        for (id, screen) in screensByID {
            if let controller = controllers[id] {
                controller.update(screen: screen)
            } else {
                controllers[id] = IslandWindowController(screen: screen, displayID: id, services: .shared)
                let metrics = IslandMetrics(screen: screen)
                logger.info("""
                    Island on display \(id, privacy: .public): notch=\(metrics.hasNotch, privacy: .public) \
                    base=\(metrics.base.width, privacy: .public)x\(metrics.base.height, privacy: .public) \
                    centerX=\(metrics.centerX, privacy: .public)
                    """)
            }
        }
        updateFullScreenVisibility()
    }

    private func preferencesChanged() {
        let displayMode = Preferences.displayMode
        let hideInFullScreen = Preferences.hideInFullScreen
        if displayMode != lastDisplayMode {
            lastDisplayMode = displayMode
            rebuild()
        }
        if hideInFullScreen != lastHideInFullScreen {
            lastHideInFullScreen = hideInFullScreen
            updateFullScreenVisibility()
        }
    }

    // MARK: - Full screen

    private func spaceChanged() {
        updateFullScreenVisibility()
        // Windows may still be animating into (or out of) full screen: check once more after it settles.
        fullScreenRecheck?.cancel()
        fullScreenRecheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.updateFullScreenVisibility()
        }
    }

    private func updateFullScreenVisibility() {
        let fullScreenIDs = Preferences.hideInFullScreen ? FullScreenDetector.fullScreenDisplayIDs() : []
        for (id, controller) in controllers {
            controller.setHidden(fullScreenIDs.contains(id))
        }
        AppServices.shared.weather.islandIsVisible = controllers.keys.contains { !fullScreenIDs.contains($0) }
    }
}
