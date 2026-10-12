import XCTest
@testable import ClickCore

/// examples/ 샘플(iPhone 16, iOS 26.6.1)에 대한 정합 테스트. 정답·구간은 PROGRESS.md "실측".
final class SampleMatchTests: XCTestCase {
    static let examples = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("examples")
    static let video = examples.appendingPathComponent("IMG_4183.MOV")
    static let frameDuration = 1.0 / 30.0

    /// 눈으로 확정된 정답. ±1프레임 허용.
    static let confirmed: [(photo: String, time: TimeInterval)] = [
        ("IMG_4178", 5.333), ("IMG_4179", 8.567), ("IMG_4180", 11.067), ("IMG_4182", 15.865),
    ]
    /// 미확정. 구간 안이면 통과. 4176 하한은 매처 결과(1.433)에 맞춰 1.5→1.4로 넓힘(사용자 결정 2026-10-12, PROGRESS.md).
    static let ranges: [(photo: String, range: ClosedRange<TimeInterval>)] = [
        ("IMG_4176", 1.4...1.9), ("IMG_4177", 2.7...3.5), ("IMG_4181", 14.7...15.0),
    ]

    func bestTime(_ photo: String) async throws -> TimeInterval {
        let url = Self.examples.appendingPathComponent(photo + ".jpg")
        let v = try await VideoTimestamp.read(from: Self.video)
        let p = try PhotoTimestamp.read(from: url)
        let frames = try await FrameExtractor.frames(url: Self.video, in: SearchWindow(photo: p, video: v))
        let result = try XCTUnwrap(try FrameMatcher.match(photo: try ImageLoader.loadGray(url: url), frames: frames))
        return result.best.time
    }

    func testConfirmedPhotosWithinOneFrame() async throws {
        for (photo, truth) in Self.confirmed {
            let t = try await bestTime(photo)
            // ±1프레임. PTS 간격이 최대 0.035s라 1.5프레임을 허용치로 둔다.
            XCTAssertEqual(t, truth, accuracy: Self.frameDuration * 1.5, "\(photo): got \(t), truth \(truth)")
        }
    }

    func testUnconfirmedPhotosWithinRange() async throws {
        for (photo, range) in Self.ranges {
            let t = try await bestTime(photo)
            XCTAssertTrue(range.contains(t), "\(photo): got \(t), range \(range)")
        }
    }
}
