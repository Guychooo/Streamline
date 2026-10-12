import XCTest
@testable import StreamCore

final class LibraryTests: XCTestCase {
    func testProgressRules() {
        var p = WatchProgress(videoID: "v", metaID: "m", metaType: "movie", title: "T", position: 20, duration: 3600)
        XCTAssertNil(p.resumePosition, "too early to resume")
        p.position = 600
        XCTAssertEqual(p.resumePosition, 595)
        p.position = 3500
        XCTAssertTrue(p.isFinished)
        XCTAssertNil(p.resumePosition)

        let clip = WatchProgress(videoID: "c", metaID: "c", metaType: "movie", title: "Clip", position: 40, duration: 90)
        XCTAssertFalse(clip.isFinished, "short clips aren't finished just because under 2 min remain")
        XCTAssertEqual(clip.resumePosition, 35)
    }

    func testStorePersists() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("library.json")
        let store = LibraryStore(fileURL: url)
        await store.record(WatchProgress(videoID: "v1", metaID: "m1", metaType: "movie", title: "A", position: 300, duration: 3600))
        await store.record(WatchProgress(videoID: "v2", metaID: "m2", metaType: "movie", title: "B", position: 3590, duration: 3600))
        let saved = await store.toggleSaved(MetaItem(id: "m1", type: "movie", name: "A"))
        XCTAssertTrue(saved)

        let reopened = LibraryStore(fileURL: url)
        let continuing = await reopened.continueWatching()
        XCTAssertEqual(continuing.map(\.videoID), ["v1"], "finished items drop out of continue watching")
        let isSaved = await reopened.isSaved("m1")
        XCTAssertTrue(isSaved)
    }
}
