import CryptoKit
import Foundation

/// Disk cache of LRCLIB results, one small JSON file per track in Application Support.
///
/// Tracks without lyrics are cached too, so they aren't looked up again every time they play,
/// but only for a while: lyrics may be added to LRCLIB later.
struct LyricsCache: Sendable {
    private struct Entry: Codable {
        var syncedLyrics: String?
        var instrumental: Bool
        var date: Date
        /// How long a "no lyrics" result stays valid. Missing in entries written by older versions.
        var lifetime: TimeInterval?
    }

    static let notFoundLifetime: TimeInterval = 7 * 24 * 3600

    let directory: URL = URL.applicationSupportDirectory
        .appending(path: AppInfo.name, directoryHint: .isDirectory)
        .appending(path: "Lyrics", directoryHint: .isDirectory)

    func result(for query: LRCLIBClient.Query) -> LyricsLookupResult? {
        guard let data = try? Data(contentsOf: fileURL(for: query)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data)
        else { return nil }
        if let lyrics = entry.syncedLyrics { return .synced(lyrics) }
        if entry.instrumental { return .instrumental }
        let lifetime = entry.lifetime ?? Self.notFoundLifetime
        return Date.now.timeIntervalSince(entry.date) < lifetime ? .notFound : nil
    }

    func store(_ result: LyricsLookupResult, for query: LRCLIBClient.Query, lifetime: TimeInterval = notFoundLifetime) {
        var entry = Entry(syncedLyrics: nil, instrumental: false, date: .now, lifetime: lifetime)
        switch result {
        case .synced(let lyrics): entry.syncedLyrics = lyrics
        case .instrumental: entry.instrumental = true
        case .notFound: break
        }
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: query), options: .atomic)
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The file name is a hash of the normalized track identity: no track names on disk paths.
    private func fileURL(for query: LRCLIBClient.Query) -> URL {
        let identity = [
            query.title, query.artist, query.album,
            query.duration.map { String(Int($0.rounded())) } ?? "",
        ]
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .joined(separator: "\u{1F}")
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: "\(hash).json")
    }
}
