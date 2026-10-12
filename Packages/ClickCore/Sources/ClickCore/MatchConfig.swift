import Foundation
import CoreMedia

/// 프레임 매칭에 쓰는 상수. 값의 근거는 PROGRESS.md "실측" 항목.
public struct MatchConfig: Sendable {
    /// 계산 위치(사진 시각 − 영상 시작) 기준 탐색 구간. 실측 밀림이 −0.92~−1.30s라 음수 쪽이 넓다.
    public var searchWindowBefore: TimeInterval = 2.0
    public var searchWindowAfter: TimeInterval = 0.5
    /// 매칭용 축소 이미지의 가로 픽셀 수. 사진·프레임 모두 이 폭으로 한 번만 축소한다.
    public var analysisWidth: Int = 180
    /// 구간 시각을 CMTime으로 바꿀 때의 timescale. 600은 24/25/30/60fps의 공배수.
    public var timescale: CMTimeScale = 600
    /// 사진 썸네일 요청 시 긴 변 크기 = analysisWidth × 이 값. 세로 사진의 긴 변(세로)이 폭의 2배 안팎이라 2배 여유.
    public var photoThumbnailLongSideFactor: Int = 4

    /// 사진 중심 crop 비율 후보. 사진 화각이 프레임보다 약 3~5% 넓다(실측). 위치는 중심 고정 — 자유 탐색은 오답을 냈다(PROGRESS.md).
    public var cropRatios: [Double] = [0.92, 0.94, 0.96, 0.98, 1.0]

    /// Vision 이동량 추정에 쓰는 crop 비율. 1.0에서 정답 프레임의 이동량이 0~3px로 가장 작았다(실측).
    public var alignmentCropRatio: Double = 1.0
    /// 이동량이 분석 폭의 이 비율을 넘으면 Vision 정합 실패로 본다(민무늬 벽에서 ±100px 쓰레기값이 나옴).
    public var maxTranslationFraction: Double = 0.15
    /// 이동량 최소값과 이 픽셀 차 이내인 후보는 동률로 보고 NCC로 가른다. Vision 이동량은 정수 px라 0이면 "같은 크기"만 동률.
    /// 0.5로 두면 (1,3)=3.16과 (0,3)=3.0이 묶여 NCC 편향으로 2프레임 밀린 사례(4179)가 있다.
    public var translationTieTolerance: Double = 0.0
    /// 최소 이동량이 분석 폭의 이 비율을 넘으면 어느 프레임도 사진 프레이밍과 맞지 않는 것이므로 NCC로만 판정한다.
    /// 확정 정답 4장의 이동량은 0~3px(폭 180 기준)였다.
    public var maxBestTranslationFraction: Double = 0.05

    public init() {}
    public static let `default` = MatchConfig()
}
