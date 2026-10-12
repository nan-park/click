import Foundation

/// 사진 한 장이 탐색 구간의 어느 프레임에 해당하는지 찾는다.
///
/// 판정 규칙(샘플 실측 근거, PROGRESS.md):
/// 1. 프레임마다 Vision으로 사진→프레임 이동량 d를 추정한다. 패닝 중에는 NCC 봉우리가 평평해도 |d|의 영점은 뾰족하다.
/// 2. |d| 최소 프레임을 고르고, 동률(허용 오차 내)은 NCC가 높은 쪽.
/// 3. 최소 이동량조차 크면(민무늬 벽의 쓰레기값, 또는 사진이 영상 프레이밍과 어긋난 경우) NCC 최대 프레임으로 폴백.
public enum FrameMatcher {
    public enum Method: Sendable { case alignment, ncc }

    public struct Candidate: Sendable {
        public let time: TimeInterval
        /// crop 비율 후보 중 최선의 NCC와 그 비율. 사진·프레임 어느 쪽이 민무늬면 nil.
        public let ncc: (score: Float, cropRatio: Double)?
        /// Vision 이동량. CGImage 생성 실패·한도 초과면 nil.
        public let translation: VisionAligner.Translation?
    }

    public struct Result: Sendable {
        public let best: Candidate
        public let method: Method
        /// 시간순 전체 후보. 디버깅·신뢰도 판단용.
        public let candidates: [Candidate]
    }

    public static func match(photo: GrayImage, frames: [FrameExtractor.Frame], config: MatchConfig = .default) throws -> Result? {
        guard let first = frames.first else { return nil }
        let w = first.image.width, h = first.image.height
        // crop별 사진은 프레임마다 같으므로 한 번만 만든다.
        let crops = try config.cropRatios.map { ratio in
            (ratio, try photo.centerCrop(ratio: ratio, toWidth: w, height: h))
        }
        let alignmentCropCG = try photo.centerCrop(ratio: config.alignmentCropRatio, toWidth: w, height: h).toCGImage()
        let maxTranslation = config.maxTranslationFraction * Double(w)

        var candidates: [Candidate] = []
        candidates.reserveCapacity(frames.count)
        for frame in frames {
            var bestNCC: (score: Float, cropRatio: Double)? = nil
            for (ratio, crop) in crops {
                guard let s = crop.ncc(with: frame.image) else { continue }
                if bestNCC == nil || s > bestNCC!.score { bestNCC = (s, ratio) }
            }
            var translation = alignmentCropCG.flatMap { VisionAligner.translation(floatingCG: $0, reference: frame.image) }
            if let t = translation, t.magnitude > maxTranslation { translation = nil }
            candidates.append(Candidate(time: frame.time, ncc: bestNCC, translation: translation))
        }

        let aligned = candidates.filter { $0.translation != nil }
        if let minMagnitude = aligned.map({ $0.translation!.magnitude }).min(),
           minMagnitude <= config.maxBestTranslationFraction * Double(w) {
            let ties = aligned.filter { $0.translation!.magnitude <= minMagnitude + config.translationTieTolerance }
            if let best = ties.max(by: nccAscending) {
                return Result(best: best, method: .alignment, candidates: candidates)
            }
        }
        guard let best = candidates.filter({ $0.ncc != nil }).max(by: nccAscending) else { return nil }
        return Result(best: best, method: .ncc, candidates: candidates)
    }

    /// NCC 없는 후보는 가장 낮게.
    static func nccAscending(_ a: Candidate, _ b: Candidate) -> Bool {
        switch (a.ncc, b.ncc) {
        case (nil, nil): return false
        case (nil, _): return true
        case (_, nil): return false
        case let (x?, y?): return x.score < y.score
        }
    }
}
