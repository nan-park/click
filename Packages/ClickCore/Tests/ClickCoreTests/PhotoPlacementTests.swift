import XCTest
@testable import ClickCore

final class PhotoPlacementTests: XCTestCase {
    let photo = URL(fileURLWithPath: "/p.jpg")

    func testCropRectCenteredWhenNoOffset() {
        let p = PhotoPlacement(photoURL: photo, time: 0, cropRatio: 0.9)
        let r = p.cropRect(photoSize: CGSize(width: 1000, height: 2000))
        XCTAssertEqual(r.minX, 50, accuracy: 1e-9)
        XCTAssertEqual(r.minY, 100, accuracy: 1e-9)
        XCTAssertEqual(r.width, 900, accuracy: 1e-9)
        XCTAssertEqual(r.height, 1800, accuracy: 1e-9)
    }

    func testCropRectShiftsByOffsetFraction() {
        let p = PhotoPlacement(photoURL: photo, time: 0, cropRatio: 0.9, offsetX: -0.01, offsetY: 0.02)
        let r = p.cropRect(photoSize: CGSize(width: 1000, height: 2000))
        XCTAssertEqual(r.minX, 40, accuracy: 1e-9)
        XCTAssertEqual(r.minY, 140, accuracy: 1e-9)
    }

    func testCropRectIsPushedInsidePhoto() {
        // 4176 실측: crop 0.92 + offsetX 0.05 → 오른쪽이 1% 밖으로. 크기는 유지하고 안쪽으로 민다.
        let p = PhotoPlacement(photoURL: photo, time: 0, cropRatio: 0.92, offsetX: 0.05, offsetY: -0.1)
        let r = p.cropRect(photoSize: CGSize(width: 1000, height: 2000))
        XCTAssertEqual(r.width, 920, accuracy: 1e-9)
        XCTAssertEqual(r.height, 1840, accuracy: 1e-9)
        XCTAssertEqual(r.maxX, 1000, accuracy: 1e-9)
        XCTAssertEqual(r.minY, 0, accuracy: 1e-9)
    }

    func testFromMatchNegatesTranslationAndUsesNCCCrop() {
        let best = FrameMatcher.Candidate(time: 5.3, ncc: (0.8, 0.96), translation: .init(dx: 2, dy: -3))
        let result = FrameMatcher.Result(best: best, method: .alignment, candidates: [best])
        var config = MatchConfig(); config.analysisWidth = 200
        let p = PhotoPlacement(photoURL: photo, match: result, frameAnalysisHeight: 400, config: config)
        XCTAssertEqual(p.time, 5.3)
        XCTAssertEqual(p.cropRatio, 0.96)
        XCTAssertEqual(p.offsetX, -0.01, accuracy: 1e-12)
        XCTAssertEqual(p.offsetY, 0.0075, accuracy: 1e-12)
    }

    func testFromMatchWithoutNCCFallsBackToAlignmentRatio() {
        let best = FrameMatcher.Candidate(time: 1.0, ncc: nil, translation: nil)
        let result = FrameMatcher.Result(best: best, method: .alignment, candidates: [best])
        let p = PhotoPlacement(photoURL: photo, match: result, frameAnalysisHeight: 320)
        XCTAssertEqual(p.cropRatio, MatchConfig.default.alignmentCropRatio)
        XCTAssertEqual(p.offsetX, 0)
        XCTAssertEqual(p.offsetY, 0)
    }
}
