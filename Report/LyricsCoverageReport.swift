import Foundation
import RingRingCore
import RingRingLyrics
import RingRingMusic
import Testing

/// How many of each artist's songs LRCLIB gives lyrics for, by artist.
///
/// A handful of each artist's catalogue songs, asked one at a time with a
/// three-second pause — LRCLIB is a free community server, and at a 0.4s
/// pace it answered 429/503 to this address for 165 of 380 songs. The run
/// stops at the second throttled answer in a row.
///
/// The catalogue lists an artist's newest songs first, so this samples new
/// releases — the songs LRCLIB is least likely to have yet. Outcomes are cached on disk
/// (`RINGRING_EVAL_DIR`), so a rerun only asks for what changed: delete
/// `lyrics-<artist id>.json` to ask an artist again. Artists:
/// `RINGRING_EVAL_GROUPS` (ids or names), else every artist on the roster.
@Suite("가사 커버리지 보고서", .serialized)
struct LyricsCoverageReportSuite {
    private static let songsPerArtist = 4

    private var cacheDir: URL {
        let env = ProcessInfo.processInfo.environment["RINGRING_EVAL_DIR"]
        let dir = env.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("eval")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private struct Outcome: Codable {
        let title: String
        let artist: String
        let found: Bool
        let detail: String
    }

    @Test("아티스트별로 가사를 찾은 곡 수")
    func writeLyricsCoverageReport() async throws {
        let catalog = ITunesCatalog()
        let lyrics = LRCLIBClient()
        let wanted = ProcessInfo.processInfo.environment["RINGRING_EVAL_GROUPS"]
            .map { $0.split(separator: ",").map(String.init) }
        let groups = IdolGroup.all.filter { group in
            wanted.map { $0.contains(group.id) || $0.contains(group.name) } ?? true
        }

        var lines: [String] = []
        var found = 0, total = 0
        var busyInARow = 0
        artists: for group in groups {
            let file = cacheDir.appendingPathComponent("lyrics-\(group.id).json")
            var outcomes: [Outcome]
            if let data = try? Data(contentsOf: file), let cached = try? JSONDecoder().decode([Outcome].self, from: data) {
                outcomes = cached
            } else {
                outcomes = []
                let songs = (try? await catalog.songs(forArtist: group.id, limit: 30)) ?? []
                for song in songs.prefix(Self.songsPerArtist) {
                    do {
                        let sheet = try await lyrics.lyrics(artist: song.artist, title: song.title, album: song.album, duration: song.duration)
                        outcomes.append(.init(title: song.title, artist: song.artist, found: true, detail: sheet.isSynced ? "synced" : "plain"))
                        busyInARow = 0
                    } catch LRCLIBClient.Failure.serverBusy(let status) {
                        // Throttled: an answer about this address, not the song.
                        busyInARow += 1
                        outcomes.append(.init(title: song.title, artist: song.artist, found: false, detail: "serverBusy(\(status))"))
                        if busyInARow >= 2 {
                            lines.append("— LRCLIB is throttling (\(status)); stopped at \(group.name). Rerun later; finished artists are cached.")
                            break artists
                        }
                    } catch {
                        outcomes.append(.init(title: song.title, artist: song.artist, found: false, detail: "\(error)"))
                        busyInARow = 0
                    }
                    try await Task.sleep(for: .seconds(3))
                }
                // A throttled answer is not a result; that artist is asked
                // again on the next run.
                if !outcomes.contains(where: { $0.detail.hasPrefix("serverBusy") }) {
                    try? JSONEncoder().encode(outcomes).write(to: file)
                }
            }
            let hits = outcomes.filter(\.found).count
            found += hits
            total += outcomes.count
            lines.append("\(hits)/\(outcomes.count)  \(group.name) [\(group.label)]")
            for miss in outcomes where !miss.found {
                lines.append("      ✗ \(miss.title) — catalogue artist 「\(miss.artist)」 · \(miss.detail)")
            }
        }
        print("=== LYRICS COVERAGE BEGIN ===")
        print(lines.joined(separator: "\n"))
        print("\n--- 요약: \(total)곡 중 \(found)곡 ---")
        print("=== LYRICS COVERAGE END ===")
    }
}
