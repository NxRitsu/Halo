import AppKit

/// Detects which displays currently show a full screen app.
///
/// There is no public API for this. A display is considered in full screen when its menu bar
/// window is not on screen and a regular window from another app spans its whole width down to
/// its bottom edge. Only window bounds and layers are read, which requires no permission.
enum FullScreenDetector {
    static func fullScreenDisplayIDs() -> Set<CGDirectDisplayID> {
        guard let primary = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let menuBarLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        let entries: [(layer: Int, pid: pid_t, bounds: CGRect)] = windows.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { return nil }
            return (layer, pid, bounds)
        }

        var result = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            // Convert to CoreGraphics coordinates (origin at the top left of the primary display).
            let frame = screen.frame
            let cgFrame = CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
            let menuBarStrip = CGRect(x: cgFrame.minX, y: cgFrame.minY, width: cgFrame.width, height: 1)

            let hasMenuBar = entries.contains { $0.layer == menuBarLevel && $0.bounds.intersects(menuBarStrip) }
            guard !hasMenuBar else { continue }

            let topLimit = cgFrame.minY + screen.safeAreaInsets.top + 1
            let hasFullScreenWindow = entries.contains { entry in
                entry.layer == 0 && entry.pid != ownPID
                    && abs(entry.bounds.width - cgFrame.width) < 1
                    && abs(entry.bounds.maxY - cgFrame.maxY) < 1
                    && entry.bounds.minY <= topLimit
                    && entry.bounds.minX >= cgFrame.minX - 1 && entry.bounds.maxX <= cgFrame.maxX + 1
            }
            if hasFullScreenWindow {
                result.insert(displayID)
            }
        }
        return result
    }
}
