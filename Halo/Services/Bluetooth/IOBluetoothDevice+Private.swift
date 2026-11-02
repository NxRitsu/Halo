import AppKit
import AudioToolbox
import CoreAudio
import Foundation
import IOBluetooth
import ObjectiveC

/// What `IOBluetoothDevice` knows but doesn't publish.
///
/// Battery levels are private properties of the class, which `bluetoothd` fills while an Apple
/// audio device is connected. The noise control mode only has a real value on the private
/// `CBClassicPeer` behind the device: the property of the same name on `IOBluetoothDevice` stays 0.
/// There's no public API for any of them. Each one is looked up at runtime and its type checked
/// first, so that on a version of macOS that removed or changed it, the value is simply unknown.
/// A value of 0 also means unknown.
extension IOBluetoothDevice {
    private static let batterySelectors = ["batteryPercentLeft", "batteryPercentRight", "batteryPercentCase", "batteryPercentSingle"]

    static var supportsPrivateBatteryLevels: Bool {
        batterySelectors.allSatisfy { hasGetter($0, returning: "C", in: self) }
    }

    var isAudioDevice: Bool {
        deviceClassMajor == kBluetoothDeviceClassMajorAudio || privateFlag("isAdvancedAppleAudioDevice")
    }

    func audioDevice(id: String) -> BluetoothAudioDevice {
        var device = BluetoothAudioDevice(id: id, name: name ?? String(localized: "Audio device"), symbol: modelSymbol)
        device.battery = BluetoothBattery(
            left: privatePercent("batteryPercentLeft"),
            right: privatePercent("batteryPercentRight"),
            chargingCase: privatePercent("batteryPercentCase"),
            single: privatePercent("batteryPercentSingle")
        )
        device.volume = BluetoothAudioVolume.read(address: id)
        device.listeningMode = classicPeer.flatMap { byte("listeningMode", of: $0) }.flatMap(ListeningMode.init(rawValue:))
        device.supportedListeningModes = supportedListeningModes
        return device
    }

    func setPrivateListeningMode(_ mode: ListeningMode) {
        let selector = NSSelectorFromString("setListeningMode:")
        guard let peer = classicPeer, peer.responds(to: selector), byte("listeningMode", of: peer) != nil else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, UInt8) -> Void
        unsafeBitCast(peer.method(for: selector), to: Setter.self)(peer, selector, mode.rawValue)
    }

    private var supportedListeningModes: [ListeningMode] {
        let noiseCancellation = privateFlag("isANCSupported")
        let transparency = privateFlag("isTransparencySupported")
        guard noiseCancellation || transparency else { return [] }
        var modes = [ListeningMode.off]
        if noiseCancellation { modes.append(.noiseCancellation) }
        if transparency { modes.append(.transparency) }
        if Self.adaptiveProductIDs.contains(privateProductID) { modes.append(.adaptive) }
        return modes
    }

    // MARK: - Model

    private static let appleVendorID: UInt16 = 0x004C
    /// AirPods Pro 2 (Lightning and USB-C), AirPods Pro 3 and AirPods 4 with noise cancellation.
    private static let adaptiveProductIDs: Set<UInt16> = [0x2014, 0x2024, 0x2027, 0x201B]

    private var modelSymbol: String {
        Self.firstAvailableSymbol(in: appleModelSymbols + classSymbols + ["headphones"])
    }

    /// Apple and Beats product identifiers.
    private var appleModelSymbols: [String] {
        guard privateVendorID == Self.appleVendorID else { return [] }
        switch privateProductID {
        case 0x2002, 0x200F: return ["airpods"]
        case 0x2013: return ["airpods.gen3", "airpods"]
        case 0x2019, 0x201B: return ["airpods.gen4", "airpods"]
        case 0x200E, 0x2014, 0x2024, 0x2027: return ["airpods.pro", "airpodspro"]
        case 0x200A, 0x201F: return ["airpods.max", "airpodsmax"]
        case 0x2006, 0x2009, 0x2017: return ["beats.headphones"]
        case 0x200B, 0x200C, 0x200D, 0x2011, 0x2016: return ["beats.powerbeats"]
        case 0x2012: return ["beats.fitpro"]
        case 0x2010, 0x2015: return ["beats.studiobuds"]
        default: return privateFlag("isAdvancedAppleAudioDevice") ? ["airpods"] : []
        }
    }

    /// Minor classes of the Bluetooth "audio" major class.
    private var classSymbols: [String] {
        guard deviceClassMajor == kBluetoothDeviceClassMajorAudio else { return [] }
        switch deviceClassMinor {
        case 5, 7: return ["hifispeaker.fill"]
        case 8: return ["car.fill"]
        default: return []
        }
    }

    private static func firstAvailableSymbol(in names: [String]) -> String {
        names.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil } ?? "headphones"
    }

    // MARK: - Private properties

    private var privateVendorID: UInt16 { privateShort("vendorID") ?? 0 }
    private var privateProductID: UInt16 { privateShort("productID") ?? 0 }

    private var classicPeer: AnyObject? {
        let selector = NSSelectorFromString("classicPeer")
        guard Self.hasGetter("classicPeer", returning: "@", in: Self.self) else { return nil }
        return perform(selector)?.takeUnretainedValue()
    }

    private func privatePercent(_ name: String) -> Int? {
        guard let value = byte(name, of: self), (1...100).contains(value) else { return nil }
        return Int(value)
    }

    private func privateFlag(_ name: String) -> Bool {
        let selector = NSSelectorFromString(name)
        guard Self.hasGetter(name, returning: "B", in: Self.self) else { return false }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(method(for: selector), to: Getter.self)(self, selector)
    }

    private func byte(_ name: String, of object: AnyObject) -> UInt8? {
        let selector = NSSelectorFromString(name)
        guard Self.hasGetter(name, returning: "C", in: type(of: object)) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> UInt8
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
    }

    private func privateShort(_ name: String) -> UInt16? {
        let selector = NSSelectorFromString(name)
        guard Self.hasGetter(name, returning: "S", in: Self.self) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> UInt16
        return unsafeBitCast(method(for: selector), to: Getter.self)(self, selector)
    }

    /// Whether the class has this instance method, taking no argument and returning this
    /// Objective-C type. Calling it with the wrong signature would be undefined.
    private static func hasGetter(_ name: String, returning type: String, in owner: AnyClass) -> Bool {
        guard let method = class_getInstanceMethod(owner, NSSelectorFromString(name)) else { return false }
        let returnType = method_copyReturnType(method)
        defer { free(returnType) }
        return String(cString: returnType) == type && method_getNumberOfArguments(method) == 2
    }
}

/// Output volume of a Bluetooth device, through public CoreAudio properties.
enum BluetoothAudioVolume {
    /// CoreAudio names the two sides of a Bluetooth device after its address, such as
    /// "AA-BB-CC-DD-EE-FF:output" and "AA-BB-CC-DD-EE-FF:input".
    static func read(address: String) -> Int? {
        let wanted = normalized(address) + "-OUTPUT"
        guard let device = audioDevices().first(where: { normalized(uniqueID(of: $0) ?? "") == wanted }),
              let volume = mainVolume(of: device)
        else { return nil }
        return Int((volume * 100).rounded())
    }

    private static func normalized(_ text: String) -> String {
        text.uppercased().replacingOccurrences(of: ":", with: "-")
    }

    private static func audioDevices() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices
    }

    private static func uniqueID(of device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func mainVolume(of device: AudioObjectID) -> Float32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var size = UInt32(MemoryLayout<Float32>.size)
        var volume: Float32 = 0
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return nil }
        return volume
    }
}
