import XCTest
@testable import StreamCore

final class RequestTests: XCTestCase {
    func testPathEncoding() {
        XCTAssertEqual(ResourceRequest(resource: "stream", type: "series", id: "tt0944947:1:2").path,
                       "stream/series/tt0944947%3A1%3A2.json")
        XCTAssertEqual(ResourceRequest(resource: "catalog", type: "movie", id: "top",
                                       extra: [.init("search", "the matrix & co"), .init("skip", "100")]).path,
                       "catalog/movie/top/search=the%20matrix%20%26%20co&skip=100.json")
        XCTAssertEqual(ResourceRequest(resource: "catalog", type: "movie", id: "top", extra: [.init("genre", "")]).path,
                       "catalog/movie/top.json", "empty extras are dropped")
    }

    func testTransportNormalisation() throws {
        XCTAssertEqual(try TransportURL.normalize(" stremio://addon.example.com/abc/manifest.json ").absoluteString,
                       "https://addon.example.com/abc/manifest.json")
        XCTAssertEqual(try TransportURL.normalize("https://addon.example.com/abc/").absoluteString,
                       "https://addon.example.com/abc/manifest.json")
        XCTAssertEqual(try TransportURL.normalize("addon.example.com").absoluteString,
                       "https://addon.example.com/manifest.json")
        XCTAssertThrowsError(try TransportURL.normalize("ipfs://abc/manifest.json"))
        XCTAssertThrowsError(try TransportURL.normalize("   "))
        XCTAssertEqual(TransportURL.baseURLString(forManifest: "https://a.example/x/manifest.json"), "https://a.example/x")
    }
}
