import XCTest
@testable import StreamCore

final class PlaybackTests: XCTestCase {
    func testClassification() {
        let headers = StreamBehaviorHints(notWebReady: true, proxyHeaders: ProxyHeaders(request: ["User-Agent": "X"]))
        XCTAssertEqual(PlaybackSource(stream: MediaStream(url: "https://a/b.m3u8", behaviorHints: headers)),
                       .direct(url: URL(string: "https://a/b.m3u8")!, headers: ["User-Agent": "X"]))
        XCTAssertEqual(PlaybackSource(stream: MediaStream(ytId: "abc")),
                       .youtube(videoID: "abc", url: URL(string: "https://www.youtube.com/watch?v=abc")!))
        XCTAssertEqual(PlaybackSource(stream: MediaStream(externalUrl: "https://service.example/title/1")),
                       .external(URL(string: "https://service.example/title/1")!))
        XCTAssertNotNil(PlaybackSource(stream: MediaStream(infoHash: "abcdef")).unsupportedReason)
        XCTAssertNotNil(PlaybackSource(stream: MediaStream(url: "magnet:?xt=urn:btih:abc")).unsupportedReason)
        XCTAssertNotNil(PlaybackSource(stream: MediaStream(url: "rtmp://live/x")).unsupportedReason)
        XCTAssertNotNil(PlaybackSource(stream: MediaStream(externalUrl: "stremio:///detail/movie/tt1")).unsupportedReason)
        XCTAssertNotNil(PlaybackSource(stream: MediaStream()).unsupportedReason)
    }

    func testArchiveSourcesDetected() throws {
        let json = #"{"rarUrls":[{"url":"https://x/a.rar"}],"name":"RAR"}"#
        let stream = try JSONDecoder().decode(MediaStream.self, from: Data(json.utf8))
        XCTAssertTrue(stream.hasArchiveSources)
        XCTAssertNotNil(PlaybackSource(stream: stream).unsupportedReason)
    }
}
