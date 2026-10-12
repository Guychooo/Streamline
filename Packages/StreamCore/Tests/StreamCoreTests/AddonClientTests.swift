import XCTest
@testable import StreamCore

private struct StubHTTPClient: HTTPClient {
    var routes: [String: String]
    func get(_ url: URL) async throws -> Data {
        guard let body = routes[url.absoluteString] else { throw AddonError.resourceNotFound(url.absoluteString) }
        return Data(body.utf8)
    }
}

final class AddonClientTests: XCTestCase {
    private let manifestA = """
    {"id":"a","version":"1.0.0","name":"Alpha","types":["movie"],"resources":["catalog","stream"],
     "catalogs":[{"type":"movie","id":"pop","name":"Popular","extra":[{"name":"search"}]}],"idPrefixes":["tt"]}
    """
    private let manifestB = """
    {"id":"b","version":"1.0.0","name":"Beta","types":["movie"],"resources":["stream","subtitles"],"catalogs":[]}
    """

    private func makeFactory(extraRoutes: [String: String] = [:]) -> AddonTransportFactory {
        var routes = [
            "https://a.example/manifest.json": manifestA,
            "https://b.example/manifest.json": manifestB,
            "https://a.example/catalog/movie/pop.json": #"{"metas":[{"id":"tt1","type":"movie","name":"One"}]}"#,
            "https://a.example/catalog/movie/pop/search=one.json": #"{"metas":[{"id":"tt1","type":"movie","name":"One"}]}"#,
            "https://a.example/stream/movie/tt1.json": #"{"streams":[{"url":"https://cdn.example/1.m3u8","name":"1080p"}]}"#,
            "https://b.example/subtitles/movie/tt1/filename=one.mkv.json": #"{"subtitles":[{"id":"s1","url":"https://subs.example/1.srt","lang":"eng"}]}"#
        ]
        routes.merge(extraRoutes) { $1 }
        return AddonTransportFactory(httpClient: StubHTTPClient(routes: routes), builtIns: [])
    }

    func testInstallCatalogSearchAndStreams() async throws {
        let factory = makeFactory()
        let a = try await factory.install(from: "stremio://a.example/manifest.json")
        let b = try await factory.install(from: "https://b.example")
        XCTAssertEqual(a.manifest.name, "Alpha")
        let client = AddonClient(addons: [a, b], factory: factory)

        let metas = try await client.catalog(a.manifest.catalogs[0], from: a)
        XCTAssertEqual(metas.map(\.name), ["One"])

        let search = await client.search("one")
        XCTAssertEqual(search.count, 1)
        XCTAssertEqual(search.first?.metas.first?.id, "tt1")

        let groups = await client.streams(type: "movie", videoID: "tt1")
        XCTAssertEqual(groups.map(\.addon.manifest.name), ["Alpha", "Beta"], "results keep install order")
        XCTAssertEqual(groups[0].streams.first?.displayName, "1080p")
        XCTAssertTrue(groups[1].streams.isEmpty)
        XCTAssertNotNil(groups[1].errorMessage, "a failing add-on reports its error instead of hiding others")
    }

    func testSubtitlesMergeStreamAttachedFirstAndDeduplicate() async throws {
        let factory = makeFactory()
        let b = try await factory.install(from: "https://b.example/manifest.json")
        let client = AddonClient(addons: [b], factory: factory)
        let stream = MediaStream(
            url: "https://cdn.example/1.mkv",
            subtitles: [
                Subtitle(id: "inline", url: "https://subs.example/inline.vtt", lang: "fre"),
                Subtitle(id: "dup", url: "https://subs.example/1.srt", lang: "eng")
            ],
            behaviorHints: StreamBehaviorHints(filename: "one.mkv")
        )
        let subtitles = await client.subtitles(type: "movie", videoID: "tt1", for: stream)
        XCTAssertEqual(subtitles.map(\.url), ["https://subs.example/inline.vtt", "https://subs.example/1.srt"])
    }

    func testBuiltInAddonServesCatalogMetaStreamsAndSearch() async throws {
        let addon = OpenMoviesAddon.make(demoSubtitleURL: URL(string: "file:///tmp/demo.vtt"))
        let factory = AddonTransportFactory(httpClient: StubHTTPClient(routes: [:]), builtIns: [addon])
        let installed = factory.builtInAddons
        let client = AddonClient(addons: installed, factory: factory)

        let movies = try await client.catalog(installed[0].manifest.catalogs[0], from: installed[0])
        XCTAssertEqual(movies.count, 4)
        let secondPage = try await client.catalog(installed[0].manifest.catalogs[0], from: installed[0], skip: 100)
        XCTAssertTrue(secondPage.isEmpty)

        let found = await client.search("sintel")
        XCTAssertEqual(found.flatMap(\.metas).map(\.name), ["Sintel"])

        let series = await client.meta(type: "series", id: "om:hls-test-streams")
        XCTAssertEqual(series?.videos?.count, 2)

        let streams = await client.streams(type: "series", videoID: "om:hls-test-streams:1:1")
        XCTAssertEqual(streams.first?.streams.count, 1)
        let firstStream = try XCTUnwrap(streams.first?.streams.first)
        XCTAssertTrue(PlaybackSource(stream: firstStream).isPlayableInApp)

        let subs = await client.subtitles(type: "movie", videoID: "om:big-buck-bunny", for: nil)
        XCTAssertEqual(subs.map(\.lang), ["eng"])
        XCTAssertEqual(subs.first?.displayName, "English (demo captions)")

        let unknown = await client.streams(type: "movie", videoID: "tt123")
        XCTAssertTrue(unknown.isEmpty, "idPrefixes keep the built-in add-on out of other ids")
    }
}
