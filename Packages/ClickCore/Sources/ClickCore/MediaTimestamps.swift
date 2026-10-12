import Foundation
import ImageIO
import AVFoundation

public enum MediaTimestampError: Error, Equatable {
    case cannotOpenImage(URL)
    case missingExifDate(URL)
    /// OffsetTimeOriginal이 없으면 벽시계 시각의 시간대를 알 수 없어 영상 시각과 비교할 수 없다.
    case missingExifTimeZone(URL)
    case unparsableExifDate(String)
    case missingVideoCreationDate(URL)
    case unparsableVideoCreationDate(String)
    case noVideoTrack(URL)
}

/// 사진의 촬영 시각. EXIF DateTimeOriginal + SubsecTimeOriginal + OffsetTimeOriginal.
public struct PhotoTimestamp: Sendable, Equatable {
    public let captureDate: Date

    public init(captureDate: Date) { self.captureDate = captureDate }

    public static func read(from url: URL) throws -> PhotoTimestamp {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { throw MediaTimestampError.cannotOpenImage(url) }
        guard let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        else { throw MediaTimestampError.missingExifDate(url) }
        guard let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String else {
            throw MediaTimestampError.missingExifTimeZone(url)
        }
        let subsec = exif[kCGImagePropertyExifSubsecTimeOriginal] as? String
        return PhotoTimestamp(captureDate: try parseExif(dateString, subsec: subsec, offset: offset))
    }

    /// "2026:10:12 16:06:50" + subsec "672" + offset "+09:00"
    static func parseExif(_ dateString: String, subsec: String?, offset: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ssxxx"
        let combined = dateString + offset
        guard var date = formatter.date(from: combined) else {
            throw MediaTimestampError.unparsableExifDate(combined)
        }
        if let subsec, let fraction = Double("0." + subsec.trimmingCharacters(in: .whitespaces)) {
            date.addTimeInterval(fraction)
        }
        return date
    }
}

/// 영상의 녹화 시작 시각과 길이·프레임레이트·방향 적용 후 크기.
public struct VideoTimestamp: Sendable, Equatable {
    public let startDate: Date
    public let duration: TimeInterval
    public let nominalFrameRate: Float
    public let naturalSize: CGSize

    public init(startDate: Date, duration: TimeInterval, nominalFrameRate: Float, naturalSize: CGSize) {
        self.startDate = startDate
        self.duration = duration
        self.nominalFrameRate = nominalFrameRate
        self.naturalSize = naturalSize
    }

    public static func read(from url: URL) async throws -> VideoTimestamp {
        let asset = AVURLAsset(url: url)
        let (metadata, duration, tracks) = try await asset.load(.metadata, .duration, .tracks)
        guard let start = try await creationDate(in: metadata) else {
            throw MediaTimestampError.missingVideoCreationDate(url)
        }
        guard let track = tracks.first(where: { $0.mediaType == .video }) else {
            throw MediaTimestampError.noVideoTrack(url)
        }
        let (fps, size, transform) = try await track.load(.nominalFrameRate, .naturalSize, .preferredTransform)
        let oriented = size.applying(transform)
        return VideoTimestamp(
            startDate: start,
            duration: duration.seconds,
            nominalFrameRate: fps,
            naturalSize: CGSize(width: abs(oriented.width), height: abs(oriented.height)))
    }

    /// 아이폰 카메라는 quickTimeMetadataCreationDate(문자열), 다른 경로로 온 파일은 commonIdentifierCreationDate.
    /// 모든 식별자가 실패하면 nil. 문자열이 있었는데 하나도 파싱되지 않았으면 그 문자열로 throw.
    static func creationDate(in metadata: [AVMetadataItem]) async throws -> Date? {
        var unparsed: String?
        for identifier in [AVMetadataIdentifier.quickTimeMetadataCreationDate, .commonIdentifierCreationDate] {
            guard let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier).first
            else { continue }
            let value = try await item.load(.value)
            if let date = value as? Date { return date }
            if let raw = value as? String {
                if let date = parseQuickTimeDate(raw) { return date }
                unparsed = unparsed ?? raw
            }
        }
        if let unparsed { throw MediaTimestampError.unparsableVideoCreationDate(unparsed) }
        return nil
    }

    /// "2026-10-12T16:06:46+0900" (초 단위) 또는 소수점 포함.
    static func parseQuickTimeDate(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSxx", "yyyy-MM-dd'T'HH:mm:ssxx"] {
            formatter.dateFormat = format
            if let d = formatter.date(from: raw) { return d }
        }
        return nil
    }
}

/// 사진의 계산상 영상 내 위치와 탐색 구간.
public struct SearchWindow: Sendable, Equatable {
    /// 사진 시각 − 영상 시작 시각. 보정 전.
    public let nominalOffset: TimeInterval
    public let start: TimeInterval
    public let end: TimeInterval

    public init(photo: PhotoTimestamp, video: VideoTimestamp, config: MatchConfig = .default) {
        nominalOffset = photo.captureDate.timeIntervalSince(video.startDate)
        start = max(0, nominalOffset - config.searchWindowBefore)
        end = min(video.duration, nominalOffset + config.searchWindowAfter)
    }

    public var isEmpty: Bool { end <= start }
}
