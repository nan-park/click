import Foundation
import ClickCore

/// 사진 한 장의 매칭 결과. 실패해도 전체를 멈추지 않고 사유만 남긴다.
struct MatchOutcome: Identifiable {
    enum Status {
        case matched(PhotoPlacement)
        case outsideVideo
        case noMatch
        case failed(Error)
    }
    let id: URL
    let status: Status

    var placement: PhotoPlacement? {
        if case .matched(let p) = status { return p }
        return nil
    }
}

/// clickcore-cli `render`와 같은 순서로 사진마다 프레임을 판정해 배치를 만든다. UI·PhotoKit 의존 없음.
/// `nonisolated`: 프로젝트 기본 액터 격리가 MainActor여도 동기 매칭(NCC·Vision)이 메인 스레드로 가지 않게 한다. 인자는 모두 Sendable.
enum MatchPipeline {
    nonisolated static func match(videoURL: URL, video: VideoTimestamp, photoURLs: [URL],
                      progress: @MainActor (Int) -> Void) async -> [MatchOutcome] {
        var outcomes: [MatchOutcome] = []
        for (index, url) in photoURLs.enumerated() {
            outcomes.append(MatchOutcome(id: url, status: await matchOne(videoURL: videoURL, video: video, photoURL: url)))
            await progress(index + 1)
        }
        return outcomes
    }

    nonisolated private static func matchOne(videoURL: URL, video: VideoTimestamp, photoURL: URL) async -> MatchOutcome.Status {
        do {
            let photoTime = try PhotoTimestamp.read(from: photoURL)
            let window = SearchWindow(photo: photoTime, video: video)
            guard !window.isEmpty else { return .outsideVideo }
            let frames = try await FrameExtractor.frames(url: videoURL, in: window)
            guard let first = frames.first else { return .outsideVideo }
            let photo = try ImageLoader.loadGray(url: photoURL)
            guard let result = try FrameMatcher.match(photo: photo, frames: frames) else { return .noMatch }
            return .matched(PhotoPlacement(photoURL: photoURL, match: result, frameAnalysisHeight: first.image.height))
        } catch {
            return .failed(error)
        }
    }
}
