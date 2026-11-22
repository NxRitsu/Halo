import AppKit
import OSLog

/// Sends what is dropped on the island with AirDrop, through the public sharing service of macOS.
///
/// Files are sent from where they are: nothing is copied. Some apps only promise a file while it is
/// dragged (a photo from Photos, an image from a web page). Those are written to a temporary
/// folder first, which is deleted once AirDrop is done with it, and at launch in case Halo quit
/// in the middle of a transfer.
@MainActor
final class AirDropService: NSObject {
    private static let readingOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    private static let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Halo", category: "AirDrop")
    /// Services showing their window, with the temporary folder of their promised files.
    private var transfers: [ObjectIdentifier: (service: NSSharingService, folder: URL?)] = [:]

    private var temporaryRoot: URL {
        // The temporary folder is shared with other apps: the name must be Halo's own.
        let name = "\(Bundle.main.bundleIdentifier ?? AppInfo.name).AirDrop"
        return FileManager.default.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)
    }

    /// Whether this Mac has AirDrop. When Wi-Fi or Bluetooth is off, the AirDrop window says so.
    var isAvailable: Bool {
        NSSharingService(named: .sendViaAirDrop) != nil
    }

    /// The AirDrop icon, as macOS draws it in its sharing menus.
    var icon: NSImage? {
        NSSharingService(named: .sendViaAirDrop)?.image
    }

    func start() {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    /// Number of files in a drag, or 0 if it holds none (some text, a link to a web page…).
    static func fileCount(in pasteboard: NSPasteboard) -> Int {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: readingOptions) ?? []
        if !urls.isEmpty { return urls.count }
        let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver] ?? []
        return promises.reduce(0) { $0 + max($1.fileNames.count, 1) }
    }

    /// Opens the AirDrop window for the files of a drop.
    func send(from pasteboard: NSPasteboard) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: Self.readingOptions) as? [URL] ?? []
        if !urls.isEmpty {
            share(urls, folder: nil)
            return
        }
        let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver] ?? []
        guard !promises.isEmpty else { return }
        let folder = temporaryRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            logger.error("Can't create the folder for promised files")
            return
        }
        // The receiving starts during the drop, while the source app still holds the files.
        let expected = promises.reduce(0) { $0 + max($1.fileNames.count, 1) }
        let collector = PromiseCollector(expected: expected) { [weak self] received in
            Task { @MainActor in self?.promisedFilesArrived(received, in: folder) }
        }
        for promise in promises {
            promise.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: Self.promiseQueue) { url, error in
                collector.add(error == nil ? url : nil)
            }
        }
    }

    private func promisedFilesArrived(_ urls: [URL], in folder: URL) {
        guard !urls.isEmpty else {
            logger.error("The promised files never arrived")
            try? FileManager.default.removeItem(at: folder)
            return
        }
        share(urls, folder: folder)
    }

    private func share(_ urls: [URL], folder: URL?) {
        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            logger.error("AirDrop is unavailable")
            if let folder { try? FileManager.default.removeItem(at: folder) }
            return
        }
        guard service.canPerform(withItems: urls) else {
            logger.error("AirDrop can't send these items")
            if let folder { try? FileManager.default.removeItem(at: folder) }
            return
        }
        service.delegate = self
        transfers[ObjectIdentifier(service)] = (service, folder)
        // Halo has no windows of its own: it must be active for the AirDrop window to come forward.
        NSApp.activate()
        service.perform(withItems: urls)
        logger.notice("AirDrop window opened for \(urls.count) item(s)")
    }

    private func finished(_ service: NSSharingService, sent: Bool) {
        if sent {
            logger.notice("AirDrop sent the items")
        } else {
            logger.notice("AirDrop was cancelled or failed")
        }
        guard let transfer = transfers.removeValue(forKey: ObjectIdentifier(service)) else { return }
        if let folder = transfer.folder {
            try? FileManager.default.removeItem(at: folder)
        }
    }
}

extension AirDropService: NSSharingServiceDelegate {
    nonisolated func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        nonisolated(unsafe) let service = sharingService
        Task { @MainActor in self.finished(service, sent: true) }
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        nonisolated(unsafe) let service = sharingService
        Task { @MainActor in self.finished(service, sent: false) }
    }
}

/// Gathers promised files, which arrive one by one on a background queue.
private final class PromiseCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    private var urls: [URL] = []
    private var completion: (@Sendable ([URL]) -> Void)?

    init(expected: Int, completion: @escaping @Sendable ([URL]) -> Void) {
        remaining = expected
        self.completion = completion
    }

    func add(_ url: URL?) {
        lock.lock()
        if let url { urls.append(url) }
        remaining -= 1
        let done = remaining <= 0 ? completion : nil
        if done != nil { completion = nil }
        let result = urls
        lock.unlock()
        done?(result)
    }
}
