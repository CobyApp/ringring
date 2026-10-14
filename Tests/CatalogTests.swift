import Foundation
import RingRingCore
@testable import RingRingMusic
import Testing
import UIKit
@testable import RingRingDesign

@Suite("iTunes 카탈로그")
struct ITunesCatalogTests {
    private let payload = """
    {"resultCount":5,"results":[
      {"wrapperType":"artist","artistName":"FRUITS ZIPPER"},
      {"wrapperType":"track","kind":"song","trackId":1,"trackName":"わたしの一番かわいいところ","artistName":"FRUITS ZIPPER","collectionName":"A","artworkUrl100":"https://x/100x100bb.jpg","trackTimeMillis":255000,"releaseDate":"2022-04-01T12:00:00Z"},
      {"wrapperType":"track","kind":"song","trackId":2,"trackName":"わたしの一番かわいいところ (Instrumental)","artistName":"FRUITS ZIPPER","trackTimeMillis":255000,"releaseDate":"2022-04-01T12:00:00Z"},
      {"wrapperType":"track","kind":"song","trackId":3,"trackName":"わたしの一番かわいいところ (2024 ver.)","artistName":"FRUITS ZIPPER","trackTimeMillis":250000,"releaseDate":"2024-01-01T12:00:00Z"},
      {"wrapperType":"track","kind":"song","trackId":4,"trackName":"NEW KAWAII","artistName":"FRUITS ZIPPER","trackTimeMillis":266000,"releaseDate":"2024-06-01T12:00:00Z"}
    ]}
    """.data(using: .utf8)!

    @Test("노래만, 한 곡에 한 행, 새 것부터, 큰 커버")
    func tracks() throws {
        let decoded = try JSONDecoder().decode(ITunesCatalog.Payload.self, from: payload)
        let tracks = ITunesCatalog.tracks(from: decoded, limit: 40)
        #expect(tracks.map(\.title) == ["NEW KAWAII", "わたしの一番かわいいところ (2024 ver.)"])
        #expect(tracks.map(\.id) == ["4", "3"])
        #expect(tracks[0].duration == 266)
    }

    /// =LOVE's page opened on its tour album: the newest release of every
    /// song it played that night, plus a Korean version at the very top.
    @Test("라이브·외국어 버전보다 스튜디오 원곡이 목록에 선다")
    func prefersTheStudioRecording() throws {
        let tour = """
        {"resultCount":5,"results":[
          {"wrapperType":"track","kind":"song","trackId":10,"trackName":"僕のヒロイン","collectionName":"僕のヒロイン - Single","trackTimeMillis":200000,"releaseDate":"2023-01-01T12:00:00Z"},
          {"wrapperType":"track","kind":"song","trackId":11,"trackName":"僕のヒロイン (=LOVE 8th ANNIVERSARY PREMIUM TOUR)","collectionName":"=LOVE 8th ANNIVERSARY PREMIUM TOUR","trackTimeMillis":210000,"releaseDate":"2025-09-01T12:00:00Z"},
          {"wrapperType":"track","kind":"song","trackId":12,"trackName":"恋、はじめました。","collectionName":"恋、はじめました。 - Single","trackTimeMillis":220000,"releaseDate":"2025-03-01T12:00:00Z"},
          {"wrapperType":"track","kind":"song","trackId":13,"trackName":"恋、はじめました。 (Korean ver.)","collectionName":"恋、はじめました。 (Korean ver.) - Single","trackTimeMillis":220000,"releaseDate":"2025-10-01T12:00:00Z"},
          {"wrapperType":"track","kind":"song","trackId":14,"trackName":"青春サブリミナル","collectionName":"=LOVE LIVE TOUR","trackTimeMillis":300000,"releaseDate":"2025-09-01T12:00:00Z"}
        ]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ITunesCatalog.Payload.self, from: tour)
        let tracks = ITunesCatalog.tracks(from: decoded, limit: 40)
        // The live take stays only where it is the song's one recording.
        #expect(tracks.map(\.id) == ["14", "12", "10"])
        #expect(!tracks.contains { $0.title.contains("Korean") })
    }

    @Test("한국어·영어 버전은 일본어가 아니다")
    func otherLanguages() {
        #expect(ITunesCatalog.isOtherLanguage("恋、はじめました。 (Korean ver.)"))
        #expect(ITunesCatalog.isOtherLanguage("Chu Chu - English Version"))
        #expect(!ITunesCatalog.isOtherLanguage("恋、はじめました。"))
    }

    @Test("Instrumental·off vocal은 공부할 게 없다")
    func unsingable() {
        #expect(ITunesCatalog.isUnsingable("かがみ (Instrumental)"))
        #expect(ITunesCatalog.isUnsingable("かがみ -off vocal-"))
        #expect(!ITunesCatalog.isUnsingable("かがみ"))
    }

    @Test("아티스트 페이지의 og:image를 정사각 사진으로")
    func portrait() {
        let html = #"<meta property="og:image" content="https://is1-ssl.mzstatic.com/image/thumb/abc/1200x630cw.png">"#
        #expect(ITunesCatalog.portraitURL(inPage: html)?.absoluteString == "https://is1-ssl.mzstatic.com/image/thumb/abc/800x800cc.png")
        #expect(ITunesCatalog.portraitURL(inPage: "<html></html>") == nil)
    }

    @Test("100pt 커버를 600pt로")
    func artwork() {
        #expect(ITunesCatalog.largeArtwork("https://x/100x100bb.jpg") == "https://x/600x600bb.jpg")
    }
}

@Suite("YouTube 영상 고르기")
struct YouTubeClientTests {
    private let track = Track(id: "1", title: "わたしの一番かわいいところ", artist: "FRUITS ZIPPER", duration: 255)

    @Test("공식 MV가 댄스 프랙티스와 라이브를 이긴다")
    func choosesOfficialVideo() {
        let candidates = [
            YouTubeClient.Candidate(videoID: "dance", title: "FRUITS ZIPPER「わたしの一番かわいいところ」Dance Practice", channelTitle: "FRUITS ZIPPER"),
            YouTubeClient.Candidate(videoID: "mv", title: "FRUITS ZIPPER「わたしの一番かわいいところ」Music Video", channelTitle: "FRUITS ZIPPER"),
            YouTubeClient.Candidate(videoID: "live", title: "わたしの一番かわいいところ / FRUITS ZIPPER LIVE", channelTitle: "someone"),
        ]
        #expect(YouTubeClient.choose(candidates, for: track)?.videoID == "mv")
    }

    @Test("ISO 8601 길이를 초로")
    func parsesDuration() {
        #expect(YouTubeClient.parseDuration("PT3M28S") == 208)
        #expect(YouTubeClient.parseDuration("PT24S") == 24)
        #expect(YouTubeClient.parseDuration("PT1H2M") == 3720)
        #expect(YouTubeClient.parseDuration("P1D") == nil)
    }

    @Test("곡 길이와 어긋나는 영상은 걸러진다")
    func filtersByLength() {
        let short = YouTubeClient.Candidate(videoID: "short", title: "『わたしの一番かわいいところ』MV公開", channelTitle: "FRUITS ZIPPER")
        let mv = YouTubeClient.Candidate(videoID: "mv", title: "【MV】わたしの一番かわいいところ", channelTitle: "KAWAII LAB.")
        let unknown = YouTubeClient.Candidate(videoID: "x", title: "わたしの一番かわいいところ", channelTitle: "Topic")
        let kept = YouTubeClient.byLength([short, mv, unknown], track: track, durations: ["short": 24, "mv": 262])
        #expect(kept.map(\.videoID) == ["mv", "x"])
    }

    @Test("MV 공개 안내 쇼츠는 MV보다 뒤로 간다")
    func announcementsSink() {
        let candidates = [
            YouTubeClient.Candidate(videoID: "short", title: "『わたしの一番かわいいところ』MV公開🚃 #FRUITSZIPPER #ふるっぱー", channelTitle: "FRUITS ZIPPER", channelID: "UCQG8tNnV4hKetLhMb4MopHQ"),
            YouTubeClient.Candidate(videoID: "mv", title: "【MV】FRUITS ZIPPER『わたしの一番かわいいところ』", channelTitle: "KAWAII LAB.", channelID: "UCW8Q9LBGGBgK6a-u0C0h95A"),
            YouTubeClient.Candidate(videoID: "inst", title: "わたしの一番かわいいところ (Instrumental)", channelTitle: "FRUITS ZIPPER - Topic", channelID: "UCB_jIxmkTjjAHyVZUD-kf4w"),
        ]
        let channels = IdolGroup.group(forArtist: "FRUITS ZIPPER")!.youtubeChannels
        let ranked = YouTubeClient.rank(candidates, for: track, channels: channels, strict: true)
        #expect(ranked.first?.videoID == "mv")
        #expect(!ranked.contains { $0.videoID == "inst" })
    }

    @Test("그룹 채널의 영상이 무엇보다 앞선다")
    func groupChannelFirst() {
        let candidates = [
            YouTubeClient.Candidate(videoID: "copy", title: "【MV】FRUITS ZIPPER「わたしの一番かわいいところ」", channelTitle: "someone official"),
            YouTubeClient.Candidate(videoID: "own", title: "わたしの一番かわいいところ", channelTitle: "FRUITS ZIPPER - Topic", channelID: "UCB_jIxmkTjjAHyVZUD-kf4w"),
        ]
        let channels = IdolGroup.group(forArtist: "FRUITS ZIPPER")!.youtubeChannels
        #expect(YouTubeClient.choose(candidates, for: track, channels: channels)?.videoID == "own")
    }

    @Test("업로드 목록은 채널 ID로 정해진다")
    func uploadsPlaylist() {
        #expect(YouTubeClient.uploadsPlaylist(ofChannel: "UCW8Q9LBGGBgK6a-u0C0h95A") == "UUW8Q9LBGGBgK6a-u0C0h95A")
    }

    @Test("업로드 응답에서 비공개·삭제 영상은 뺀다")
    func decodesPlaylist() throws {
        let data = """
        {"nextPageToken":"N","items":[
          {"snippet":{"title":"【MV】A","channelTitle":"KAWAII LAB.","resourceId":{"videoId":"a"}}},
          {"snippet":{"title":"Private video","resourceId":{"videoId":"p"}}}]}
        """.data(using: .utf8)!
        let (items, next) = try YouTubeClient.playlistItems(from: data, channelID: "UC1")
        #expect(items.map(\.videoID) == ["a"])
        #expect(items[0].channelID == "UC1")
        #expect(next == "N")
    }

    @Test("아티스트 이름으로 그룹을 찾는다")
    func groupForArtist() {
        #expect(IdolGroup.group(forArtist: "FRUITS ZIPPER")?.name == "FRUITS ZIPPER")
        #expect(IdolGroup.group(forArtist: "=LOVE")?.name == "=LOVE")
        #expect(IdolGroup.group(forArtist: "宇多田ヒカル") == nil)
    }

    @Test("공식 MV가 자막 재업로드를 이긴다")
    func officialBeatsSubtitledCopy() {
        let candidates = [
            YouTubeClient.Candidate(videoID: "copy", title: "[MV] FRUITS ZIPPER - わたしの一番かわいいところ (한글자막)", channelTitle: "some subs"),
            YouTubeClient.Candidate(videoID: "mv", title: "【MV】FRUITS ZIPPER「わたしの一番かわいいところ」", channelTitle: "KAWAII LAB."),
        ]
        #expect(YouTubeClient.choose(candidates, for: track)?.videoID == "mv")
    }

    @Test("MV 다음에 다른 후보가 순서대로 남는다")
    func keepsRunnersUp() {
        let candidates = [
            YouTubeClient.Candidate(videoID: "live", title: "わたしの一番かわいいところ LIVE", channelTitle: "FRUITS ZIPPER"),
            YouTubeClient.Candidate(videoID: "mv", title: "【MV】FRUITS ZIPPER「わたしの一番かわいいところ」", channelTitle: "KAWAII LAB."),
            YouTubeClient.Candidate(videoID: "topic", title: "わたしの一番かわいいところ", channelTitle: "FRUITS ZIPPER - Topic"),
        ]
        #expect(YouTubeClient.rank(candidates, for: track, strict: true).map(\.videoID) == ["mv", "topic", "live"])
    }

    @Test("느슨한 패스는 라이브·리릭도 받는다")
    func plainPassAdmitsMore() {
        let candidates = [YouTubeClient.Candidate(videoID: "lyric", title: "わたしの一番かわいいところ Lyric Video", channelTitle: "fan")]
        #expect(YouTubeClient.rank(candidates, for: track, strict: true).isEmpty)
        #expect(YouTubeClient.rank(candidates, for: track, strict: false).map(\.videoID) == ["lyric"])
    }

    @Test("옛 목록 파일도 읽힌다")
    func decodesOldDirectory() throws {
        // No `alternates` field. (Written by the current matcher: an older
        // one's picks are redone, see `picksFromAnOlderMatcherAreRedone`.)
        let data = #"{"matcher":3,"videos":{"1":"abc"}}"#.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(VideoDirectory.Snapshot.self, from: data)
        #expect(snapshot.videos == ["1": "abc"])
        #expect(snapshot.alternates.isEmpty)
    }

    @Test("제목에 곡명이 없으면 후보가 아니다")
    func requiresTitle() {
        let candidates = [YouTubeClient.Candidate(videoID: "x", title: "FRUITS ZIPPER NEW KAWAII MV", channelTitle: "FRUITS ZIPPER")]
        #expect(YouTubeClient.choose(candidates, for: track) == nil)
    }

    @Test("검색 응답을 후보로")
    func decodes() throws {
        let data = """
        {"items":[{"id":{"kind":"youtube#video","videoId":"abc"},"snippet":{"title":"A &amp; B","channelTitle":"C"}},
                  {"id":{"kind":"youtube#channel"},"snippet":{"title":"ch","channelTitle":"C"}}]}
        """.data(using: .utf8)!
        let candidates = try YouTubeClient.candidates(from: data)
        #expect(candidates == [YouTubeClient.Candidate(videoID: "abc", title: "A & B", channelTitle: "C")])
    }

    @Test("영상 목록은 다음 실행에도 남는다")
    func directory() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("videos-\(UUID().uuidString)", isDirectory: true)
        let directory = VideoDirectory(directory: dir)
        directory.persist(.init(videos: ["1": "abc", "2": ""]))
        #expect(directory.restore().videos == ["1": "abc", "2": ""])
    }
}

@Suite("사진 속 검은 띠 자르기")
@MainActor
struct LetterboxTests {
    private func image(width: Int, height: Int, bar: Int, barColor: UIColor = .black) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: {
            let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f
        }())
        return renderer.image { context in
            barColor.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.systemPink.setFill(); context.fill(CGRect(x: 0, y: bar, width: width, height: height - bar * 2))
        }
    }

    @Test("위아래 띠를 잘라낸다")
    func trimsBars() {
        let trimmed = Letterbox.trimmed(image(width: 200, height: 200, bar: 25))
        #expect(trimmed.cgImage?.width == 200)
        #expect(trimmed.cgImage?.height == 150)
    }

    @Test("짙은 회색 띠도 잘라낸다")
    func trimsCharcoalBars() {
        let grey = UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1)
        #expect(Letterbox.trimmed(image(width: 200, height: 200, bar: 20, barColor: grey)).cgImage?.height == 160)
    }

    @Test("띠가 없으면 그대로")
    func leavesCleanPictures() {
        let clean = image(width: 200, height: 200, bar: 0)
        #expect(Letterbox.trimmed(clean).cgImage?.height == 200)
    }

    @Test("거의 전부 어두운 사진은 자르지 않는다")
    func leavesDarkPictures() {
        let dark = image(width: 200, height: 200, bar: 80)
        #expect(Letterbox.trimmed(dark).cgImage?.height == 200)
    }
}

@Suite("MV 찾기 보강")
struct VideoMatchingTests {
    private func track(_ title: String, artist: String = "モーニング娘。") -> Track {
        Track(id: "t", title: title, artist: artist, duration: 240)
    }

    @Test("카탈로그의 하이픈 장음도 영상 제목의 ー와 맞는다")
    func longVowelHyphen() {
        let video = YouTubeClient.Candidate(videoID: "v", title: "モーニング娘。『LOVEマシーン』(MV)", channelTitle: "モーニング娘。")
        #expect(YouTubeClient.rank([video], for: track("LOVEマシ-ン"), strict: true).map(\.videoID) == ["v"])
    }

    @Test("「/멤버」 크레딧과 판 표기를 떼고도 찾는다")
    func coreTitle() {
        let video = YouTubeClient.Candidate(videoID: "v", title: "モーニング娘。『大きい瞳』MV", channelTitle: "モーニング娘。")
        #expect(!YouTubeClient.rank([video], for: track("大きい瞳/亀井絵里・道重さゆみ・田中れいな"), strict: true).isEmpty)
        let ver = YouTubeClient.Candidate(videoID: "w", title: "【MV】NEW KAWAII", channelTitle: "KAWAII LAB.")
        #expect(!YouTubeClient.rank([ver], for: track("NEW KAWAII (2025 ver.)", artist: "FRUITS ZIPPER"), strict: true).isEmpty)
    }

    @Test("「・・・(略)」로 줄인 긴 제목은 잘린 앞부분으로 찾는다")
    func shortenedTitle() {
        let video = YouTubeClient.Candidate(videoID: "v", title: "【MV】鈴懸の木の道で「君の微笑みを夢に見る」と言ってしまったら僕たちの関係はどう変わってしまうのか、僕なりに何日か考えた上でのやや気恥ずかしい結論のようなもの / AKB48", channelTitle: "AKB48")
        #expect(!YouTubeClient.rank([video], for: track("鈴懸の木の道で・・・(略)やや気恥ずかしい結論のようなもの", artist: "AKB48"), strict: true).isEmpty)
    }

    @Test("짧은 영문 키는 버리고, 두 글자 일본어 제목은 쓴다")
    func noTinyKeys() {
        #expect(YouTubeClient.titleKeys("I").isEmpty)
        #expect(YouTubeClient.titleKeys("走れ! -ZZ ver.-").contains("走れ"))
    }

    @Test("채널 목록은 새 영상을 앞에, 겹침 없이 붙인다")
    func mergesUploads() {
        let old = VideoDirectory.ChannelUploads(fetchedAt: .distantPast, videos: [
            .init(videoID: "b", title: "B", channelTitle: "c"), .init(videoID: "a", title: "A", channelTitle: "c"),
        ])
        let merged = old.merging(newer: [.init(videoID: "c", title: "C", channelTitle: "c"), .init(videoID: "b", title: "B", channelTitle: "c")])
        #expect(merged.videos.map(\.videoID) == ["c", "b", "a"])
        #expect(merged.isDeep)
    }

    @Test("옛 파일의 '못 찾음'은 다시 찾고, 임베드 거부는 유지한다")
    func oldMissesAreRetried() throws {
        let json = #"{"videos":{"1":"","2":""},"misses":{"1":{"at":0,"permanent":false},"2":{"at":0,"permanent":true}},"channels":{"UCx":{"fetchedAt":0,"videos":[]}}}"#
        let snapshot = try JSONDecoder().decode(VideoDirectory.Snapshot.self, from: Data(json.utf8))
        #expect(snapshot.videos["1"] == nil)
        #expect(snapshot.videos["2"] == "")
        #expect(snapshot.channels["UCx"]?.isDeep == false)
    }

    @Test("매칭 규칙 3 이전에 고른 영상은 다시 고르고, 채널 목록은 남긴다")
    func picksFromAnOlderMatcherAreRedone() throws {
        let json = #"{"matcher":2,"videos":{"1":"choreo","2":""},"alternates":{"1":["mv"]},"misses":{"2":{"at":0,"permanent":true}},"channels":{"UCx":{"fetchedAt":0,"videos":[]}}}"#
        let snapshot = try JSONDecoder().decode(VideoDirectory.Snapshot.self, from: Data(json.utf8))
        #expect(snapshot.videos["1"] == nil)
        #expect(snapshot.alternates["1"] == nil)
        #expect(snapshot.videos["2"] == "")
        #expect(snapshot.channels["UCx"] != nil)
    }

    @Test("지금 규칙으로 고른 영상은 그대로 둔다")
    func currentPicksStay() throws {
        let json = #"{"matcher":\#(VideoDirectory.Snapshot.currentMatcher),"videos":{"1":"mv"}}"#
        let snapshot = try JSONDecoder().decode(VideoDirectory.Snapshot.self, from: Data(json.utf8))
        #expect(snapshot.videos["1"] == "mv")
    }
}

@Suite("채널 업로드 순위 매기기")
struct ChannelRankingTests {
    private let track = Track(id: "1", title: "YAKIMOCHI", artist: "SWEET STEADY")

    /// The regex the fold used before, kept here as the reference it must match.
    private func referenceFold(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping
            .lowercased()
            .replacingOccurrences(of: #"[\s\p{P}\p{S}ーｰ]"#, with: "", options: .regularExpression)
    }

    @Test("접기는 예전 정규식과 같은 결과를 낸다")
    func foldMatchesTheRegex() {
        let samples = [
            "FRUITS ZIPPER「わたしの一番かわいいところ」MV",
            "わたしの一番かわいいところ / FRUITS ZIPPER",
            "ＬＯＶＥマシーン (2024 ver.)", "LOVEマシ-ン", "【MV】YAKIMOCHI #SWEETSTEADY #shorts",
            "Call me,Tell me", "1,2,3,FOOOOUR!!", "モーニング娘。'14『笑顔の君は太陽さ』",
            "≠ME 「すきなこがいること」 Music Video", "♡ Sweet Cafe ♡ ~live~", "ﾃｽﾄ ｰ ｶﾀｶﾅ",
        ]
        for sample in samples {
            #expect(YouTubeClient.fold(sample) == referenceFold(sample), "\(sample)")
        }
    }

    @Test("엄격 결과가 먼저 오고, 느슨한 결과는 겹치지 않게 뒤에 붙는다")
    func strictFirstThenLooseWithoutDuplicates() {
        let candidates = [
            YouTubeClient.Candidate(videoID: "live", title: "YAKIMOCHI live", channelTitle: "fan"),
            YouTubeClient.Candidate(videoID: "mv", title: "SWEET STEADY「YAKIMOCHI」MV", channelTitle: "SWEET STEADY"),
            YouTubeClient.Candidate(videoID: "other", title: "SWEET STEP", channelTitle: "SWEET STEADY"),
        ]
        let ranked = YouTubeClient.rankAll(candidates, for: track, channels: [])
        #expect(ranked.first?.videoID == "mv")
        #expect(Set(ranked.map(\.videoID)) == ["mv", "live"])
        #expect(ranked.count == Set(ranked.map(\.videoID)).count)
    }

    @Test("업로드 수천 개에 제목이 수백 번 걸려도 금방 끝난다")
    func aDeepChannelRanksQuickly() {
        // Two deep channels' worth, with hundreds of hashtag Shorts carrying
        // the title — the shape that froze the player for minutes.
        let candidates = (0..<6000).map { i in
            YouTubeClient.Candidate(
                videoID: "v\(i)",
                title: i % 15 == 0 ? "#YAKIMOCHI #SWEETSTEADY #shorts \(i)" : "SWEET STEADY other upload \(i)",
                channelTitle: "SWEET STEADY"
            )
        }
        let start = ContinuousClock.now
        _ = YouTubeClient.rankAll(candidates, for: track, channels: [])
        #expect(ContinuousClock.now - start < .seconds(3))
    }
}

/// Cases from the video matching report: the videos that won over a real MV.
@Suite("MV가 아닌 영상에 지지 않기")
struct NotTheMusicVideoTests {
    private let groupChannel = "UCU0PgOXf0lxzVxN2TLzMJkw"
    private let label = "UCW8Q9LBGGBgK6a-u0C0h95A"

    private func first(_ candidates: [YouTubeClient.Candidate], _ track: Track, channels: [String]) -> String? {
        YouTubeClient.rankAll(candidates, for: track, channels: channels).first?.videoID
    }

    @Test("레이블의 【MV】가 그룹 채널의 안무 영상을 이긴다")
    func mvBeatsChoreography() {
        let track = Track(id: "1", title: "倍倍FIGHT!", artist: "CANDY TUNE", duration: 253)
        let candidates = [
            .init(videoID: "choreo", title: "【Choreography Video -MV edition-】CANDY TUNE「倍倍FIGHT!」", channelTitle: "CANDY TUNE", channelID: groupChannel),
            YouTubeClient.Candidate(videoID: "mv", title: "【MV】CANDY TUNE「倍倍FIGHT!」", channelTitle: "KAWAII LAB.", channelID: label),
        ]
        #expect(first(candidates, track, channels: [groupChannel, label]) == "mv")
    }

    @Test("응원법·콜 영상은 곡 음원보다 뒤로 간다")
    func cheeringGuideSinks() {
        let track = Track(id: "2", title: "DASH!!!", artist: "SWEET STEADY", duration: 186)
        let channel = "UC5s_kUbxX3P1q6lmDgygD-w"
        let candidates = [
            YouTubeClient.Candidate(videoID: "call", title: "【Cheering Guide】SWEET STEADY「DASH!!!」コール動画", channelTitle: "SWEET STEADY", channelID: channel),
            YouTubeClient.Candidate(videoID: "song", title: "DASH!!!", channelTitle: "SWEET STEADY", channelID: channel),
        ]
        #expect(first(candidates, track, channels: [channel]) == "song")
    }

    @Test("장음 부호가 든 감점 단어도 걸린다")
    func penaltiesWithALongVowelMarkMatch() {
        // 「コール動画」 folds to 「コル動画」; the word list has to be folded too.
        let track = Track(id: "7", title: "真夏日よ", artist: "乃木坂46", duration: 269)
        let channel = "UCUzpZpX2wRYOk3J8QTFGxDg"
        let candidates = [
            YouTubeClient.Candidate(videoID: "call", title: "乃木坂46 『真夏日よ』 コール動画 真夏の全国ツアー2025", channelTitle: "乃木坂46 OFFICIAL YouTube CHANNEL", channelID: channel),
            YouTubeClient.Candidate(videoID: "memorial", title: "乃木坂46『真夏日よ』 明治神宮野球場公演 10thメモリアルムービー", channelTitle: "乃木坂46 OFFICIAL YouTube CHANNEL", channelID: channel),
        ]
        #expect(first(candidates, track, channels: [channel]) == "memorial")
    }

    @Test("【MV】 태그가 붙은 콜 영상은 음원보다 앞, 깨끗한 MV보다 뒤")
    func aTaggedMVWithCallsIsStillTheMV() {
        let track = Track(id: "8", title: "アイドルライフメガパック", artist: "iLiFE!", duration: 216)
        let channel = "UCDdYkqNNrE8LbLJnVxrRgjw"
        let withCalls = YouTubeClient.Candidate(videoID: "calls", title: "【MV】アイドルライフメガパック / iLiFE!【コール動画】", channelTitle: "iLiFE!【あいらいふ】", channelID: channel)
        let audio = YouTubeClient.Candidate(videoID: "audio", title: "アイドルライフメガパック", channelTitle: "iLiFE!【あいらいふ】", channelID: channel)
        let clean = YouTubeClient.Candidate(videoID: "clean", title: "【MV】アイドルライフメガパック / iLiFE!", channelTitle: "iLiFE!【あいらいふ】", channelID: channel)
        #expect(first([audio, withCalls], track, channels: [channel]) == "calls")
        #expect(first([withCalls, audio, clean], track, channels: [channel]) == "clean")
    }

    @Test("곡 제목에 든 말은 감점하지 않는다")
    func theSongsOwnWordsAreNotPenalties() {
        let track = Track(id: "3", title: "いえなかったことば ～ありがとう～", artist: "CANDY TUNE", duration: 260)
        let candidates = [
            YouTubeClient.Candidate(videoID: "live", title: "いえなかったことば〜ありがとう〜 (ライブ映像)", channelTitle: "CANDY TUNE", channelID: groupChannel),
            YouTubeClient.Candidate(videoID: "mv", title: "【MV】 CANDY TUNE「いえなかったことば〜ありがとう〜」", channelTitle: "KAWAII LAB.", channelID: label),
        ]
        #expect(first(candidates, track, channels: [groupChannel, label]) == "mv")
    }

    @Test("메이킹·비하인드는 MUSiC CLiP보다 뒤로 간다")
    func makingOfSinks() {
        let track = Track(id: "4", title: "土曜日のわたしたちは", artist: "LiSA", duration: 248)
        let channel = "UCqEfdEvLG5oQWNYlDQrGlKw"
        let candidates = [
            YouTubeClient.Candidate(videoID: "behind", title: "LiSA『土曜日のわたしたちは』 - MUSiC CLiP Behind The Scene -", channelTitle: "LiSA Official YouTube", channelID: channel),
            YouTubeClient.Candidate(videoID: "making", title: "LiSA『土曜日のわたしたちは』MUSiC CLiP Making Movie", channelTitle: "LiSA Official YouTube", channelID: channel),
            YouTubeClient.Candidate(videoID: "clip", title: "LiSA『土曜日のわたしたちは』 -MUSiC CLiP-", channelTitle: "LiSA Official YouTube", channelID: channel),
        ]
        #expect(first(candidates, track, channels: [channel]) == "clip")
    }

    @Test("한 글자 제목도 괄호로 인용되면 찾는다")
    func aOneCharacterTitleMatchesWhenQuoted() {
        let track = Track(id: "5", title: "虹", artist: "日向坂46", duration: 294)
        let channel = "UCR0V48DJyWbwEAdxLL5FjxA"
        let candidates = [
            YouTubeClient.Candidate(videoID: "other", title: "日向坂46『虹の向こう側』", channelTitle: "日向坂46", channelID: channel),
            YouTubeClient.Candidate(videoID: "mv", title: "日向坂46『虹』", channelTitle: "日向坂46", channelID: channel),
        ]
        #expect(YouTubeClient.rankAll(candidates, for: track, channels: [channel]).map(\.videoID) == ["mv"])
    }

    @Test("길이가 터무니없는 영상은 버리고, 맞는 길이를 앞에 둔다")
    func lengthDropsTheClearlyWrongAndOrdersTheRest() {
        let track = Track(id: "6", title: "ナツマトペ", artist: "=LOVE", duration: 240)
        func c(_ id: String) -> YouTubeClient.Candidate { .init(videoID: id, title: id, channelTitle: "=LOVE") }
        let kept = YouTubeClient.byLength(
            [c("short"), c("medley"), c("longish"), c("mv"), c("unknown")],
            track: track,
            durations: ["short": 14, "medley": 838, "longish": 420, "mv": 245]
        )
        #expect(kept.map(\.videoID) == ["mv", "unknown", "longish"])
    }
}
