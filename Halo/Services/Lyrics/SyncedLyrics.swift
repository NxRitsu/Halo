import Foundation

/// Lyrics with a timestamp on each line, parsed from the LRC format.
struct SyncedLyrics: Hashable {
    struct Line: Hashable {
        var time: TimeInterval
        /// Empty for an instrumental break.
        var text: String
    }

    let lines: [Line]

    /// Parses LRC text, for instance `[01:02.50]Some words`.
    ///
    /// A line may carry several timestamps (`[00:10.00][00:42.00]Chorus`). Metadata tags such as
    /// `[ar:Artist]` are ignored, except `[offset:±ms]` which shifts every line.
    /// Returns nil when the text contains no timed line.
    init?(lrc: String) {
        var offset: TimeInterval = 0
        var lines: [Line] = []

        for rawLine in lrc.split(whereSeparator: \.isNewline) {
            var rest = Substring(rawLine)
            var times: [TimeInterval] = []
            while rest.first == "[", let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let time = Self.parseTimestamp(tag) {
                    times.append(time)
                } else if tag.lowercased().hasPrefix("offset:"),
                          let milliseconds = Double(tag.dropFirst("offset:".count).trimmingCharacters(in: .whitespaces)) {
                    // A positive offset makes the lyrics appear sooner.
                    offset = -milliseconds / 1000
                }
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            lines += times.map { Line(time: $0, text: text) }
        }

        guard !lines.isEmpty else { return nil }
        self.lines = lines
            .map { Line(time: max($0.time + offset, 0), text: $0.text) }
            .sorted { $0.time < $1.time }
    }

    /// Parses `mm:ss`, `mm:ss.xx` or `mm:ss:xx`.
    private static func parseTimestamp(_ tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let minutes = Int(parts[0]),
              let seconds = Double(parts[1].replacingOccurrences(of: ":", with: "."))
        else { return nil }
        return TimeInterval(minutes * 60) + seconds
    }

    /// Index of the line being sung at the given playback position, or nil before the first line.
    func lineIndex(at time: TimeInterval) -> Int? {
        // Binary search for the last line that starts at or before `time`.
        var low = 0
        var high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].time <= time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low == 0 ? nil : low - 1
    }

    /// Start time of the line following the given one.
    func nextLineTime(after index: Int?) -> TimeInterval? {
        let next = (index ?? -1) + 1
        return next < lines.count ? lines[next].time : nil
    }
}
