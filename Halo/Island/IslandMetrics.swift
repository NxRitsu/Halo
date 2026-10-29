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
    let compact: IslandLayout
    let expanded: IslandLayout

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
            compact = IslandLayout(width: notchWidth, height: notchHeight, earRadius: 0, bottomRadius: 10)
        } else {
            // No notch: draw a virtual island of similar size in the menu bar.
            let menuBarHeight = frame.maxY - screen.visibleFrame.maxY
            let height = menuBarHeight > 0 ? menuBarHeight : NSStatusBar.system.thickness
            hasNotch = false
            centerX = frame.midX
            compact = IslandLayout(width: 180, height: height, earRadius: 6, bottomRadius: 10)
        }

        expanded = IslandLayout(
            width: max(compact.width + 220, 440),
            height: compact.height + 96,
            earRadius: 14,
            bottomRadius: 32
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
