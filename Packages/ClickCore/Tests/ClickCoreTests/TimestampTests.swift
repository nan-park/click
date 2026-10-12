import XCTest
@testable import ClickCore

final class TimestampTests: XCTestCase {
    func testExifParseWithSubsecAndOffset() throws {
        let d = try PhotoTimestamp.parseExif("2026:10:12 16:06:48", subsec: "672", offset: "+09:00")
        // 2026-10-12T07:06:48.672Z
        XCTAssertEqual(d.timeIntervalSince1970, 1_791_788_808.672, accuracy: 0.0005)
    }

    func testExifParseRejectsGarbage() {
        XCTAssertThrowsError(try PhotoTimestamp.parseExif("not a date", subsec: nil, offset: "+09:00"))
    }

    func testQuickTimeDateSecondsAndFraction() {
        let a = VideoTimestamp.parseQuickTimeDate("2026-10-12T16:06:46+0900")
        let b = VideoTimestamp.parseQuickTimeDate("2026-10-12T16:06:46.2500+0900")
        XCTAssertEqual(a?.timeIntervalSince1970, 1_791_788_806)
        XCTAssertEqual(b?.timeIntervalSince1970 ?? 0, 1_791_788_806.25, accuracy: 0.0005)
        XCTAssertNil(VideoTimestamp.parseQuickTimeDate("2026-10-12"))
    }

    func testSearchWindowClipsToVideo() {
        let video = VideoTimestamp(startDate: Date(timeIntervalSince1970: 1000), duration: 18, nominalFrameRate: 30, naturalSize: .zero)
        var config = MatchConfig()
        config.searchWindowBefore = 2; config.searchWindowAfter = 0.5

        let early = SearchWindow(photo: PhotoTimestamp(captureDate: Date(timeIntervalSince1970: 1001)), video: video, config: config)
        XCTAssertEqual(early.start, 0); XCTAssertEqual(early.end, 1.5); XCTAssertFalse(early.isEmpty)

        let late = SearchWindow(photo: PhotoTimestamp(captureDate: Date(timeIntervalSince1970: 1019)), video: video, config: config)
        XCTAssertEqual(late.start, 17); XCTAssertEqual(late.end, 18); XCTAssertFalse(late.isEmpty)

        let outside = SearchWindow(photo: PhotoTimestamp(captureDate: Date(timeIntervalSince1970: 1030)), video: video, config: config)
        XCTAssertTrue(outside.isEmpty)
    }
}
