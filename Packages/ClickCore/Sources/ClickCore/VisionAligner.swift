import Foundation
import CoreGraphics
import Vision

/// Vision 정합으로 사진(crop)과 프레임 사이의 평행이동을 추정한다.
///
/// Vision은 정합 실패를 보고하지 않는다 — 민무늬 입력에도 쓰레기 이동량을 돌려준다.
/// 한도 검사는 호출자(FrameMatcher.maxTranslationFraction)가 한다.
public enum VisionAligner {
    /// 이미지 좌표계(원점 좌상단, y 아래) 기준, 사진 crop을 얼마나 옮겨야 프레임에 맞는지(픽셀).
    public struct Translation: Sendable, Equatable {
        public let dx: Double
        public let dy: Double
        public var magnitude: Double { (dx * dx + dy * dy).squareRoot() }
    }

    /// `floating`(사진 crop)을 `reference`(프레임)에 맞추는 평행이동. CGImage 생성 실패나 Vision 오류면 nil.
    public static func translation(floating: GrayImage, reference: GrayImage) -> Translation? {
        guard let floatingCG = floating.toCGImage() else { return nil }
        return translation(floatingCG: floatingCG, reference: reference)
    }

    /// 같은 사진 crop을 여러 프레임에 대조할 때 CGImage를 한 번만 만들기 위한 변형.
    public static func translation(floatingCG: CGImage, reference: GrayImage) -> Translation? {
        guard let referenceCG = reference.toCGImage() else { return nil }
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: floatingCG)
        let handler = VNImageRequestHandler(cgImage: referenceCG)
        do { try handler.perform([request]) } catch { return nil }
        guard let obs = request.results?.first else { return nil }
        let t = obs.alignmentTransform
        // Vision은 y축이 위로 향하는 좌표계로 돌려준다. 이미지 좌표계로 바꾸기 위해 ty 부호를 뒤집는다.
        return Translation(dx: Double(t.tx) + 0, dy: -Double(t.ty) + 0)  // "+ 0"은 -0.0 제거
    }
}
