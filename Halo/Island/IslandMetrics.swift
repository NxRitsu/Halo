import AppKit

/// Size and corner radii of the island in one state.
struct IslandLayout: Equatable {
    /// Width of the island body, excluding the top "ears".
    var width: CGFloat
    var height: CGFloat
    /// Radius of the concave curves that join the island to the top edge of the screen.
    var earRadius: CGFloat
    var bottomRadius: CGFloat

    /// Width including the ears: the size of the window that hosts this state.
    var totalWidth: CGFloat { width + earRadius * 2 }
}

/// Geometry of the island on one screen, derived from the notch when there is one.
struct IslandMetrics: Equatable {
    let hasNotch: Bool
    /// Horizontal center of the notch (or of the screen), in global screen coordinates.
    let centerX: CGFloat
    /// Top edge of the screen, in global screen coordinates.
    let topY: CGFloat
    let scale: CGFloat
    /// The idle compact island: the notch itself, or a virtual island of similar size.
    let base: IslandLayout

    init(screen: NSScreen) {
        let frame = screen.frame
        scale = screen.backingScaleFactor
        topY = frame.maxY

        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            // The notch is the strip between the two menu bar areas left and right of it.
            let notchWidth = frame.width - left.width - right.width
            let notchHeight = screen.safeAreaInsets.top
            hasNotch = true
            centerX = frame.minX + left.width + notchWidth / 2
            // At rest the island covers the notch exactly and stays invisible.
            // A slightly larger bottom radius than the hardware keeps the corners hidden behind it.
            base = IslandLayout(width: notchWidth, height: notchHeight, earRadius: 0, bottomRadius: 10)
        } else {
            // No notch: draw a virtual island of similar size in the menu bar.
            let menuBarHeight = frame.maxY - screen.visibleFrame.maxY
            let height = menuBarHeight > 0 ? menuBarHeight : NSStatusBar.system.thickness
            hasNotch = false
            centerX = frame.midX
            base = IslandLayout(width: 180, height: height, earRadius: 6, bottomRadius: 10)
        }
    }

    /// Width of each side area of the compact island, left and right of the notch.
    /// Kept as narrow as its content allows, because the wings cover the menu bar.
    var wingWidth: CGFloat { base.height }

    /// Horizontal parts of the menu bar covered by the compact wings, in global screen coordinates.
    var wingRanges: [Range<CGFloat>] {
        let overflow = (wingsLayout.totalWidth - base.width) / 2
        let notchMinX = centerX - base.width / 2
        let notchMaxX = centerX + base.width / 2
        return [notchMinX - overflow ..< notchMinX, notchMaxX ..< notchMaxX + overflow]
    }

    private var expandedWidth: CGFloat { max(base.width + 220, 440) }

    /// Height of the synced lyrics area in the expanded player, spacing included.
    static let lyricsHeight: CGFloat = 86

    /// Height of the alert area below the notch.
    static let alertHeight: CGFloat = 50

    func layout(expanded: Bool, content: IslandContent) -> IslandLayout {
        if expanded {
            let contentHeight: CGFloat = switch content.expanded {
            case .idle: 96
            case .nowPlaying: content.showsLyrics ? 150 + Self.lyricsHeight : 150
            }
            return IslandLayout(width: expandedWidth, height: base.height + contentHeight, earRadius: 14, bottomRadius: 32)
        }
        if let alert = content.alert {
            return alertLayout(for: alert.event)
        }
        if content.compactHasWings {
            return wingsLayout
        }
        return base
    }

    private var wingsLayout: IslandLayout {
        IslandLayout(width: base.width + wingWidth * 2, height: base.height, earRadius: 6, bottomRadius: 12)
    }

    private func alertLayout(for event: IslandAlert.Event) -> IslandLayout {
        switch event {
        case .battery: batteryAlertLayout
        case .bluetooth: bluetoothAlertLayout
        }
    }

    private var batteryAlertLayout: IslandLayout {
        IslandLayout(width: max(base.width + 140, 340), height: base.height + Self.alertHeight, earRadius: 10, bottomRadius: 24)
    }

    /// Wider than the battery alert: it holds a device name and up to three gauges.
    private var bluetoothAlertLayout: IslandLayout {
        IslandLayout(width: max(base.width + 220, 410), height: base.height + Self.alertHeight, earRadius: 10, bottomRadius: 24)
    }

    /// Smallest layout that contains every possible state: the size of the hosted SwiftUI view.
    var largest: IslandLayout {
        let expanded = [IslandContent.Activity.idle, .nowPlaying].flatMap { activity in
            [false, true].map { lyrics in
                layout(expanded: true, content: IslandContent(expanded: activity, showsLyrics: lyrics))
            }
        }
        let all = expanded + [base, wingsLayout, batteryAlertLayout, bluetoothAlertLayout]
        return IslandLayout(
            width: all.map(\.totalWidth).max() ?? base.totalWidth,
            height: all.map(\.height).max() ?? base.height,
            earRadius: 0,
            bottomRadius: 0
        )
    }

    /// Window frame that hosts the island in the given layout, aligned on the backing pixel grid.
    func windowFrame(for layout: IslandLayout) -> NSRect {
        let width = layout.totalWidth
        let x = ((centerX - width / 2) * scale).rounded() / scale
        return NSRect(x: x, y: topY - layout.height, width: width, height: layout.height)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    var isBuiltIn: Bool {
        displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false
    }
}
