import Foundation
import Photos
import PhotosUI
import SwiftUI
import ClickCore
import UniformTypeIdentifiers

/// 영상 한 편을 처리하는 동안의 상태. 화면은 이 phase만 보고 그린다.
@MainActor @Observable
final class SessionModel {
    enum Phase {
        case idle
        case loadingVideo
        case searchingPhotos
        case review
        case matching(done: Int, total: Int)
        case rendering(progress: Double)
        case saving
        case finished(Summary)
        case failed(String)
    }

    struct Candidate: Identifiable {
        let asset: PHAsset
        var isIncluded = true
        var id: String { asset.localIdentifier }
    }

    struct Summary {
        let matched: Int
        /// 영상 밖이거나 순간을 못 찾았거나 읽기 실패한 장수.
        let skipped: Int
        let preset: String
    }

    private(set) var phase: Phase = .idle
    private(set) var video: VideoTimestamp?
    var candidates: [Candidate] = []

    private var workspace: URL?
    private var videoURL: URL?

    var includedCount: Int { candidates.filter(\.isIncluded).count }

    // MARK: 영상 선택

    /// PhotosPicker 결과. 원본 인코딩 그대로 파일로 받아 녹화 시작 시각을 읽고 같은 시간대 사진을 찾는다.
    func load(_ item: PhotosPickerItem) async {
        reset()
        phase = .loadingVideo
        do {
            let workspace = try makeWorkspace()
            self.workspace = workspace
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                throw SessionError.cannotLoadMovie
            }
            // 임포트 사본은 워크스페이스 밖에 생기므로 옮기기 전에 실패하면 여기서 지운다.
            defer { try? FileManager.default.removeItem(at: movie.file) }
            let url = workspace.appendingPathComponent(movie.file.lastPathComponent)
            try FileManager.default.moveItem(at: movie.file, to: url)
            videoURL = url
            let video = try await VideoTimestamp.read(from: url)
            self.video = video

            phase = .searchingPhotos
            try await PhotoLibraryService.ensureAuthorized()
            let start = video.startDate.addingTimeInterval(-AppConfig.candidateSearchPadding)
            let end = video.startDate.addingTimeInterval(video.duration + AppConfig.candidateSearchPadding)
            candidates = PhotoLibraryService.photos(between: start, and: end).map { Candidate(asset: $0) }
            phase = .review
        } catch {
            fail(error)
        }
    }

    // MARK: 만들기

    /// 포함된 사진을 원본으로 꺼내 매칭·합성하고 사진 보관함에 저장한다.
    func run() async {
        guard let workspace, let videoURL, let video else { return }
        let assets = candidates.filter(\.isIncluded).map(\.asset)
        do {
            phase = .matching(done: 0, total: assets.count)
            var photoURLs: [URL] = []
            for (index, asset) in assets.enumerated() {
                photoURLs.append(try await PhotoLibraryService.writeOriginalPhoto(asset, index: index, to: workspace))
            }
            let outcomes = await MatchPipeline.match(videoURL: videoURL, video: video, photoURLs: photoURLs) { [weak self] done in
                self?.phase = .matching(done: done, total: assets.count)
            }
            let placements = outcomes.compactMap(\.placement)
            guard !placements.isEmpty else { throw SessionError.nothingMatched(reason: Self.firstFailureReason(outcomes)) }

            phase = .rendering(progress: 0)
            let outputURL = workspace
                .appendingPathComponent(AppConfig.outputPrefix + Self.stamp(video.startDate))
                .appendingPathExtension(Self.outputExtension)
            let job = EffectRenderer.Job(videoURL: videoURL, placements: placements, outputURL: outputURL)
            var config = EffectConfig.default
            config.shutterSoundURL = Bundle.main.url(forResource: AppConfig.shutterSoundName, withExtension: AppConfig.shutterSoundExtension)
            // 번들에 음원이 없으면 빌드 구성 문제다. 디버그에서는 멈추고, 릴리스에서는 무음으로 계속한다.
            assert(config.shutterSoundURL != nil, "번들에 \(AppConfig.shutterSoundName).\(AppConfig.shutterSoundExtension) 없음")
            let output = try await EffectRenderer.render(job, config: config) { [weak self] p in
                Task { @MainActor in
                    // 폴링 Task가 saving 전환 뒤에 늦게 돌아도 단계를 되돌리지 않는다.
                    if let self, case .rendering = self.phase { self.phase = .rendering(progress: p) }
                }
            }

            phase = .saving
            try await PhotoLibraryService.saveVideo(at: output.url)
            phase = .finished(Summary(matched: placements.count, skipped: outcomes.count - placements.count, preset: output.preset))
            cleanupWorkspace()
        } catch {
            fail(error)
        }
    }

    init() {
        Self.sweepStaleWorkspaces()
    }

    func reset() {
        cleanupWorkspace()
        phase = .idle
        video = nil
        candidates = []
        videoURL = nil
    }

    // MARK: 내부

    private func fail(_ error: Error) {
        cleanupWorkspace()
        phase = .failed(error.localizedDescription)
    }

    private func makeWorkspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(AppConfig.workspacePrefix + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 이 세션이 만든 임시 폴더만 지운다. 다른 경로는 건드리지 않는다.
    private func cleanupWorkspace() {
        if let workspace { try? FileManager.default.removeItem(at: workspace) }
        workspace = nil
    }

    /// 코어의 출력 컨테이너(`EffectRenderer.outputFileType`)에서 확장자를 얻는다.
    private static var outputExtension: String {
        UTType(EffectRenderer.outputFileType.rawValue)?.preferredFilenameExtension ?? EffectRenderer.outputFileType.rawValue
    }

    /// 전부 실패했을 때 첫 읽기 실패의 사유. 기기 첫 실행에서 원인을 알기 위한 것.
    private static func firstFailureReason(_ outcomes: [MatchOutcome]) -> String? {
        for o in outcomes {
            if case .failed(let error) = o.status { return error.localizedDescription }
        }
        return nil
    }

    /// 앱이 강제 종료돼 남은 이전 워크스페이스를 지운다. 이 앱 접두사가 붙은 폴더만.
    private static func sweepStaleWorkspaces() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        guard let names = try? fm.contentsOfDirectory(atPath: tmp.path) else { return }
        for name in names where name.hasPrefix(AppConfig.workspacePrefix) {
            try? fm.removeItem(at: tmp.appendingPathComponent(name))
        }
    }

    private static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }
}

enum SessionError: Error, LocalizedError {
    case cannotLoadMovie
    case nothingMatched(reason: String?)

    var errorDescription: String? {
        switch self {
        case .cannotLoadMovie: return "영상을 불러오지 못했습니다."
        case .nothingMatched(let reason):
            let base = "영상에서 사진 순간을 찾지 못했습니다."
            return reason.map { base + "\n" + $0 } ?? base
        }
    }
}

/// PhotosPicker가 주는 영상 파일. 임시 위치로 복사만 하고, 최종 위치는 SessionModel이 정한다.
struct PickedMovie: Transferable {
    let file: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.file) } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "-" + received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(file: copy)
        }
    }
}
