import AppKit
import SwiftUI

/// Hosting view that reports hover changes and accepts clicks without activating the app.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChange: ((Bool) -> Void)?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        // The window size is driven by the controller, never by the SwiftUI content.
        sizingOptions = []
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChange?(false)
    }
}
