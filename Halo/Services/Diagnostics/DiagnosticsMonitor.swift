import Foundation
import OSLog

/// Resource usage of a process, ready to display.
struct ProcessUsage: Equatable {
    /// Share of one processor core, from 0 to 1 per core. Nil until two samples are available.
    var cpu: Double?
    var memory: UInt64
    var peakMemory: UInt64?
}

/// Measures Halo's resource usage, only for as long as `run()` is running.
@MainActor
@Observable
final class DiagnosticsMonitor {
    private static let interval = Duration.seconds(2)

    private(set) var app: ProcessUsage?
    /// Usage of the process that reads MediaRemote, when it is the one in use.
    private(set) var helper: ProcessUsage?

    @ObservationIgnored private let nowPlaying: NowPlayingService
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Halo", category: "Diagnostics")
    @ObservationIgnored private var previousApp: (sample: ProcessSample, time: TimeInterval)?
    @ObservationIgnored private var previousHelper: (identifier: pid_t, sample: ProcessSample, time: TimeInterval)?

    init(nowPlaying: NowPlayingService) {
        self.nowPlaying = nowPlaying
    }

    /// Samples until the calling task is cancelled.
    func run() async {
        logger.notice("Measuring started")
        defer {
            previousApp = nil
            previousHelper = nil
            logger.notice("Measuring stopped")
        }
        while !Task.isCancelled {
            sample()
            try? await Task.sleep(for: Self.interval)
        }
    }

    private func sample() {
        let now = ProcessInfo.processInfo.systemUptime

        if let sample = ProcessMetrics.currentProcess() {
            app = ProcessUsage(
                cpu: previousApp.map { Self.cpu(from: $0.sample, to: sample, over: now - $0.time) },
                memory: sample.memory,
                peakMemory: sample.peakMemory
            )
            previousApp = (sample, now)
        }

        if let identifier = nowPlaying.helperProcessIdentifier, let sample = ProcessMetrics.process(identifier) {
            let previous = previousHelper?.identifier == identifier ? previousHelper : nil
            helper = ProcessUsage(
                cpu: previous.map { Self.cpu(from: $0.sample, to: sample, over: now - $0.time) },
                memory: sample.memory,
                peakMemory: nil
            )
            previousHelper = (identifier, sample, now)
        } else {
            helper = nil
            previousHelper = nil
        }
    }

    private static func cpu(from start: ProcessSample, to end: ProcessSample, over duration: TimeInterval) -> Double {
        duration > 0 ? max(end.cpuTime - start.cpuTime, 0) / duration : 0
    }
}
