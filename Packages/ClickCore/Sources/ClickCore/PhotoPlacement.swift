import Foundation
import CoreGraphics

/// 사진 한 장을 영상 어느 시각에, 어떻게 잘라 올릴지. 매칭 결과에서 만든다.
public struct PhotoPlacement: Sendable, Equatable {
    public let photoURL: URL
    /// 효과가 시작되는 영상 시각(매칭된 프레임의 PTS).
    public let time: TimeInterval
    /// 사진 중심 crop 비율(사진 화각이 프레임보다 넓어 1 이하).
    public let cropRatio: Double
    /// crop 중심을 옮길 양(사진 폭·높이 대비 비율). GrayImage.centerCrop의 offsetX/offsetY와 같은 의미.
    public let offsetX: Double
    public let offsetY: Double

    public init(photoURL: URL, time: TimeInterval, cropRatio: Double = 1.0, offsetX: Double = 0, offsetY: Double = 0) {
        self.photoURL = photoURL
        self.time = time
        self.cropRatio = cropRatio
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    /// 매칭 결과로부터. 이동량 d는 "사진을 d만큼 옮기면 프레임과 맞는다"(VisionAligner)이므로
    /// 프레임과 같은 그림을 만들려면 crop 창을 −d만큼 옮긴다. d는 분석 이미지 px라 폭·높이로 나눠 비율로 바꾼다.
    /// `frameAnalysisHeight`: 매칭에 쓴 프레임 그레이 이미지의 높이(px). d는 사진 crop을 프레임 크기로 맞춘 뒤 잰 값이라 분모가 프레임 쪽이다.
    /// 주의: d는 crop 비율 1.0에서 잰 값이라 cropRatio < 1일 때는 근사다(실측 d가 0~3px/180이라 차이는 1% 미만).
    public init(photoURL: URL, match: FrameMatcher.Result, frameAnalysisHeight: Int, config: MatchConfig = .default) {
        let best = match.best
        let d = best.translation
        self.init(
            photoURL: photoURL,
            time: best.time,
            cropRatio: best.ncc?.cropRatio ?? config.alignmentCropRatio,
            offsetX: -(d?.dx ?? 0) / Double(config.analysisWidth),
            offsetY: -(d?.dy ?? 0) / Double(frameAnalysisHeight))
    }

    /// 사진 픽셀 크기에 대한 crop 사각형(원점 좌상단, 이미지 좌표계).
    /// 오프셋 때문에 창이 사진 밖으로 나가면 크기는 두고 안쪽으로 민다 — 밖을 자르면 비율이 틀어진다(4176에서 1% 초과 실측).
    public func cropRect(photoSize: CGSize) -> CGRect {
        let cw = min(photoSize.width * cropRatio, photoSize.width)
        let ch = min(photoSize.height * cropRatio, photoSize.height)
        let x = (photoSize.width - cw) / 2 + offsetX * photoSize.width
        let y = (photoSize.height - ch) / 2 + offsetY * photoSize.height
        return CGRect(
            x: min(max(x, 0), photoSize.width - cw),
            y: min(max(y, 0), photoSize.height - ch),
            width: cw, height: ch)
    }
}
