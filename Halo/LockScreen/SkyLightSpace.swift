import AppKit

/// A window server space drawn above the lock screen, through the private SkyLight framework.
///
/// Windows of an app stay below the lock screen, whatever their level. A space created with a high
/// absolute level is composited above it, along with the windows moved into it. Several open
/// source projects use this technique; none of their code is copied here.
///
/// Every function is looked up at runtime. If one is missing on a version of macOS, the space
/// can't be created and the lock screen widgets turn themselves off.
@MainActor
final class SkyLightSpace {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias SpaceDestroy = @convention(c) (Int32, UInt64) -> Int32
    private typealias SetAbsoluteLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32

    /// Level of the lock screen's notifications: above the lock screen, below system alerts.
    private static let lockScreenLevel: Int32 = 400

    private let connection: Int32
    private let space: UInt64
    private let addWindows: AddWindows

    init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let mainConnection = Self.function("SLSMainConnectionID", in: handle, as: MainConnection.self),
              let create = Self.function("SLSSpaceCreate", in: handle, as: SpaceCreate.self),
              let destroy = Self.function("SLSSpaceDestroy", in: handle, as: SpaceDestroy.self),
              let setLevel = Self.function("SLSSpaceSetAbsoluteLevel", in: handle, as: SetAbsoluteLevel.self),
              let show = Self.function("SLSShowSpaces", in: handle, as: ShowSpaces.self),
              let addWindows = Self.function("SLSSpaceAddWindowsAndRemoveFromSpaces", in: handle, as: AddWindows.self)
        else { return nil }

        connection = mainConnection()
        space = create(connection, 1, nil)
        guard space != 0 else { return nil }
        guard setLevel(connection, space, Self.lockScreenLevel) == 0 else {
            _ = destroy(connection, space)
            return nil
        }
        _ = show(connection, [NSNumber(value: space)] as CFArray)
        self.addWindows = addWindows
    }

    /// Moves a window into the space. It must be on screen already.
    func add(_ window: NSWindow) {
        // 7: remove the window from every other space.
        _ = addWindows(connection, space, [NSNumber(value: window.windowNumber)] as CFArray, 7)
    }

    private static func function<T>(_ name: String, in handle: UnsafeMutableRawPointer, as type: T.Type) -> T? {
        dlsym(handle, name).map { unsafeBitCast($0, to: type) }
    }
}
