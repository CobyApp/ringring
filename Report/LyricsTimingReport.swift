import Foundation
import RingRingCore
import RingRingLyrics
import Testing

/// How long a reader waits on 「Finding lyrics」, hit and miss, against the live
/// LRCLIB. Prints, asserts nothing: the network sets the numbers, and the point
/// is comparing two runs of the same songs.
@Suite("가사 찾기 대기 시간 보고서", .serialized)
struct LyricsTimingReportSuite {
    private static let songs: [(artist: String, title: String, duration: TimeInterval)] = [
        // Not on LRCLIB (2026-10): every spelling is asked before giving up.
        ("FRUITS ZIPPER", "秘密のアティチュード", 212),
        ("FRUITS ZIPPER", "1,2,3,FOOOOUR", 207),
        ("SWEET STEADY", "すいすてたいむ", 278),
        // On LRCLIB.
        ("SWEET STEADY", "YAKIMOCHI", 193),
        ("FRUITS ZIPPER", "わたしの一番かわいいところ", 262),
        ("SWEET STEADY", "なりたい私", 221),
    ]

    @Test("곡마다 가사를 찾는 데 걸린 시간")
    func writeLyricsTimingReport() async {
        let client = LRCLIBClient()
        var lines: [String] = []
        for song in Self.songs {
            let start = ContinuousClock.now
            let outcome: String
            do {
                let lyrics = try await client.lyrics(artist: song.artist, title: song.title, duration: song.duration)
                outcome = "found \(lyrics.lines.count) lines" + (lyrics.isSynced ? " (synced)" : "")
            } catch {
                outcome = "\(error)"
            }
            let elapsed = ContinuousClock.now - start
            lines.append("\(song.artist) — \(song.title): \(elapsed.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow))) · \(outcome)")
        }
        print("=== LYRICS TIMING BEGIN ===")
        print(lines.joined(separator: "\n"))
        print("=== LYRICS TIMING END ===")
    }
}
