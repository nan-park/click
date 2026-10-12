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

    public init() {}
    public static let `default` = MatchConfig()
}
