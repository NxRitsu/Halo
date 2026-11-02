import Foundation

/// Noise control mode of a pair of AirPods, as stored by `IOBluetoothDevice`.
enum ListeningMode: UInt8, CaseIterable, Identifiable {
    case off = 1
    case noiseCancellation = 2
    case transparency = 3
    case adaptive = 4

    var id: UInt8 { rawValue }
}

/// Charge of each part of a device, from 1 to 100. A part that is unknown or absent is nil.
struct BluetoothBattery: Equatable {
    var left: Int?
    var right: Int?
    var chargingCase: Int?
    /// Devices with a single battery, such as over-ear headphones.
    var single: Int?

    var isEmpty: Bool { left == nil && right == nil && chargingCase == nil && single == nil }
}

/// A connected Bluetooth audio device.
struct BluetoothAudioDevice: Identifiable, Equatable {
    /// Bluetooth address. It identifies the device, so it never goes in a report or a log.
    let id: String
    var name: String
    /// SF Symbol of the model.
    var symbol: String
    var battery = BluetoothBattery()
    /// Output volume, from 0 to 100, when macOS already exposes the device as an audio output.
    var volume: Int?
    /// Current noise control mode, on devices that report one.
    var listeningMode: ListeningMode?
    var supportedListeningModes: [ListeningMode] = []
}

/// A Bluetooth audio device connected or disconnected, worth a temporary alert.
struct BluetoothAudioEvent: Equatable {
    enum Kind: Equatable {
        case connected
        case disconnected
    }

    let kind: Kind
    /// The device at the time of the event. Its details are still being read when it just connected.
    let device: BluetoothAudioDevice
}

enum BluetoothAudioStatus: Equatable {
    case disabled
    case starting
    case active
    case poweredOff
    case denied
    case unsupported
}
