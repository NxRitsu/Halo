import AppKit
import CoreLocation
import Foundation
import OSLog

/// Knows the local weather, in reduced location accuracy. Nothing runs on a timer: a refresh only
/// happens when the Mac wakes, when it moved far enough, and when the weather comes on screen, and
/// never more than once per `refreshInterval` unless the Mac moved.
///
/// The coordinates stay in memory and are only sent to Open-Meteo. They are never logged or saved.
@MainActor
@Observable
final class WeatherService: NSObject {
    private static let refreshInterval: TimeInterval = 30 * 60
    /// Reduced accuracy can wander by a few kilometers without the Mac moving at all.
    private static let significantDistance: CLLocationDistance = 10_000
    private static let minimumIntervalAfterMoving: TimeInterval = 5 * 60
    /// Past this age, an old report would be more misleading than no report.
    private static let displayLifetime: TimeInterval = 6 * 3600
    private static let locatingTimeout: TimeInterval = 60
    /// The network usually isn't back yet at the moment the Mac wakes.
    private static let wakeDelay: Duration = .seconds(5)

    private(set) var status = WeatherStatus.disabled
    private(set) var latest: WeatherReport?

    /// Whether at least one island is on screen, as opposed to hidden by a full screen app.
    @ObservationIgnored var islandIsVisible = true

    @ObservationIgnored private let client = OpenMeteoClient()
    @ObservationIgnored private let cache = WeatherCache()
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Halo", category: "Weather")
    @ObservationIgnored private var manager: CLLocationManager?
    @ObservationIgnored private var location: CLLocation?
    @ObservationIgnored private var fetchedLocation: CLLocation?
    @ObservationIgnored private var locatingSince: Date?
    @ObservationIgnored private var fetch: Task<Void, Never>?
    @ObservationIgnored private var wakeRefresh: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var retryAt: Date?

    func setEnabled(_ enabled: Bool) {
        if enabled {
            guard manager == nil else { return }
            status = .starting
            latest = cache.load()
            let manager = CLLocationManager()
            manager.desiredAccuracy = kCLLocationAccuracyReduced
            // Setting the delegate reports the current authorization, on this thread's run loop.
            manager.delegate = self
            self.manager = manager
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.didWake() }
            }
        } else {
            manager?.stopMonitoringSignificantLocationChanges()
            manager?.delegate = nil
            manager = nil
            if let wakeObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            }
            wakeObserver = nil
            status = .disabled
            forgetEverything()
        }
    }

    /// Fetches the weather if the last report is old enough, and if the last failure is old enough.
    func refreshIfNeeded() {
        guard let manager, isAuthorized(manager), isOutdated, canContactService, fetch == nil else { return }
        if let locatingSince, Date.now.timeIntervalSince(locatingSince) < Self.locatingTimeout { return }
        locatingSince = .now
        manager.requestLocation()
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else { return }
        NSWorkspace.shared.open(url)
    }

    /// The report to show at this date, if it's still meaningful.
    func report(at date: Date) -> WeatherReport? {
        guard let latest, date.timeIntervalSince(latest.fetchedAt) < Self.displayLifetime else { return nil }
        return latest
    }

    // MARK: - Decisions

    private var isOutdated: Bool {
        guard let latest else { return true }
        return Date.now.timeIntervalSince(latest.fetchedAt) >= Self.refreshInterval
    }

    private var canContactService: Bool {
        retryAt.map { Date.now >= $0 } ?? true
    }

    private func isAuthorized(_ manager: CLLocationManager) -> Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: true
        default: false
        }
    }

    private func didWake() {
        wakeRefresh?.cancel()
        wakeRefresh = Task { [weak self] in
            try? await Task.sleep(for: Self.wakeDelay)
            guard let self, !Task.isCancelled, self.islandIsVisible else { return }
            self.refreshIfNeeded()
        }
    }

    // MARK: - Location

    private func authorizationChanged() {
        guard let manager else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            status = .starting
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            if status != .active {
                status = latest != nil && !isOutdated ? .active : .starting
            }
            manager.startMonitoringSignificantLocationChanges()
            refreshIfNeeded()
        case .denied, .restricted:
            manager.stopMonitoringSignificantLocationChanges()
            // Also what apps get when Location Services are off for the whole Mac.
            status = CLLocationManager.locationServicesEnabled() ? .denied : .locationOff
            forgetEverything()
        @unknown default:
            status = .denied
            forgetEverything()
        }
        logger.notice("Location authorization changed: \(manager.authorizationStatus.rawValue, privacy: .public)")
    }

    private func located(_ newLocation: CLLocation) {
        let wasRequested = locatingSince != nil
        locatingSince = nil
        location = newLocation
        logger.notice("Location updated, requested: \(wasRequested, privacy: .public)")
        if wasRequested {
            startFetching()
        } else if hasMovedFar(newLocation), islandIsVisible, canContactService {
            startFetching()
        }
    }

    private func hasMovedFar(_ newLocation: CLLocation) -> Bool {
        guard let fetchedLocation, newLocation.distance(from: fetchedLocation) >= Self.significantDistance else { return false }
        guard let latest else { return true }
        return Date.now.timeIntervalSince(latest.fetchedAt) >= Self.minimumIntervalAfterMoving
    }

    private func locationFailed(code: CLError.Code?) {
        let wasRequested = locatingSince != nil
        locatingSince = nil
        logger.notice("Location failed with code \(code?.rawValue ?? -1, privacy: .public)")
        guard wasRequested, code != .denied else { return }
        // Where the Mac was a moment ago is still a good place to ask about.
        if location != nil {
            startFetching()
        } else if latest == nil || isOutdated {
            status = .locationNotFound
        }
    }

    // MARK: - Fetching

    private func startFetching() {
        guard let location, fetch == nil else { return }
        let coordinate = location.coordinate
        let (latitude, longitude) = (coordinate.latitude, coordinate.longitude)
        fetch = Task { [weak self, client] in
            let report = try? await client.report(latitude: latitude, longitude: longitude)
            guard let self, !Task.isCancelled else { return }
            self.fetch = nil
            if let report {
                self.fetched(report, at: location)
            } else {
                self.fetchFailed()
            }
        }
    }

    private func fetched(_ report: WeatherReport, at location: CLLocation) {
        latest = report
        fetchedLocation = location
        failures = 0
        retryAt = nil
        status = .active
        cache.store(report)
        logger.notice("Weather updated")
    }

    /// 5 min, then 10, 20, 40, and at most an hour. Later attempts wait for the next refresh.
    private func fetchFailed() {
        let delay = min(5 * 60 * pow(2, Double(failures)), 3600)
        failures += 1
        let date = Date.now.addingTimeInterval(delay)
        retryAt = date
        status = .unavailable(retryAt: date)
        logger.notice("Open-Meteo is unavailable, waiting \(Int(delay), privacy: .public) s")
    }

    private func forgetEverything() {
        fetch?.cancel()
        fetch = nil
        wakeRefresh?.cancel()
        wakeRefresh = nil
        latest = nil
        location = nil
        fetchedLocation = nil
        locatingSince = nil
        failures = 0
        retryAt = nil
        cache.remove()
    }

    #if DEBUG
    /// Shows a made-up report, to check the views without a location.
    func showSample(_ report: WeatherReport) {
        status = .active
        latest = report
    }
    #endif
}

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationChanged()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.located(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let code = (error as? CLError)?.code
        Task { @MainActor in
            self.locationFailed(code: code)
        }
    }
}
