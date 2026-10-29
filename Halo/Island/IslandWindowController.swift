import AppKit
import SwiftUI

/// Owns the panel of one island and drives its expansion.
///
/// The panel always matches the bounding box of the island's current state, so it never
/// intercepts clicks on the menu bar outside the island. When expanding, the panel grows first
/// and SwiftUI animates the shape inside it; when collapsing, the panel shrinks once the
/// animation has finished.
@MainActor
final class IslandWindowController {
    private static let expandAnimation = Animation.spring(response: 0.42, dampingFraction: 0.78)
    private static let collapseAnimation = Animation.spring(response: 0.36, dampingFraction: 0.9)
    private static let collapseDelay: Duration = .milliseconds(120)

    let displayID: CGDirectDisplayID
    private let panel: IslandPanel
    private let model: IslandModel
    private var pendingTransition: Task<Void, Never>?
    private var isHidden = false

    init(screen: NSScreen, displayID: CGDirectDisplayID) {
        self.displayID = displayID
        let metrics = IslandMetrics(screen: screen)
        model = IslandModel(metrics: metrics)
        panel = IslandPanel(contentRect: metrics.windowFrame(for: metrics.compact))

        let hostingView = IslandHostingView(rootView: IslandView(model: model))
        hostingView.onHoverChange = { [weak self] inside in
            self?.hoverChanged(inside)
        }
        panel.contentView = hostingView
        model.onTap = { [weak self] in
            self?.expand()
        }
        panel.orderFrontRegardless()
    }

    func update(screen: NSScreen) {
        let metrics = IslandMetrics(screen: screen)
        guard metrics != model.metrics else { return }
        model.metrics = metrics
        panel.setFrame(metrics.windowFrame(for: model.layout), display: true)
    }

    func setHidden(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        isHidden = hidden
        if hidden {
            pendingTransition?.cancel()
            model.isExpanded = false
            panel.setFrame(model.metrics.windowFrame(for: model.metrics.compact), display: false)
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func close() {
        pendingTransition?.cancel()
        panel.close()
    }

    // MARK: - Expansion

    private func hoverChanged(_ inside: Bool) {
        pendingTransition?.cancel()
        if inside {
            guard Preferences.expandOnHover, !model.isExpanded else { return }
            schedule(after: .seconds(Preferences.hoverDelay)) { $0.expand() }
        } else if model.isExpanded {
            schedule(after: Self.collapseDelay) { $0.collapse() }
        }
    }

    private func schedule(after delay: Duration, _ action: @escaping (IslandWindowController) -> Void) {
        pendingTransition = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            action(self)
        }
    }

    private func expand() {
        pendingTransition?.cancel()
        guard !model.isExpanded, !isHidden else { return }
        panel.setFrame(model.metrics.windowFrame(for: model.metrics.expanded), display: true)
        withAnimation(Self.expandAnimation) {
            model.isExpanded = true
        }
    }

    private func collapse() {
        guard model.isExpanded else { return }
        withAnimation(Self.collapseAnimation) {
            model.isExpanded = false
        } completion: { [weak self] in
            guard let self, !self.model.isExpanded else { return }
            self.panel.setFrame(self.model.metrics.windowFrame(for: self.model.metrics.compact), display: true)
        }
    }
}
