import Foundation

/// 사진 효과의 고정값 (첫 버전은 커스터마이즈 없음, 사용자 결정 2026-10-12: 정지 0.7s + 축소 이동 0.3s).
public struct EffectConfig: Sendable {
    /// 캡처 사진이 전체 화면으로 정지해 있는 시간.
    public var freezeDuration: TimeInterval = 0.7
    /// 정지 뒤 좌하단 썸네일 크기로 축소·이동하며 사라지는 시간.
    public var shrinkDuration: TimeInterval = 0.3
    /// 썸네일 폭 = 프레임 폭 × 이 값. 사용자 확정 2026-10-12.
    public var thumbnailScale: Double = 0.22
    /// 썸네일의 좌·하단 여백 = 프레임 폭 × 이 값. 사용자 확정 2026-10-12.
    public var thumbnailMargin: Double = 0.04
    /// 찰칵 소리 파일. nil이면 무음(음원 미정, 사용자 결정 2026-10-12).
    public var shutterSoundURL: URL? = nil
    /// 내보내기 진행률을 읽는 간격.
    public var progressInterval: Duration = .milliseconds(250)

    public var totalDuration: TimeInterval { freezeDuration + shrinkDuration }

    public init() {}
    public static let `default` = EffectConfig()
}
