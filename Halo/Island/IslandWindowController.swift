import AppKit
import SwiftUI

/// Owns the panel of one island and drives its expansion.
///
/// The panel always matches the bounding box of the island's current state, so it never
/// intercepts clicks on the menu bar outside the island. When expanding, the panel grows first
/// and SwiftUI animates the shape inside it; when collapsing, the panel shrinks once the
/// animation has finished.
///
/// The SwiftUI view itself keeps the expanded size, pinned at the top center of the island:
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

    let displayID: CGDirectDisplayID
    private let panel: IslandPanel
    private let model: IslandModel
    private let hostingView: IslandHostingView<IslandView>
    private var pendingTransition: Task<Void, Never>?
    private var isHidden = false
    private var mouseMonitors: [Any] = []

    init(screen: NSScreen, displayID: CGDirectDisplayID) {
        self.displayID = displayID
        let metrics = IslandMetrics(screen: screen)
        model = IslandModel(metrics: metrics)
        panel = IslandPanel(contentRect: metrics.windowFrame(for: metrics.compact))

        hostingView = IslandHostingView(rootView: IslandView(model: model))
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        let container = NSView(frame: NSRect(origin: .zero, size: panel.frame.size))
        container.autoresizesSubviews = false
        container.addSubview(hostingView)
        panel.contentView = container
        layoutHostingView()

        hostingView.onHoverChange = { [weak self] inside in
            self?.hoverChanged(inside)
        }
        model.onTap = { [weak self] in
            self?.expand()
        }
        panel.orderFrontRegardless()

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
        setPanelFrame(for: model.layout)
    }

    /// Resizes the panel around the island and keeps the hosting view fixed on screen.
    private func setPanelFrame(for layout: IslandLayout) {
        panel.setFrame(model.metrics.windowFrame(for: layout), display: true)
        layoutHostingView()
    }

    /// Places the hosting view at its expanded frame, in the panel's coordinates.
    private func layoutHostingView() {
        let expandedFrame = model.metrics.windowFrame(for: model.metrics.expanded)
        let origin = NSPoint(x: expandedFrame.minX - panel.frame.minX, y: expandedFrame.minY - panel.frame.minY)
        hostingView.frame = NSRect(origin: origin, size: expandedFrame.size)
    }

    func setHidden(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        isHidden = hidden
        if hidden {
            cancelPendingTransition()
            stopMouseMonitors()
            model.isExpanded = false
            setPanelFrame(for: model.metrics.compact)
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
        guard model.isExpanded else { return }
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
        setPanelFrame(for: model.metrics.expanded)
        withAnimation(Self.expandAnimation) {
            model.isExpanded = true
        }
        startMouseMonitors()
    }

    private func collapse() {
        guard model.isExpanded else { return }
        stopMouseMonitors()
        withAnimation(Self.collapseAnimation) {
            model.isExpanded = false
        } completion: { [weak self] in
            guard let self, !self.model.isExpanded else { return }
            self.setPanelFrame(for: self.model.metrics.compact)
        }
    }

    // MARK: - Mouse monitors (only while expanded)

    private func startMouseMonitors() {
        guard mouseMonitors.isEmpty else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
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
