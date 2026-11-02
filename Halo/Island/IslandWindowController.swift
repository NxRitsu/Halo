import AppKit
import SwiftUI

/// Owns the panel of one island and drives its transitions (expansion, activity changes).
///
/// The panel always matches the bounding box of the island's current state, so it never
/// intercepts clicks on the menu bar outside the island. During a transition, the panel covers
/// both the old and new states while SwiftUI animates the shape inside it, then fits the new
/// state once the animation has finished.
///
/// The SwiftUI view itself keeps the largest possible size, pinned at the top center of the island:
/// the panel only acts as a viewport around it. SwiftUI therefore never sees a size change,
/// which would otherwise be animated (the island would grow from a corner) and can loop on
/// constraint updates when the hosting view is the panel's content view.
///
/// Resizing the panel rebuilds its tracking area, which can emit a spurious "exited" event while
/// the cursor is still inside. So once expanded, the island decides when to collapse from the
/// actual cursor position, using mouse-moved monitors that only exist while it is expanded.
@MainActor
final class IslandWindowController {
    private static let expandAnimation = Animation.spring(response: 0.42, dampingFraction: 0.78)
    private static let collapseAnimation = Animation.spring(response: 0.36, dampingFraction: 0.9)
    private static let collapseDelay: Duration = .milliseconds(120)
    private static let contentAnimation = Animation.spring(response: 0.45, dampingFraction: 0.8)

    let displayID: CGDirectDisplayID
    private let panel: IslandPanel
    private let model: IslandModel
    private let hostingView: IslandHostingView<IslandView>
    private var pendingTransition: Task<Void, Never>?
    private var isHidden = false
    private var mouseMonitors: [Any] = []
    private let activities: ActivityCoordinator
    /// Identifies the latest transition, so that only its completion resizes the panel.
    private var transitionID = 0

    init(screen: NSScreen, displayID: CGDirectDisplayID, services: AppServices) {
        self.displayID = displayID
        activities = services.activities
        let metrics = IslandMetrics(screen: screen)
        model = IslandModel(
            metrics: metrics,
            content: services.activities.content,
            nowPlaying: services.nowPlaying,
            lyrics: services.lyrics,
            battery: services.battery
        )
        panel = IslandPanel(contentRect: metrics.windowFrame(for: model.layout))

        hostingView = IslandHostingView(rootView: IslandView(model: model))
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        let container = NSView(frame: NSRect(origin: .zero, size: panel.frame.size))
        container.autoresizesSubviews = false
        container.addSubview(hostingView)
        panel.contentView = container
        setPanelFrame(panel.frame)

        hostingView.onHoverChange = { [weak self] inside in
            self?.hoverChanged(inside)
        }
        model.onTap = { [weak self] in
            self?.expand()
        }
        panel.orderFrontRegardless()
        observeActivities()

        #if DEBUG
        if ProcessInfo.processInfo.environment["HALO_STRESS_EXPANSION"] != nil {
            startExpansionStressTest()
        }
        #endif
    }

    #if DEBUG
    /// Expands and collapses the island in a loop, to reproduce layout issues without a mouse.
    private func startExpansionStressTest() {
        Task { [weak self] in
            while let self {
                try? await Task.sleep(for: .milliseconds(Int.random(in: 50...700)))
                if self.model.isExpanded { self.collapse() } else { self.expand() }
            }
        }
    }
    #endif

    func update(screen: NSScreen) {
        let metrics = IslandMetrics(screen: screen)
        guard metrics != model.metrics else { return }
        model.metrics = metrics
        transitionID += 1
        setPanelFrame(metrics.windowFrame(for: model.layout))
    }

    /// Resizes the panel and keeps the hosting view fixed on screen.
    private func setPanelFrame(_ frame: NSRect) {
        panel.setFrame(frame, display: true)
        let hostedFrame = model.metrics.windowFrame(for: model.metrics.largest)
        let origin = NSPoint(x: hostedFrame.minX - frame.minX, y: hostedFrame.minY - frame.minY)
        hostingView.frame = NSRect(origin: origin, size: hostedFrame.size)
    }

    /// Animates the island to a new state. The panel covers both states during the animation.
    private func transition(expanded: Bool, content: IslandContent, animation: Animation) {
        let target = model.metrics.windowFrame(for: model.metrics.layout(expanded: expanded, content: content))
        transitionID += 1
        let id = transitionID
        setPanelFrame(panel.frame.union(target))
        withAnimation(animation) {
            model.isExpanded = expanded
            model.content = content
        } completion: { [weak self] in
            guard let self, self.transitionID == id else { return }
            self.setPanelFrame(target)
        }
    }

    // MARK: - Activities

    private func observeActivities() {
        withObservationTracking {
            _ = activities.content
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.contentChanged()
                self.observeActivities()
            }
        }
    }

    private func contentChanged() {
        let content = activities.content
        guard content != model.content else { return }
        if isHidden {
            model.content = content
            transitionID += 1
            setPanelFrame(model.metrics.windowFrame(for: model.layout))
        } else {
            transition(expanded: model.isExpanded, content: content, animation: Self.contentAnimation)
        }
    }

    func setHidden(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        isHidden = hidden
        if hidden {
            cancelPendingTransition()
            stopMouseMonitors()
            model.isExpanded = false
            transitionID += 1
            setPanelFrame(model.metrics.windowFrame(for: model.layout))
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func close() {
        cancelPendingTransition()
        stopMouseMonitors()
        panel.close()
    }

    // MARK: - Expansion

    private func hoverChanged(_ inside: Bool) {
        // While expanded, collapsing is driven by `mouseMoved()`, not by tracking area events.
        guard !model.isExpanded else {
            if inside { cancelPendingTransition() }
            return
        }
        cancelPendingTransition()
        if inside, Preferences.expandOnHover {
            schedule(after: .seconds(Preferences.hoverDelay)) { controller in
                if controller.isMouseInside { controller.expand() }
            }
        }
    }

    private func mouseMoved() {
        // Never collapse in the middle of a drag (for instance on the progress bar).
        guard model.isExpanded, NSEvent.pressedMouseButtons == 0 else { return }
        if isMouseInside {
            cancelPendingTransition()
        } else if pendingTransition == nil {
            schedule(after: Self.collapseDelay) { controller in
                if !controller.isMouseInside { controller.collapse() }
            }
        }
    }

    /// Whether the cursor is over the panel. The top edge is inclusive: the cursor often rests there.
    private var isMouseInside: Bool {
        let location = NSEvent.mouseLocation
        let frame = panel.frame
        return location.x >= frame.minX && location.x <= frame.maxX
            && location.y >= frame.minY && location.y <= frame.maxY
    }

    private func schedule(after delay: Duration, _ action: @escaping (IslandWindowController) -> Void) {
        pendingTransition?.cancel()
        pendingTransition = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.pendingTransition = nil
            action(self)
        }
    }

    private func cancelPendingTransition() {
        pendingTransition?.cancel()
        pendingTransition = nil
    }

    private func expand() {
        cancelPendingTransition()
        guard !model.isExpanded, !isHidden else { return }
        transition(expanded: true, content: model.content, animation: Self.expandAnimation)
        startMouseMonitors()
    }

    private func collapse() {
        guard model.isExpanded else { return }
        stopMouseMonitors()
        transition(expanded: false, content: model.content, animation: Self.collapseAnimation)
    }

    // MARK: - Mouse monitors (only while expanded)

    private func startMouseMonitors() {
        guard mouseMonitors.isEmpty else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseUp]
        // Global monitors see events sent to other apps, local ones events sent to Halo.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.mouseMoved() }
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    private func stopMouseMonitors() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors.removeAll()
    }
}
