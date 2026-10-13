import Foundation
import CoreGraphics

/// 앱 층의 고정값. 코어 고정값은 `EffectConfig`·`MatchConfig`.
enum AppConfig {
    /// 녹화 시간대 사진 탐색 시 PhotoKit creationDate 구간을 양쪽으로 넓히는 여유.
    /// PhotoKit 시각과 EXIF 시각이 같은 값인지 미확인이라 넉넉히 둔다(추정). 정밀한 구간 판정은 코어 `SearchWindow`가 한다.
    static let candidateSearchPadding: TimeInterval = 5
    /// 후보 목록 썸네일 셀 한 변(pt)과 모서리 반지름(pt).
    static let thumbnailCellSide: CGFloat = 56
    static let thumbnailCornerRadius: CGFloat = 8
    /// PhotoKit 썸네일 요청 크기는 픽셀 단위라 화면 배율을 곱한다.
    static func thumbnailRequestSize(displayScale: CGFloat) -> CGSize {
        CGSize(width: thumbnailCellSide * displayScale, height: thumbnailCellSide * displayScale)
    }
    /// 작업 파일(영상 사본·사진 원본·출력)을 두는 임시 폴더 이름 접두사.
    static let workspacePrefix = "click-"
    /// 출력 파일 이름 접두사. 뒤에 타임스탬프가 붙는다.
    static let outputPrefix = "Click-"
}
