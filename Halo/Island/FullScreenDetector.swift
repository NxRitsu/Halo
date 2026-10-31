import AppKit

/// Detects which displays currently show a full screen Space.
///
/// There is no public API for this. The primary method asks the window server for the type of
/// the current Space on each display through the private `CGSCopyManagedDisplaySpaces` function
/// (a full screen Space has type 4). It is resolved at runtime, so if it disappears in a future
/// macOS release the detector falls back to a heuristic based on window bounds.
enum FullScreenDetector {
    enum Method: Equatable {
        case spaces
        case windowBounds
    }

    private typealias MainConnectionFunction = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpacesFunction = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let fullScreenSpaceType = 4
    /// Display identifier used when "Displays have separate Spaces" is turned off.
    private static let sharedSpacesIdentifier = "Main"

    private static let spacesAPI: (MainConnectionFunction, CopyManagedDisplaySpacesFunction)? = {
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let connection = dlsym(defaultHandle, "CGSMainConnectionID"),
              let copySpaces = dlsym(defaultHandle, "CGSCopyManagedDisplaySpaces")
        else { return nil }
        return (
            unsafeBitCast(connection, to: MainConnectionFunction.self),
            unsafeBitCast(copySpaces, to: CopyManagedDisplaySpacesFunction.self)
        )
    }()

    /// The method currently in use, for diagnostics.
    static var method: Method {
        spacesAPI != nil ? .spaces : .windowBounds
    }

    static func fullScreenDisplayIDs() -> Set<CGDirectDisplayID> {
        fullScreenDisplayIDsFromSpaces() ?? fullScreenDisplayIDsFromWindowBounds()
    }

    // MARK: - Spaces (private API)

    private static func fullScreenDisplayIDsFromSpaces() -> Set<CGDirectDisplayID>? {
        guard let (mainConnection, copyManagedDisplaySpaces) = spacesAPI,
              let displays = copyManagedDisplaySpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]]
        else { return nil }

        var fullScreenIdentifiers = Set<String>()
        for display in displays {
            guard let identifier = display["Display Identifier"] as? String,
                  let currentSpace = display["Current Space"] as? [String: Any],
                  let type = currentSpace["type"] as? Int
            else { return nil }
            if type == fullScreenSpaceType {
                fullScreenIdentifiers.insert(identifier)
            }
        }

        var result = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            if fullScreenIdentifiers.contains(sharedSpacesIdentifier)
                || fullScreenIdentifiers.contains(displayUUID(displayID) ?? "") {
                result.insert(displayID)
            }
        }
        return result
    }

    private static func displayUUID(_ displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    // MARK: - Window bounds (fallback)

    /// A display is considered in full screen when a regular window spans its whole width, from
    /// the menu bar (or notch) down to its bottom edge, and no other app has a window on it:
    /// a full screen Space only shows the windows of one app, unlike a desktop with a maximized window.
    private static func fullScreenDisplayIDsFromWindowBounds() -> Set<CGDirectDisplayID> {
        guard let primary = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let appWindows: [(pid: pid_t, bounds: CGRect)] = windows.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { return nil }
            return (pid, bounds)
        }

        var result = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            // Convert to CoreGraphics coordinates (origin at the top left of the primary display).
            let frame = screen.frame
            let cgFrame = CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
            let menuBarHeight = max(screen.safeAreaInsets.top, frame.maxY - screen.visibleFrame.maxY)

            let windowsOnScreen = appWindows.filter { $0.bounds.intersects(cgFrame) }
            guard let candidate = windowsOnScreen.first(where: { window in
                abs(window.bounds.width - cgFrame.width) < 1
                    && abs(window.bounds.maxY - cgFrame.maxY) < 1
                    && window.bounds.minY <= cgFrame.minY + menuBarHeight + 1
            }) else { continue }

            if windowsOnScreen.allSatisfy({ $0.pid == candidate.pid }) {
                result.insert(displayID)
            }
        }
        return result
    }
}
