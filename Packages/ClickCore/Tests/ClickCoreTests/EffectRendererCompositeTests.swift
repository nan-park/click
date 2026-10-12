import XCTest
import CoreImage
@testable import ClickCore

/// 내보내기 없이 합성 함수의 좌표 변환(이미지 y-아래 ↔ CI y-위)만 검증한다.
final class EffectRendererCompositeTests: XCTestCase {
    let frameSize = CGSize(width: 100, height: 200)
    let photoURL = URL(fileURLWithPath: "/p.jpg")
    let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])

    func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ rect: CGRect) -> CIImage {
        CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: rect)
    }
    /// 이미지 좌표계(원점 좌상단)의 (x, y) 픽셀 RGB.
    func pixel(_ image: CIImage, x: Int, y: Int) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: 4)
        let ciY = Int(image.extent.height) - 1 - y
        context.render(image, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: x, y: ciY, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return Array(px[0..<3])
    }

    /// 사진: 위 절반 초록, 아래 절반 파랑. 정지 중 프레임의 위쪽은 초록이어야 한다(y축이 뒤집히면 파랑).
    func testFreezeKeepsPhotoTopAtFrameTop() {
        let frame = solid(1, 0, 0, CGRect(origin: .zero, size: frameSize))
        let top = solid(0, 1, 0, CGRect(x: 0, y: 200, width: 200, height: 200))   // CI 좌표: 위
        let bottom = solid(0, 0, 1, CGRect(x: 0, y: 0, width: 200, height: 200))
        let photo = top.composited(over: bottom).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 400))
        let p = PhotoPlacement(photoURL: photoURL, time: 1.0)
        let out = EffectRenderer.composite(frame: frame, at: 1.1, placements: [p], photos: [photoURL: photo], config: .default)
        XCTAssertEqual(pixel(out, x: 50, y: 10), [0, 255, 0])
        XCTAssertEqual(pixel(out, x: 50, y: 190), [0, 0, 255])
    }

    /// 축소가 끝난 직후 썸네일 위치(좌하단)는 사진, 반대편(우상단)은 프레임.
    func testThumbnailLandsBottomLeft() {
        let frame = solid(1, 0, 0, CGRect(origin: .zero, size: frameSize))
        let photo = solid(0, 0, 1, CGRect(x: 0, y: 0, width: 200, height: 400))
        let p = PhotoPlacement(photoURL: photoURL, time: 1.0)
        let config = EffectConfig.default
        let t = 1.0 + config.totalDuration - 0.0001
        let out = EffectRenderer.composite(frame: frame, at: t, placements: [p], photos: [photoURL: photo], config: config)
        let thumb = EffectTimeline.thumbnailRect(frameSize: frameSize, config: config)
        XCTAssertEqual(pixel(out, x: Int(thumb.midX), y: Int(thumb.midY)), [0, 0, 255])
        XCTAssertEqual(pixel(out, x: 95, y: 5), [255, 0, 0])
        XCTAssertEqual(pixel(out, x: Int(thumb.maxX) + 2, y: Int(thumb.midY)), [255, 0, 0])
    }

    /// crop: 사진 좌상단 1/4만 쓰는 배치(비율 0.5, 중심을 왼쪽·위로 1/4 이동)면 정지 화면 전체가 그 영역 색이어야 한다.
    func testCropRectUsesImageCoordinates() {
        let q = CGFloat(100)
        let topLeft = solid(0, 1, 0, CGRect(x: 0, y: 200, width: 100, height: 200))     // 이미지 좌표 좌상단
        let rest = solid(0, 0, 1, CGRect(x: 0, y: 0, width: 200, height: 400))
        let photo = topLeft.composited(over: rest).cropped(to: CGRect(x: 0, y: 0, width: 2 * q, height: 4 * q))
        let p = PhotoPlacement(photoURL: photoURL, time: 0, cropRatio: 0.5, offsetX: -0.25, offsetY: -0.25)
        let cropped = EffectRenderer.cropped(photo, placement: p)
        XCTAssertEqual(cropped.extent, CGRect(x: 0, y: 0, width: 100, height: 200))
        let frame = solid(1, 0, 0, CGRect(origin: .zero, size: frameSize))
        let out = EffectRenderer.composite(frame: frame, at: 0.1, placements: [p], photos: [photoURL: cropped], config: .default)
        XCTAssertEqual(pixel(out, x: 5, y: 5), [0, 255, 0])
        XCTAssertEqual(pixel(out, x: 95, y: 195), [0, 255, 0])
    }

    func testNoOverlayReturnsFrameUnchanged() {
        let frame = solid(1, 0, 0, CGRect(origin: .zero, size: frameSize))
        let out = EffectRenderer.composite(frame: frame, at: 0, placements: [], photos: [:], config: .default)
        XCTAssertEqual(pixel(out, x: 50, y: 100), [255, 0, 0])
    }
}
