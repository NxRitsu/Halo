import AppKit
import OSLog
import SwiftUI

enum LockScreenStatus: Equatable {
    case disabled
    case ready
    /// The private SkyLight functions are missing or refused to create the space.
    case unavailable
}

/// Shows the widgets on the lock screen while the Mac is locked, and removes them as soon as it
/// unlocks.
///
/// macOS posts distributed notifications when the screen locks and unlocks: nothing is polled.
/// The window only exists while the screen is locked, so the widgets cost nothing otherwise.
@MainActor
@Observable
final class LockScreenService {
    private static let lockedNotification = Notification.Name("com.apple.screenIsLocked")
    private static let unlockedNotification = Notification.Name("com.apple.screenIsUnlocked")
    /// Size of the window, centered below the clock of the lock screen.
    static let windowSize = CGSize(width: 460, height: 320)

    private(set) var status = LockScreenStatus.disabled
    private(set) var isLocked = false

    @ObservationIgnored private var space: SkyLightSpace?
    @ObservationIgnored private var window: NSPanel?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Halo", category: "LockScreen")
    @ObservationIgnored private let makeContent: @MainActor () -> AnyView

    init(content: @escaping @MainActor () -> AnyView) {
        makeContent = content
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            guard observers.isEmpty else { return }
            let center = DistributedNotificationCenter.default()
            observers = [
                center.addObserver(forName: Self.lockedNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.locked() }
                },
                center.addObserver(forName: Self.unlockedNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.unlocked() }
                },
            ]
            status = .ready
            if Self.screenIsLocked { locked() }
        } else {
            observers.forEach(DistributedNotificationCenter.default().removeObserver)
            observers = []
            hideWindow()
            isLocked = false
            status = .disabled
        }
    }

    private func locked() {
        isLocked = true
        if space == nil {
            space = SkyLightSpace()
            if space == nil {
                logger.error("Can't draw above the lock screen")
                status = .unavailable
                return
            }
        }
        showWindow()
    }

    private func unlocked() {
        isLocked = false
        hideWindow()
    }

    private func showWindow() {
        guard window == nil, let space, let screen = NSScreen.screens.first else { return }
        let size = Self.windowSize
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            // Below the date and time that macOS draws at the top of the lock screen.
            y: screen.frame.maxY - screen.frame.height * 0.3 - size.height,
            width: size.width,
            height: size.height
        )
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        // The widgets can't be used: clicks go to the lock screen.
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        let hosting = NSHostingView(rootView: makeContent())
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.orderFrontRegardless()
        space.add(panel)
        window = panel
        logger.notice("Widgets shown on the lock screen")
    }

    private func hideWindow() {
        guard let window else { return }
        window.orderOut(nil)
        window.contentView = nil
        window.close()
        self.window = nil
        logger.notice("Widgets removed from the lock screen")
    }

    /// Whether the screen is locked right now, for when Halo starts while it is.
    private static var screenIsLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
