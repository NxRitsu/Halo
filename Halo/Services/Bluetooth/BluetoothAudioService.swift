import AppKit
import CoreBluetooth
import Foundation
import IOBluetooth
import OSLog

/// Follows Bluetooth audio devices. No polling: IOBluetooth calls back on each connection and
/// disconnection. Details are then read a few times over some seconds, because AirPods report
/// their battery shortly after connecting.
///
/// `CBCentralManager` never scans here. It asks for the Bluetooth permission, which IOBluetooth
/// needs too, and reports when the permission or the power state changes.
@MainActor
@Observable
final class BluetoothAudioService: NSObject {
    private(set) var status = BluetoothAudioStatus.disabled
    private(set) var devices: [BluetoothAudioDevice] = []

    /// Whether this version of macOS still has the private properties that hold battery levels.
    let canReadBatteries = IOBluetoothDevice.supportsPrivateBatteryLevels

    /// Called on the main actor for each connection and disconnection.
    @ObservationIgnored var onEvent: (BluetoothAudioEvent) -> Void = { _ in }

    @ObservationIgnored private var manager: CBCentralManager?
    @ObservationIgnored private var connectNotification: IOBluetoothUserNotification?
    @ObservationIgnored private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    @ObservationIgnored private var peers: [String: IOBluetoothDevice] = [:]
    @ObservationIgnored private var refreshTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Halo", category: "Bluetooth")

    func setEnabled(_ enabled: Bool) {
        if enabled {
            guard manager == nil else { return }
            status = .starting
            // The first use of this manager is what shows the permission prompt.
            manager = CBCentralManager(
                delegate: self,
                queue: .main,
                options: [CBCentralManagerOptionShowPowerAlertKey: false]
            )
        } else {
            stopListening()
            manager = nil
            status = .disabled
        }
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Keeps the details fresh while a view shows them, until the task is cancelled.
    func monitor() async {
        while !Task.isCancelled {
            refreshAll()
            try? await Task.sleep(for: .seconds(5))
        }
    }

    /// The change reaches the AirPods asynchronously: the mode is read back shortly after.
    func setListeningMode(_ mode: ListeningMode, for id: String) {
        guard let peer = peers[id] else { return }
        peer.setPrivateListeningMode(mode)
        scheduleRefresh(of: id, after: [0.3, 1, 2.5])
    }

    // MARK: - Listening

    private func stateChanged(_ state: CBManagerState) {
        switch state {
        case .poweredOn:
            startListening()
            status = .active
        case .poweredOff:
            stopListening()
            status = .poweredOff
        case .unauthorized:
            stopListening()
            status = .denied
        case .unsupported:
            stopListening()
            status = .unsupported
        case .unknown, .resetting:
            status = .starting
        @unknown default:
            status = .starting
        }
    }

    private func startListening() {
        guard connectNotification == nil else { return }
        // Devices that are already connected don't deserve an alert.
        for peer in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? [] where peer.isConnected() {
            add(peer)
        }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
        if connectNotification == nil {
            logger.error("Bluetooth connection notifications are unavailable")
        }
    }

    private func stopListening() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications = [:]
        refreshTasks.values.forEach { $0.cancel() }
        refreshTasks = [:]
        peers = [:]
        devices = []
    }

    // IOBluetooth calls these two back on the main thread or on a private queue, depending on how
    // it learned about the event. The queue is serial and dispatching keeps the order of events.

    @objc private nonisolated func deviceConnected(_ notification: IOBluetoothUserNotification, device peer: IOBluetoothDevice) {
        nonisolated(unsafe) let peer = peer
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.connected(peer)
            }
        }
    }

    @objc private nonisolated func deviceDisconnected(_ notification: IOBluetoothUserNotification, device peer: IOBluetoothDevice) {
        nonisolated(unsafe) let notification = notification
        nonisolated(unsafe) let peer = peer
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.disconnected(peer, notification: notification)
            }
        }
    }

    private func connected(_ peer: IOBluetoothDevice) {
        guard let id = peer.addressString, peers[id] == nil, let device = add(peer) else { return }
        logger.notice("Audio device connected")
        onEvent(BluetoothAudioEvent(kind: .connected, device: device))
    }

    private func disconnected(_ peer: IOBluetoothDevice, notification: IOBluetoothUserNotification) {
        guard let id = peer.addressString, peers[id] != nil else { return }
        notification.unregister()
        disconnectNotifications[id] = nil
        refreshTasks.removeValue(forKey: id)?.cancel()
        peers[id] = nil
        let device = devices.first { $0.id == id }
        devices.removeAll { $0.id == id }
        logger.notice("Audio device disconnected")
        if let device {
            onEvent(BluetoothAudioEvent(kind: .disconnected, device: device))
        }
    }

    /// Starts following a connected device, if it is an audio device.
    @discardableResult
    private func add(_ peer: IOBluetoothDevice) -> BluetoothAudioDevice? {
        guard peer.isAudioDevice, let id = peer.addressString, peers[id] == nil else { return nil }
        peers[id] = peer
        disconnectNotifications[id] = peer.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:))
        )
        let device = peer.audioDevice(id: id)
        devices.append(device)
        scheduleRefresh(of: id, after: [0.3, 0.7, 1.5, 2, 2.5, 3, 4, 6, 12])
        return device
    }

    // MARK: - Reading

    private func refreshAll() {
        peers.keys.forEach(refresh)
    }

    private func refresh(_ id: String) {
        guard let peer = peers[id], let index = devices.firstIndex(where: { $0.id == id }) else { return }
        let device = peer.audioDevice(id: id)
        guard devices[index] != device else { return }
        devices[index] = device
        logger.notice("""
            Audio device details: left \(device.battery.left ?? -1), right \(device.battery.right ?? -1), \
            case \(device.battery.chargingCase ?? -1), single \(device.battery.single ?? -1), \
            volume \(device.volume ?? -1), mode \(device.listeningMode?.rawValue ?? 0)
            """)
    }

    /// Reads the details at the given delays in seconds, counted from now.
    private func scheduleRefresh(of id: String, after delays: [Double]) {
        refreshTasks[id]?.cancel()
        refreshTasks[id] = Task { [weak self] in
            var elapsed = 0.0
            for delay in delays {
                try? await Task.sleep(for: .seconds(delay - elapsed))
                guard !Task.isCancelled else { return }
                elapsed = delay
                self?.refresh(id)
            }
        }
    }

    #if DEBUG
    /// Shows a made-up device, to check the alerts without connecting one.
    func showSample(_ device: BluetoothAudioDevice) {
        status = .active
        devices = [device]
    }
    #endif
}

extension BluetoothAudioService: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        // The manager delivers its callbacks on the main queue.
        MainActor.assumeIsolated {
            stateChanged(state)
        }
    }
}
