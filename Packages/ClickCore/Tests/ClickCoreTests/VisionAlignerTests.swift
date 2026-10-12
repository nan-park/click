import XCTest
@testable import ClickCore

final class VisionAlignerTests: XCTestCase {
    /// 결정적 의사난수 텍스처. Vision 정합이 붙을 만큼 무늬가 있어야 한다.
    static func texture(width: Int, height: Int, shiftX: Int, shiftY: Int) -> GrayImage {
        var px = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let sx = x - shiftX, sy = y - shiftY
                var h = UInt32(truncatingIfNeeded: sx &* 73856093 ^ sy &* 19349663)
                h ^= h >> 13; h = h &* 0x5bd1e995; h ^= h >> 15
                px[y * width + x] = Float(h % 256) / 255
            }
        }
        return GrayImage(width: width, height: height, pixels: px)
    }

    /// floating의 내용이 reference보다 오른쪽·아래로 가 있으면, floating을 왼쪽·위로(−dx, −dy) 옮겨야 맞는다.
    func testTranslationSignIsImageCoordinates() throws {
        let reference = Self.texture(width: 180, height: 320, shiftX: 0, shiftY: 0)
        let floating = Self.texture(width: 180, height: 320, shiftX: 5, shiftY: 3)
        let t = try XCTUnwrap(VisionAligner.translation(floating: floating, reference: reference))
        XCTAssertEqual(t.dx, -5, accuracy: 1)
        XCTAssertEqual(t.dy, -3, accuracy: 1)
    }

    func testIdenticalImagesHaveZeroTranslation() throws {
        let img = Self.texture(width: 180, height: 320, shiftX: 0, shiftY: 0)
        let t = try XCTUnwrap(VisionAligner.translation(floating: img, reference: img))
        XCTAssertEqual(t.magnitude, 0, accuracy: 0.5)
    }
}
