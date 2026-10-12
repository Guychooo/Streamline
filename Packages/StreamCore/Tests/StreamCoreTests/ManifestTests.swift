import XCTest
@testable import StreamCore

final class ManifestTests: XCTestCase {
    func testDecodesMixedResourceForms() throws {
        let json = """
        {
          "id": "org.example", "version": "1.2.0", "name": "Example", "description": "x",
          "types": ["movie", "series"], "idPrefixes": ["tt"],
          "resources": ["catalog", {"name": "stream", "types": ["movie"], "idPrefixes": ["tt", "kitsu:"]}, "meta"],
          "catalogs": [
            {"type": "movie", "id": "top", "name": "Top", "extra": [{"name": "search"}, {"name": "skip"}]},
            {"type": "movie", "id": "find", "extra": [{"name": "search", "isRequired": true}]},
            {"type": "series", "id": "genre", "extra": [{"name": "genre", "isRequired": true, "options": ["Drama"]}]}
          ]
        }
        """
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.resources.map(\.name), ["catalog", "stream", "meta"])
        XCTAssertTrue(manifest.resources[0].isShortForm)
        XCTAssertFalse(manifest.resources[1].isShortForm)

        let addon = InstalledAddon(transportURL: "https://a.example/manifest.json", manifest: manifest)
        XCTAssertTrue(addon.supports(resource: "stream", type: "movie", id: "kitsu:1"))
        XCTAssertFalse(addon.supports(resource: "stream", type: "series", id: "tt1"), "object form overrides types")
        XCTAssertTrue(addon.supports(resource: "meta", type: "series", id: "tt1"))
        XCTAssertFalse(addon.supports(resource: "meta", type: "series", id: "kitsu:1"), "short form inherits idPrefixes")
        XCTAssertFalse(addon.supports(resource: "subtitles", type: "movie", id: "tt1"))

        XCTAssertEqual(addon.browsableCatalogs.map(\.id), ["top"])
        XCTAssertEqual(addon.searchableCatalogs.map(\.id), ["top", "find"])
    }

    func testObjectResourceWithoutPrefixesMatchesAnyID() throws {
        let manifest = Manifest(
            id: "x", version: "1", name: "X", types: ["movie"], idPrefixes: ["tt"],
            resources: [.full("stream", types: ["movie"])], catalogs: []
        )
        let addon = InstalledAddon(transportURL: "https://x/manifest.json", manifest: manifest)
        XCTAssertTrue(addon.supports(resource: "stream", type: "movie", id: "anything"))
    }

    func testLegacyExtraFields() throws {
        let json = #"{"type":"movie","id":"c","extraSupported":["search","genre"],"extraRequired":["search"]}"#
        let catalog = try JSONDecoder().decode(CatalogDescriptor.self, from: Data(json.utf8))
        XCTAssertTrue(catalog.supportsSearch)
        XCTAssertFalse(catalog.isBrowsable)
        XCTAssertTrue(catalog.isSearchable)
    }

    func testManifestRoundTripKeepsShortForm() throws {
        let manifest = Manifest(id: "x", version: "1", name: "X", types: ["movie"],
                                resources: [.short("stream"), .full("meta", types: ["series"])], catalogs: [])
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(Manifest.self, from: data)
        XCTAssertEqual(decoded, manifest)
    }

    func testLossyDecodingSkipsBrokenItems() throws {
        let json = #"{"metas":[{"id":"tt1","type":"movie","name":"Good"},{"type":"movie"},{"id":"tt2","name":"No type","releaseInfo":2014}]}"#
        let response = try JSONDecoder().decode(CatalogResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.metas.map(\.id), ["tt1", "tt2"])
        XCTAssertEqual(response.metas[1].releaseInfo, "2014")
    }

    func testSeasonsAndEpisodes() throws {
        let json = """
        {"meta":{"id":"tt9","type":"series","name":"Show","videos":[
          {"id":"tt9:2:1","title":"B1","season":2,"episode":1,"released":"2020-01-01"},
          {"id":"tt9:0:1","name":"Special","season":0,"episode":1},
          {"id":"tt9:1:2","title":"A2","season":"1","episode":"2"},
          {"id":"tt9:1:1","title":"A1","season":1,"number":1}
        ]}}
        """
        let meta = try XCTUnwrap(try JSONDecoder().decode(MetaResponse.self, from: Data(json.utf8)).meta)
        XCTAssertEqual(meta.seasons, [1, 2, 0])
        XCTAssertEqual(meta.episodes(inSeason: 1).map(\.title), ["A1", "A2"])
        XCTAssertEqual(meta.videos?.first { $0.season == 0 }?.title, "Special")
        XCTAssertEqual(meta.episodes(inSeason: 1).first?.episodeLabel, "S1 · E1")
    }
}
