import Foundation
import os

/// Location of the MediaRemote helper library and its Perl loader inside the app bundle.
enum MediaRemoteHelper {
    static var libraryURL: URL? {
        Bundle.main.privateFrameworksURL?.appending(path: "MediaRemoteHelper.framework/MediaRemoteHelper")
    }

    static var scriptURL: URL? {
        Bundle.main.url(forResource: "media-remote", withExtension: "pl")
    }

    /// Whether MediaRemote returns now playing information to Halo's own process.
    ///
    /// Since macOS 15.4 it returns nothing to unentitled processes. Nothing is also returned when
    /// nothing is playing, so a negative answer means "use the helper process", which works in
    /// both cases.
    static func isDirectlyAccessible() async -> Bool {
        typealias GetNowPlayingInfo = @convention(c) (DispatchQueue, @escaping @convention(block) (NSDictionary?) -> Void) -> Void
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY),
              let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo")
        else { return false }
        let getNowPlayingInfo = unsafeBitCast(symbol, to: GetNowPlayingInfo.self)

        return await withCheckedContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let finish: @Sendable (Bool) -> Void = { result in
                let shouldResume = resumed.withLock { done in
                    defer { done = true }
                    return !done
                }
                if shouldResume {
                    continuation.resume(returning: result)
                }
            }
            getNowPlayingInfo(DispatchQueue.global()) { info in
                finish((info?.count ?? 0) > 0)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                finish(false)
            }
        }
    }
}

/// Receives helper messages from C callbacks and forwards them to the main actor.
private final class HelperMessageSink: Sendable {
    let handler: @MainActor @Sendable (NowPlayingEvent) -> Void

    init(handler: @escaping @MainActor @Sendable (NowPlayingEvent) -> Void) {
        self.handler = handler
    }

    func receive(_ data: Data) {
        guard let event = NowPlayingEvent(helperMessage: data) else { return }
        Task { @MainActor in
            handler(event)
        }
    }
}

/// Runs the helper library inside Halo's process. Only used when MediaRemote is directly accessible.
@MainActor
final class DirectMediaRemoteSource: NowPlayingSource {
    private typealias EmitFunction = @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void
    private typealias StartFunction = @convention(c) (EmitFunction, UnsafeMutableRawPointer?) -> Bool
    private typealias SendCommandFunction = @convention(c) (UnsafePointer<CChar>) -> Void

    let method = NowPlayingMethod.mediaRemoteDirect
    private var sendCommand: SendCommandFunction?
    private var sink: HelperMessageSink?

    func start(_ handler: @escaping @MainActor (NowPlayingEvent) -> Void) {
        guard let path = MediaRemoteHelper.libraryURL?.path,
              let handle = dlopen(path, RTLD_NOW),
              let startSymbol = dlsym(handle, "HaloMediaRemoteStart"),
              let commandSymbol = dlsym(handle, "HaloMediaRemoteSendCommand")
        else {
            handler(.failed("Cannot load the MediaRemote helper library"))
            return
        }
        let sink = HelperMessageSink { event in handler(event) }
        self.sink = sink
        sendCommand = unsafeBitCast(commandSymbol, to: SendCommandFunction.self)

        let start = unsafeBitCast(startSymbol, to: StartFunction.self)
        let emit: EmitFunction = { json, context in
            guard let json, let context else { return }
            let sink = Unmanaged<HelperMessageSink>.fromOpaque(context).takeUnretainedValue()
            sink.receive(Data(String(cString: json).utf8))
        }
        // The helper keeps running for the lifetime of the process, so the sink is retained forever.
        if !start(emit, Unmanaged.passRetained(sink).toOpaque()) {
            handler(.failed("MediaRemote framework unavailable"))
        }
    }

    func stop() {
        // MediaRemote observation cannot be stopped in-process; events are simply ignored by the service.
    }

    func send(_ command: MediaCommand) {
        sendCommand?(command.helperLine)
    }
}

/// Runs the helper library inside `/usr/bin/perl`, which MediaRemote still serves.
@MainActor
final class HelperProcessMediaRemoteSource: NowPlayingSource {
    let method = NowPlayingMethod.mediaRemoteHelper
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var handler: (@MainActor (NowPlayingEvent) -> Void)?

    var processIdentifier: pid_t? {
        process?.processIdentifier
    }

    func start(_ handler: @escaping @MainActor (NowPlayingEvent) -> Void) {
        self.handler = handler
        guard let libraryURL = MediaRemoteHelper.libraryURL, let scriptURL = MediaRemoteHelper.scriptURL else {
            handler(.failed("MediaRemote helper missing from the app bundle"))
            return
        }

        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, libraryURL.path]
        let outputPipe = Pipe()
        let inputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardInput = inputPipe
        process.standardError = FileHandle.nullDevice

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            if data.isEmpty {
                fileHandle.readabilityHandler = nil
            }
            Task { @MainActor in
                self?.consume(data)
            }
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in
                self?.processTerminated(status: status)
            }
        }

        do {
            try process.run()
            self.process = process
            input = inputPipe.fileHandleForWriting
        } catch {
            handler(.failed("Cannot launch /usr/bin/perl: \(error.localizedDescription)"))
        }
    }

    func stop() {
        handler = nil
        // Closing stdin makes the helper exit by itself.
        try? input?.close()
        input = nil
        process?.terminate()
        process = nil
        buffer.removeAll()
    }

    func send(_ command: MediaCommand) {
        try? input?.write(contentsOf: Data((command.helperLine + "\n").utf8))
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let event = NowPlayingEvent(helperMessage: Data(line)) {
                handler?(event)
            }
        }
    }

    private func processTerminated(status: Int32) {
        guard process != nil else { return }
        process = nil
        handler?(.failed("The MediaRemote helper exited (status \(status))"))
    }
}
