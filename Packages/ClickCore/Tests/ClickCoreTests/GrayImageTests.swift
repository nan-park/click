import XCTest
@testable import ClickCore

final class GrayImageTests: XCTestCase {
    func testNCCIdenticalAndInverted() {
        let a = GrayImage(width: 2, height: 2, pixels: [0, 1, 0.5, 0.25])
        let inv = GrayImage(width: 2, height: 2, pixels: a.pixels.map { 1 - $0 })
        XCTAssertEqual(a.ncc(with: a) ?? 0, 1, accuracy: 1e-5)
        XCTAssertEqual(a.ncc(with: inv) ?? 0, -1, accuracy: 1e-5)
    }

    func testNCCFlatIsUndefined() {
        let flat = GrayImage(width: 2, height: 2, pixels: [0.5, 0.5, 0.5, 0.5])
        let a = GrayImage(width: 2, height: 2, pixels: [0, 1, 0.5, 0.25])
        XCTAssertNil(flat.ncc(with: a))
        XCTAssertNil(flat.ncc(with: flat))
    }

    func testCenterCropBounds() throws {
        let img = GrayImage(width: 4, height: 4, pixels: (0..<16).map { Float($0) / 15 })
        XCTAssertNoThrow(try img.centerCrop(ratio: 0.5, toWidth: 2, height: 2))
        XCTAssertThrowsError(try img.centerCrop(ratio: 1.1, toWidth: 2, height: 2))
        XCTAssertThrowsError(try img.centerCrop(ratio: 0.5, offsetX: 0.3, toWidth: 2, height: 2))
        XCTAssertThrowsError(try img.centerCrop(ratio: 0.5, toWidth: 0, height: 2))
        let full = try img.centerCrop(ratio: 1, toWidth: 4, height: 4)
        XCTAssertEqual(full.pixels, img.pixels)
    }

    func testRotation() {
        let img = GrayImage(width: 2, height: 1, pixels: [0, 1])
        let r = img.rotated(quarterTurns: 1)
        XCTAssertEqual(r.width, 1); XCTAssertEqual(r.height, 2)
        XCTAssertEqual(r.pixels, [0, 1])
        XCTAssertEqual(img.rotated(quarterTurns: 4).pixels, img.pixels)
        XCTAssertEqual(img.rotated(quarterTurns: 2).pixels, [1, 0])
    }
}
