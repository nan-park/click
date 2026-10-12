import Foundation
import AVFoundation
import CoreGraphics

public enum FrameExtractorError: Error {
    case readerFailed(String)
    case pixelBufferUnavailable(TimeInterval)
    /// 90° 단위 회전이 아닌 preferredTransform(미러 등)은 지원하지 않는다.
    case unsupportedTransform(CGAffineTransform)
}

/// 탐색 구간의 프레임을 디코딩 순서대로 읽어 실제 PTS와 함께 돌려준다.
/// AVAssetImageGenerator는 요청 시각을 timescale로 잘라 한 프레임 앞을 돌려주는 일이 있어 쓰지 않는다.
public enum FrameExtractor {
    public struct Frame: Sendable {
        /// 프레임의 실제 표시 시각(PTS), 초.
        public let time: TimeInterval
        public let image: GrayImage
    }

    public static func frames(url: URL, in window: SearchWindow, config: MatchConfig = .default) async throws -> [Frame] {
        guard !window.isEmpty else { return [] }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw MediaTimestampError.noVideoTrack(url)
        }
        let (transform, fps) = try await track.load(.preferredTransform, .nominalFrameRate)
        let turns = try quarterTurns(of: transform)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        // 리더는 timeRange.start에 걸친 첫 샘플의 PTS를 start로 잘라 보고한다.
        // 한 프레임 앞에서 시작해 그 잘린 샘플을 구간 밖으로 밀어내고 아래에서 버린다.
        let frameDuration = fps > 0 ? 1.0 / Double(fps) : 0
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: max(0, window.start - frameDuration), preferredTimescale: config.timescale),
            end: CMTime(seconds: window.end, preferredTimescale: config.timescale))
        guard reader.startReading() else {
            throw FrameExtractorError.readerFailed(reader.error?.localizedDescription ?? "startReading")
        }

        var frames: [Frame] = []
        while let sample = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard pts >= window.start else { continue }
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else {
                throw FrameExtractorError.pixelBufferUnavailable(pts)
            }
            let gray = try grayImage(from: buffer, targetWidth: config.analysisWidth, quarterTurns: turns)
            frames.append(Frame(time: pts, image: gray))
        }
        if reader.status == .failed {
            throw FrameExtractorError.readerFailed(reader.error?.localizedDescription ?? "reading")
        }
        return frames
    }

    /// preferredTransform의 회전 성분을 시계 방향 90° 단위로.
    static func quarterTurns(of t: CGAffineTransform) throws -> Int {
        switch (t.a, t.b, t.c, t.d) {
        case (1, 0, 0, 1): return 0
        case (0, 1, -1, 0): return 1    // 90° CW (세로 촬영)
        case (-1, 0, 0, -1): return 2   // 180°
        case (0, -1, 1, 0): return 3    // 270°
        default: throw FrameExtractorError.unsupportedTransform(t)
        }
    }

    static func grayImage(from buffer: CVPixelBuffer, targetWidth: Int, quarterTurns: Int) throws -> GrayImage {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        // 사진 쪽(ImageIO, 프로파일 포함)과 같은 그레이 변환 가중치를 쓰도록 sRGB로 명시.
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: base, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: srgb,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
              let cg = ctx.makeImage()
        else { throw GrayImageError.invalidSize(width: w, height: h) }
        // 회전 전 축소: 세로 영상(90°)은 저장 폭이 긴 변이므로 회전 후 폭이 targetWidth가 되도록 맞춘다.
        let unrotatedWidth = quarterTurns % 2 == 1
            ? Int((Double(targetWidth) * Double(w) / Double(h)).rounded())
            : targetWidth
        return try GrayImage(cgImage: cg, targetWidth: unrotatedWidth).rotated(quarterTurns: quarterTurns)
    }
}
