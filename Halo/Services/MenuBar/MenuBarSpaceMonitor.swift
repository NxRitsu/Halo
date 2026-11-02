import AppKit
import ApplicationServices
import OSLog

/// Tells whether the compact wings would cover items of the menu bar.
///
/// macOS has no API for the free space around the notch, so this reads the position of the menus
/// of the frontmost app and of the status items through the Accessibility API. Reads only happen
/// after an event (app activation, display change, permission change), never on a timer, and only
/// while the automatic mode is selected. Only positions are used, never titles or contents.
///
/// Without the permission, `wingsCoverMenus` stays false: the wings behave as if there were room.
@MainActor
@Observable
final class MenuBarSpaceMonitor {
    private(set) var isTrusted = AXIsProcessTrusted()
    private(set) var wingsCoverMenus = false

    /// Apps build or update their menus just after activating, so each event reads a few times.
    private static let readDelays: [Duration] = [.zero, .milliseconds(400), .milliseconds(1500)]

    @ObservationIgnored private var isEnabled = false
    @ObservationIgnored private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Halo", category: "MenuBar")

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            startObserving()
            scheduleReads()
        } else {
            stopObserving()
            readTask?.cancel()
            readTask = nil
            setWingsCoverMenus(false)
        }
    }

    /// Shows the system prompt that leads to the permission, if it isn't granted yet.
    func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        setTrusted(AXIsProcessTrustedWithOptions(options))
    }

    func refreshAccess() {
        setTrusted(AXIsProcessTrusted())
    }

    func openAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Events

    private func startObserving() {
        observe(NSWorkspace.didActivateApplicationNotification, on: NSWorkspace.shared.notificationCenter)
        observe(NSApplication.didChangeScreenParametersNotification, on: .default)
        // Posted when an app is added to or removed from the list of the Accessibility permission.
        observe(Notification.Name("com.apple.accessibility.api"), on: DistributedNotificationCenter.default())
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleReads()
            }
        }
        observers.append((center, token))
    }

    private func stopObserving() {
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers.removeAll()
    }

    // MARK: - Reading

    private func scheduleReads() {
        readTask?.cancel()
        readTask = Task { [weak self] in
            for delay in Self.readDelays {
                if delay != .zero {
                    try? await Task.sleep(for: delay)
                }
                guard !Task.isCancelled else { return }
                await self?.read()
            }
        }
    }

    private func read() async {
        refreshAccess()
        guard isTrusted, let frontmost = NSWorkspace.shared.frontmostApplication else {
            setWingsCoverMenus(false)
            return
        }
        let frontmostID = frontmost.processIdentifier
        let statusItemOwners = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited }
            .map(\.processIdentifier)

        // Accessibility calls block until the other app answers: never on the main thread.
        let start = ContinuousClock.now
        let (menus, statusItems) = await Task.detached(priority: .utility) {
            (
                MenuBarReader.itemFrames(of: frontmostID, in: kAXMenuBarAttribute),
                statusItemOwners.flatMap { MenuBarReader.itemFrames(of: $0, in: kAXExtrasMenuBarAttribute) }
            )
        }.value
        guard !Task.isCancelled else { return }

        let covered = Self.wingsCover(menus + statusItems)
        logger.info("\(menus.count) menus up to x=\(menus.map(\.maxX).max() ?? 0), \(statusItems.count) status items from x=\(statusItems.map(\.minX).min() ?? 0), wings cover menus: \(covered), read in \(start.duration(to: .now))")
        setWingsCoverMenus(covered)
    }

    /// Item frames use Accessibility coordinates: the origin is the top left of the primary display.
    private static func wingsCover(_ frames: [CGRect]) -> Bool {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return false }
        return NSScreen.screens.contains { screen in
            let metrics = IslandMetrics(screen: screen)
            let menuBarY = primaryHeight - screen.frame.maxY
            let menuBar = menuBarY - 1 ..< menuBarY + metrics.base.height
            return frames.contains { frame in
                menuBar.contains(frame.minY) && metrics.wingRanges.contains { range in
                    frame.width > 0 && frame.maxX > range.lowerBound && frame.minX < range.upperBound
                }
            }
        }
    }

    private func setTrusted(_ trusted: Bool) {
        if isTrusted != trusted {
            isTrusted = trusted
        }
    }

    private func setWingsCoverMenus(_ covered: Bool) {
        if wingsCoverMenus != covered {
            wingsCoverMenus = covered
        }
    }
}

/// Accessibility reads, off the main thread.
private enum MenuBarReader {
    /// Bounds the wait for an app that doesn't answer, such as a hung one.
    private static let timeout: Float = 0.2

    /// Frames of the children of a menu bar attribute of an app. Empty if the app doesn't have one.
    static func itemFrames(of pid: pid_t, in attribute: String) -> [CGRect] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        guard let bar: AXUIElement = value(of: app, attribute),
              let items: [AXUIElement] = value(of: bar, kAXChildrenAttribute)
        else { return [] }
        return items.compactMap(frame)
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue: AXValue = value(of: element, kAXPositionAttribute),
              let sizeValue: AXValue = value(of: element, kAXSizeAttribute)
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func value<T>(of element: AXUIElement, _ attribute: String) -> T? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result as? T
    }
}
