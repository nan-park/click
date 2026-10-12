import Foundation
import AVFoundation
import CoreImage

public enum EffectRendererError: Error, Equatable {
    case cannotLoadPhoto(URL)
    /// 출력 경로에 이미 파일이 있다. 지우는 것은 호출자 책임(실수로 다른 파일을 덮지 않도록).
    case outputExists(URL)
    case exportFailed(String)
    case noCompatiblePreset
}

/// 영상 위에 사진 효과를 CIFilter 핸들러로 합성해 내보낸다.
///
/// 색: 합성의 색 속성을 지정하지 않으면 프레임워크가 HLG 소스를 HLG로 유지한다
/// (AVMutableComposition 경유 포함, macOS 실측 — PROGRESS.md). 사진은 Core Image가 작업 색공간으로 변환하므로 SDR 사진도 그대로 올린다.
public enum EffectRenderer {
    public struct Job: Sendable {
        public let videoURL: URL
        public let placements: [PhotoPlacement]
        public let outputURL: URL
        public init(videoURL: URL, placements: [PhotoPlacement], outputURL: URL) {
            self.videoURL = videoURL
            self.placements = placements
            self.outputURL = outputURL
        }
    }

    /// 합성 결과. `preset`은 실제로 쓴 내보내기 프리셋.
    public struct Output: Sendable {
        public let url: URL
        public let preset: String
    }

    /// HDR 유지 시도(HEVC) → 불가 시 SDR(H.264). CLAUDE.md 고정값.
    public static let exportPresets = [AVAssetExportPresetHEVCHighestQuality, AVAssetExportPresetHighestQuality]
    public static let outputFileType: AVFileType = .mov

    public static func render(_ job: Job, config: EffectConfig = .default,
                              progress: (@Sendable (Double) -> Void)? = nil) async throws -> Output {
        if FileManager.default.fileExists(atPath: job.outputURL.path) {
            throw EffectRendererError.outputExists(job.outputURL)
        }
        let composition = try await makeComposition(videoURL: job.videoURL, config: config, placements: job.placements)
        let photos = try loadPhotos(job.placements)
        let placements = job.placements
        let videoComposition = AVMutableVideoComposition(asset: composition) { request in
            let image = composite(frame: request.sourceImage, at: request.compositionTime.seconds,
                                  placements: placements, photos: photos, config: config)
            request.finish(with: image, context: nil)
        }

        var chosen: (AVAssetExportSession, String)?
        for preset in exportPresets {
            guard let s = AVAssetExportSession(asset: composition, presetName: preset) else { continue }
            if await AVAssetExportSession.compatibility(ofExportPreset: preset, with: composition, outputFileType: outputFileType) {
                chosen = (s, preset); break
            }
        }
        guard let (session, preset) = chosen else { throw EffectRendererError.noCompatiblePreset }
        session.videoComposition = videoComposition
        session.outputURL = job.outputURL
        session.outputFileType = outputFileType
        // iOS 17에는 states(updateInterval:)가 없어 progress를 주기적으로 읽는다.
        let poller = progress.map { report in
            Task {
                while true {
                    try? await Task.sleep(for: config.progressInterval)
                    if Task.isCancelled { return }
                    report(Double(session.progress))
                }
            }
        }
        await session.export()
        poller?.cancel()
        _ = await poller?.result
        switch session.status {
        case .completed:
            progress?(1)
            return Output(url: job.outputURL, preset: preset)
        default:
            throw EffectRendererError.exportFailed(session.error?.localizedDescription ?? "status \(session.status.rawValue)")
        }
    }

    /// 원본의 비디오·오디오 트랙을 그대로 넣은 AVMutableComposition. 찰칵 소리가 있으면 사진마다 별도 오디오 트랙에 넣는다
    /// (insertTimeRange는 끼워 넣기라 한 트랙에 이어 넣으면 뒤 소리가 밀린다).
    static func makeComposition(videoURL: URL, config: EffectConfig, placements: [PhotoPlacement]) async throws -> AVMutableComposition {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let composition = AVMutableComposition()
        guard let srcVideo = try await asset.loadTracks(withMediaType: .video).first,
              let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw MediaTimestampError.noVideoTrack(videoURL) }
        try video.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: srcVideo, at: .zero)
        video.preferredTransform = try await srcVideo.load(.preferredTransform)

        // 원본 오디오 중 활성 트랙만(아이폰의 비활성 공간음향 APAC 트랙은 내보내기가 어차피 버린다).
        for src in try await asset.loadTracks(withMediaType: .audio) where try await src.load(.isEnabled) {
            if let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try audio.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: src, at: .zero)
            }
        }

        if let soundURL = config.shutterSoundURL,
           let srcSound = try await AVURLAsset(url: soundURL).loadTracks(withMediaType: .audio).first {
            let soundDuration = try await srcSound.load(.timeRange).duration
            for p in placements where p.time >= 0 && p.time < duration.seconds {
                guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                let at = CMTime(seconds: p.time, preferredTimescale: duration.timescale)
                try track.insertTimeRange(CMTimeRange(start: .zero, duration: soundDuration), of: srcSound, at: at)
            }
        }
        return composition
    }

    /// 사진을 방향 적용해 한 번만 읽고 배치의 crop 사각형으로 잘라 둔다.
    static func loadPhotos(_ placements: [PhotoPlacement]) throws -> [URL: CIImage] {
        var result: [URL: CIImage] = [:]
        for p in placements where result[p.photoURL] == nil {
            guard let image = CIImage(contentsOf: p.photoURL, options: [.applyOrientationProperty: true]) else {
                throw EffectRendererError.cannotLoadPhoto(p.photoURL)
            }
            result[p.photoURL] = cropped(image, placement: p)
        }
        return result
    }

    /// 이미지 좌표계(원점 좌상단) crop 사각형을 CI 좌표계(원점 좌하단)로 바꿔 자르고, 원점을 (0,0)으로 옮긴다.
    public static func cropped(_ image: CIImage, placement: PhotoPlacement) -> CIImage {
        let ext = image.extent
        let crop = placement.cropRect(photoSize: ext.size)
        let ciCrop = CGRect(x: ext.minX + crop.minX, y: ext.minY + (ext.height - crop.maxY), width: crop.width, height: crop.height)
        return image.cropped(to: ciCrop).transformed(by: CGAffineTransform(translationX: -ciCrop.minX, y: -ciCrop.minY))
    }

    /// `time`의 프레임에 오버레이를 얹은 결과. 순수 함수라 내보내기 없이 테스트한다.
    /// 사진 비율이 프레임과 다르면 비율을 지키며 사각형을 채우고 넘치는 쪽을 자른다(aspect fill).
    public static func composite(frame: CIImage, at time: TimeInterval, placements: [PhotoPlacement],
                          photos: [URL: CIImage], config: EffectConfig) -> CIImage {
        let frameSize = frame.extent.size
        guard let overlay = EffectTimeline.overlay(at: time, placements: placements, frameSize: frameSize, config: config),
              let photo = photos[overlay.placement.photoURL],
              photo.extent.width > 0, photo.extent.height > 0, frameSize.width > 0, frameSize.height > 0
        else { return frame }
        let rect = overlay.rect
        let scale = max(rect.width / photo.extent.width, rect.height / photo.extent.height)
        let scaledSize = CGSize(width: photo.extent.width * scale, height: photo.extent.height * scale)
        // 프레임 좌표계(y 아래) → CI 좌표계(y 위). 채우고 남는 부분은 중앙 정렬.
        let origin = CGPoint(x: frame.extent.minX + rect.minX - (scaledSize.width - rect.width) / 2,
                             y: frame.extent.minY + (frameSize.height - rect.maxY) - (scaledSize.height - rect.height) / 2)
        let target = CGRect(x: frame.extent.minX + rect.minX, y: frame.extent.minY + (frameSize.height - rect.maxY),
                            width: rect.width, height: rect.height)
        let placed = photo
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: origin.x, y: origin.y))
            .cropped(to: target)
        return placed.composited(over: frame).cropped(to: frame.extent)
    }
}
