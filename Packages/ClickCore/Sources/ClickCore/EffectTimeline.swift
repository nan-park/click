import Foundation
import CoreGraphics

/// 한 시각에 사진 오버레이를 어디에 얼마나 크게 그릴지. 순수 계산이라 AVFoundation 없이 테스트한다.
public enum EffectTimeline {
    public struct Overlay: Equatable, Sendable {
        /// 프레임 좌표계(원점 좌상단, y 아래)에서 사진이 차지할 사각형.
        public let rect: CGRect
        public let placement: PhotoPlacement
    }

    /// `time`에 보여야 할 오버레이. 없으면 nil. 효과 구간이 겹치면 가장 늦게 시작한 것만 그린다 —
    /// 뒤 사진의 정지(freezeDuration)가 앞 사진의 축소(shrinkDuration)보다 길어 어차피 전체 화면으로 가려지므로 결과는 같다.
    public static func overlay(at time: TimeInterval, placements: [PhotoPlacement], frameSize: CGSize,
                               config: EffectConfig = .default) -> Overlay? {
        let active = placements.filter { time >= $0.time && time < $0.time + config.totalDuration }
        guard let p = active.max(by: { $0.time < $1.time }) else { return nil }
        let elapsed = time - p.time
        let rect: CGRect
        if elapsed < config.freezeDuration {
            rect = CGRect(origin: .zero, size: frameSize)
        } else {
            let raw = (elapsed - config.freezeDuration) / config.shrinkDuration
            let t = easeOut(min(max(raw, 0), 1))
            let full = CGRect(origin: .zero, size: frameSize)
            let thumb = thumbnailRect(frameSize: frameSize, config: config)
            rect = CGRect(
                x: lerp(full.minX, thumb.minX, t), y: lerp(full.minY, thumb.minY, t),
                width: lerp(full.width, thumb.width, t), height: lerp(full.height, thumb.height, t))
        }
        return Overlay(rect: rect, placement: p)
    }

    /// 좌하단 썸네일 위치(프레임 좌표계, y 아래).
    public static func thumbnailRect(frameSize: CGSize, config: EffectConfig = .default) -> CGRect {
        let w = frameSize.width * config.thumbnailScale
        let h = w * frameSize.height / frameSize.width
        let m = frameSize.width * config.thumbnailMargin
        return CGRect(x: m, y: frameSize.height - m - h, width: w, height: h)
    }

    /// 2차 ease-out. 곡선 선택은 추정(사용자 미확인).
    static func easeOut(_ t: Double) -> Double { 1 - (1 - t) * (1 - t) }
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}
