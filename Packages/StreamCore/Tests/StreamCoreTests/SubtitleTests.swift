import XCTest
@testable import StreamCore

final class SubtitleTests: XCTestCase {
    func testSRT() throws {
        let srt = "\u{FEFF}1\r\n00:00:01,000 --> 00:00:03,500\r\n<i>Hello</i> &amp; welcome\r\nSecond line\r\n\r\n2\r\n00:00:04,000 --> 00:00:05,000\r\n{\\an8}Top line\r\n"
        let cues = try SubtitleParser.parse(text: srt)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0], SubtitleCue(start: 1, end: 3.5, text: "Hello & welcome\nSecond line"))
        XCTAssertEqual(cues[1].text, "Top line")
    }

    func testWebVTT() throws {
        let vtt = """
        WEBVTT
        Kind: captions

        NOTE this is ignored

        intro
        00:01.000 --> 00:02.000 align:start position:10%
        <v Narrator>Short form</v>

        01:00:00.250 --> 01:00:01.000
        Long form
        """
        let cues = try SubtitleParser.parse(text: vtt)
        XCTAssertEqual(cues.map(\.text), ["Short form", "Long form"])
        XCTAssertEqual(cues[1].start, 3600.25, accuracy: 0.0001)
    }

    func testASS() throws {
        let ass = """
        [Script Info]
        Title: Test

        [V4+ Styles]
        Format: Name, Fontname
        Style: Default,Arial

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:02.00,0:00:04.50,Default,,0,0,0,,{\\b1}Bold{\\b0}, with a comma\\Nand a break
        Comment: 0,0:00:05.00,0:00:06.00,Default,,0,0,0,,ignored
        """
        let cues = try SubtitleParser.parse(text: ass)
        XCTAssertEqual(cues, [SubtitleCue(start: 2, end: 4.5, text: "Bold, with a comma\nand a break")])
    }

    func testRejectsEmptyFiles() {
        XCTAssertThrowsError(try SubtitleParser.parse(text: "WEBVTT\n\n")) { error in
            XCTAssertEqual(error as? SubtitleParseError, .noCues)
        }
    }

    func testWindows1252Fallback() throws {
        var bytes = Array("1\n00:00:01,000 --> 00:00:02,000\nCaf".utf8)
        bytes.append(0xE9)  // é in Windows-1252, invalid as UTF-8
        let cues = try SubtitleParser.parse(data: Data(bytes))
        XCTAssertEqual(cues.first?.text, "Café")
    }

    func testTrackLookupHandlesOverlaps() {
        let track = SubtitleTrack(cues: [
            SubtitleCue(start: 0, end: 10, text: "long"),
            SubtitleCue(start: 2, end: 3, text: "short"),
            SubtitleCue(start: 12, end: 13, text: "later")
        ])
        XCTAssertEqual(track.text(at: 2.5), "long\nshort")
        XCTAssertEqual(track.text(at: 5), "long")
        XCTAssertNil(track.text(at: 11))
        XCTAssertEqual(track.text(at: 12), "later")
        XCTAssertNil(track.text(at: 13), "end time is exclusive")
    }
}
