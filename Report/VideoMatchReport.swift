import Foundation
import RingRingCore
import Testing

@testable import RingRingMusic

/// Which video each song gets from its group's channels, printed for review.
///
/// Not a test of quality — a wrong pick is only visible to a person reading
/// the titles — but the evidence that a scoring change is judged on. It runs
/// the app's own ranking and length filter over real uploads, so what it prints
/// is what a reader would be played.
///
/// Uploads and lengths are cached on disk (`RINGRING_EVAL_DIR`, else the app's
/// caches), so a rerun after changing the scoring costs no YouTube quota.
/// Groups: `RINGRING_EVAL_GROUPS` as comma-separated catalogue ids, else a
/// spread across the roster.
@Suite("영상 매칭 보고서", .serialized)
@MainActor
struct VideoMatchReportSuite {
    private static let defaultGroups = [
        "FRUITS ZIPPER", "CANDY TUNE", "SWEET STEADY", "CUTIE STREET", "=LOVE", "≠ME",
        "日向坂46", "乃木坂46", "AKB48", "iLiFE!", "Snow Man", "YOASOBI", "Mrs. GREEN APPLE", "LiSA",
    ]

    private var cacheDir: URL {
        let env = ProcessInfo.processInfo.environment["RINGRING_EVAL_DIR"]
        let dir = env.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("eval")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cached<T: Codable>(_ name: String, _ make: () async throws -> T) async throws -> T {
        let file = cacheDir.appendingPathComponent(name)
        if let data = try? Data(contentsOf: file), let value = try? JSONDecoder().decode(T.self, from: data) {
            return value
        }
        let value = try await make()
        try JSONEncoder().encode(value).write(to: file)
        return value
    }

    @Test("그룹 채널에서 곡마다 어떤 영상이 골리는지")
    func writeVideoMatchReport() async throws {
        let youtube = YouTubeClient()
        let catalog = ITunesCatalog()
        let wanted = ProcessInfo.processInfo.environment["RINGRING_EVAL_GROUPS"]
            .map { $0.split(separator: ",").map(String.init) }
        let groups = IdolGroup.all.filter { group in
            wanted.map { $0.contains(group.id) || $0.contains(group.name) } ?? Self.defaultGroups.contains(group.name)
        }

        var lines: [String] = []
        var picked = 0, missed = 0, total = 0
        for group in groups {
            let songs: [Track] = try await cached("songs-\(group.id).json") {
                Array(try await catalog.songs(forArtist: group.id, limit: 30))
            }
            var uploads: [YouTubeClient.Candidate] = []
            for channel in group.youtubeChannels {
                uploads += (try? await cached("uploads-\(channel).json") {
                    try await youtube.uploads(ofChannel: channel)
                }) ?? []
            }
            // Lengths only for uploads that name one of the songs.
            let named = Set(songs.flatMap { YouTubeClient.rankAll(uploads, for: $0, channels: group.youtubeChannels).prefix(50).map(\.videoID) })
            var lengths: [String: TimeInterval] = (try? await cached("lengths-\(group.id).json") { [String: TimeInterval]() }) ?? [:]
            let missing = named.subtracting(lengths.keys)
            if !missing.isEmpty, let found = try? await youtube.durations(of: Array(missing)) {
                lengths.merge(found) { $1 }
                for id in missing where lengths[id] == nil { lengths[id] = -1 }
                try? JSONEncoder().encode(lengths).write(to: cacheDir.appendingPathComponent("lengths-\(group.id).json"))
            }

            lines.append("\n## \(group.name) — uploads \(uploads.count)")
            for song in songs {
                total += 1
                let ranked = YouTubeClient.rankAll(uploads, for: song, channels: group.youtubeChannels)
                let choice = YouTubeClient.byLength(ranked, track: song, durations: lengths.filter { $0.value > 0 }).first
                let scores = Dictionary(
                    YouTubeClient.scored(uploads, for: song, channels: group.youtubeChannels, strict: true).map { ($0.candidate.videoID, $0.score) },
                    uniquingKeysWith: max
                )
                func describe(_ c: YouTubeClient.Candidate) -> String {
                    let length = lengths[c.videoID].map { $0 > 0 ? "\(Int($0))s" : "?" } ?? "-"
                    return "[\(scores[c.videoID] ?? 0)] \(c.title) ‹\(c.channelTitle)› \(length)"
                }
                guard let choice else {
                    missed += 1
                    lines.append("✗ \(song.title) (\(Int(song.duration))s) — nothing on the channels" + (ranked.isEmpty ? "" : " of its length (\(ranked.count) named it)"))
                    continue
                }
                picked += 1
                lines.append("✓ \(song.title) (\(Int(song.duration))s) → \(describe(choice))")
                for other in ranked.filter({ $0 != choice }).prefix(3) {
                    lines.append("      · \(describe(other))")
                }
            }
        }
        print("=== VIDEO MATCH BEGIN ===")
        print(lines.joined(separator: "\n"))
        print("\n--- 요약: 곡 \(total), 채널에서 고름 \(picked), 못 찾음 \(missed) ---")
        print("=== VIDEO MATCH END ===")
    }
}
