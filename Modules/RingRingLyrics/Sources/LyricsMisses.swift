import Foundation

/// Songs LRCLIB recently had no lyrics for, by catalogue id.
///
/// A song without lyrics cost up to nine requests every time it was opened —
/// every spelling, and each one's free-text fallback — and LRCLIB is a free
/// community server that answers 429 when one address asks too much. A
/// 「none」 is trusted for three days: long enough that reopening the song
/// costs nothing, short enough that lyrics someone uploads in the meantime are
/// found. The 「Search again」 button on the not-found card always asks.
///
/// Only a real 「not found」 is kept. A busy server or a dropped connection
/// says nothing about the song.
public struct LyricsMisses: Sendable {
    public static let freshFor: TimeInterval = 60 * 60 * 24 * 3

    private let file: URL
    private var missedAt: [String: Date]

    public init(file: URL = LyricsMisses.defaultFile) {
        self.file = file
        missedAt = (try? JSONDecoder().decode([String: Date].self, from: Data(contentsOf: file))) ?? [:]
    }

    public static var defaultFile: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lyrics-misses.json")
    }

    public func isRecent(_ trackID: String, now: Date = .now) -> Bool {
        guard let at = missedAt[trackID] else { return false }
        return now.timeIntervalSince(at) <= Self.freshFor
    }

    public mutating func record(_ trackID: String, at date: Date = .now) {
        missedAt[trackID] = date
        // Old entries go as new ones arrive, so the file stays small.
        missedAt = missedAt.filter { date.timeIntervalSince($0.value) <= Self.freshFor }
        save()
    }

    public mutating func forget(_ trackID: String) {
        guard missedAt.removeValue(forKey: trackID) != nil else { return }
        save()
    }

    private func save() {
        try? JSONEncoder().encode(missedAt).write(to: file, options: .atomic)
    }
}
