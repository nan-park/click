import XCTest
@testable import ClickCore

final class EffectTimelineTests: XCTestCase {
    let frame = CGSize(width: 1080, height: 1920)
    let photo = URL(fileURLWithPath: "/p.jpg")
    // 기본값과 다른 값으로 두어 config가 실제로 쓰이는지 확인한다.
    var config: EffectConfig { var c = EffectConfig(); c.freezeDuration = 0.5; c.shrinkDuration = 0.2; return c }

    func testNoOverlayOutsideEffect() {
        let p = [PhotoPlacement(photoURL: photo, time: 5.0)]
        XCTAssertNil(EffectTimeline.overlay(at: 4.99, placements: p, frameSize: frame, config: config))
        XCTAssertNil(EffectTimeline.overlay(at: 5.0 + config.totalDuration, placements: p, frameSize: frame, config: config))
        XCTAssertNil(EffectTimeline.overlay(at: 5.71, placements: p, frameSize: frame, config: config))
    }

    func testFreezeCoversFullFrame() {
        let p = [PhotoPlacement(photoURL: photo, time: 5.0)]
        let o = EffectTimeline.overlay(at: 5.0, placements: p, frameSize: frame, config: config)
        XCTAssertEqual(o?.rect, CGRect(origin: .zero, size: frame))
        XCTAssertEqual(EffectTimeline.overlay(at: 5.49, placements: p, frameSize: frame, config: config)?.rect,
                       CGRect(origin: .zero, size: frame))
    }

    func testShrinkEndsAtThumbnail() {
        let p = [PhotoPlacement(photoURL: photo, time: 5.0)]
        let end = EffectTimeline.overlay(at: 5.0 + config.totalDuration - 0.0001, placements: p, frameSize: frame, config: config)!.rect
        let thumb = EffectTimeline.thumbnailRect(frameSize: frame, config: config)
        XCTAssertEqual(end.minX, thumb.minX, accuracy: 1)
        XCTAssertEqual(end.minY, thumb.minY, accuracy: 1)
        XCTAssertEqual(end.width, thumb.width, accuracy: 1)
        // 중간은 전체 화면과 썸네일 사이, 단조 감소.
        let mid = EffectTimeline.overlay(at: 5.6, placements: p, frameSize: frame, config: config)!.rect
        XCTAssertLessThan(mid.width, frame.width)
        XCTAssertGreaterThan(mid.width, thumb.width)
    }

    func testThumbnailKeepsAspectAndSitsBottomLeft() {
        let t = EffectTimeline.thumbnailRect(frameSize: frame, config: config)
        XCTAssertEqual(t.width / t.height, frame.width / frame.height, accuracy: 1e-9)
        XCTAssertEqual(t.minX, frame.width * config.thumbnailMargin)
        XCTAssertEqual(t.maxY, frame.height - frame.width * config.thumbnailMargin, accuracy: 1e-9)
    }

    func testLatestPlacementWinsWhenOverlapping() {
        let a = PhotoPlacement(photoURL: URL(fileURLWithPath: "/a.jpg"), time: 5.0)
        let b = PhotoPlacement(photoURL: URL(fileURLWithPath: "/b.jpg"), time: 5.4)
        let o = EffectTimeline.overlay(at: 5.45, placements: [a, b], frameSize: frame, config: config)
        XCTAssertEqual(o?.placement, b)
    }
}
