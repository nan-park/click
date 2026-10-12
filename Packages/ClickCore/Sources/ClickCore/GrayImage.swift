import Foundation
import CoreGraphics
import ImageIO

public enum GrayImageError: Error, Equatable {
    case invalidSize(width: Int, height: Int)
    case cropOutOfBounds
}

/// 매칭용 Float 그레이스케일 이미지. 0...1, row-major.
public struct GrayImage: Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [Float]

    public init(width: Int, height: Int, pixels: [Float]) {
        precondition(pixels.count == width * height)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// CGImage를 `targetWidth` 폭으로 축소하며 그레이 변환.
    public init(cgImage: CGImage, targetWidth: Int) throws {
        let scale = Double(targetWidth) / Double(cgImage.width)
        let w = targetWidth
        let h = Int((Double(cgImage.height) * scale).rounded())
        guard w > 0, h > 0, w <= cgImage.width else { throw GrayImageError.invalidSize(width: w, height: h) }
        var bytes = [UInt8](repeating: 0, count: w * h)
        try bytes.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(
                data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { throw GrayImageError.invalidSize(width: w, height: h) }
            ctx.interpolationQuality = .high
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        self.init(width: w, height: h, pixels: bytes.map { Float($0) / 255 })
    }

    public subscript(x: Int, y: Int) -> Float { pixels[y * width + x] }

    /// 정규화된 상호상관(NCC), −1...1.
    /// 크기가 다르거나 어느 한쪽이 민무늬(분산 0)면 상관을 정의할 수 없어 nil.
    public func ncc(with other: GrayImage) -> Float? {
        guard width == other.width, height == other.height else { return nil }
        let n = Float(pixels.count)
        var sa: Float = 0, sb: Float = 0
        for i in 0..<pixels.count { sa += pixels[i]; sb += other.pixels[i] }
        let ma = sa / n, mb = sb / n
        var num: Float = 0, da: Float = 0, db: Float = 0
        for i in 0..<pixels.count {
            let a = pixels[i] - ma, b = other.pixels[i] - mb
            num += a * b; da += a * a; db += b * b
        }
        let denom = (da * db).squareRoot()
        return denom > 0 ? num / denom : nil
    }

    /// 중심 기준 `ratio` 배 영역을 (offsetX, offsetY)만큼(전체 폭·높이 대비 비율) 옮겨 잘라내고 bilinear로 리사이즈.
    /// 잘라낼 영역이 이미지 밖으로 나가면 throw — 가장자리 복제로 가짜 데이터를 만들지 않는다.
    public func centerCrop(ratio: Double, offsetX: Double = 0, offsetY: Double = 0, toWidth w: Int, height h: Int) throws -> GrayImage {
        guard w > 0, h > 0 else { throw GrayImageError.invalidSize(width: w, height: h) }
        let cw = Double(width) * ratio, ch = Double(height) * ratio
        let x0 = (Double(width) - cw) / 2 + offsetX * Double(width)
        let y0 = (Double(height) - ch) / 2 + offsetY * Double(height)
        guard ratio > 0, x0 >= 0, y0 >= 0, x0 + cw <= Double(width), y0 + ch <= Double(height) else {
            throw GrayImageError.cropOutOfBounds
        }
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            let sy = y0 + (Double(y) + 0.5) / Double(h) * ch - 0.5
            for x in 0..<w {
                let sx = x0 + (Double(x) + 0.5) / Double(w) * cw - 0.5
                out[y * w + x] = sample(sx, sy)
            }
        }
        return GrayImage(width: w, height: h, pixels: out)
    }

    func sample(_ fx: Double, _ fy: Double) -> Float {
        let x = min(max(fx, 0), Double(width - 1)), y = min(max(fy, 0), Double(height - 1))
        let x0 = Int(x), y0 = Int(y)
        let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
        let tx = Float(x - Double(x0)), ty = Float(y - Double(y0))
        let top = self[x0, y0] * (1 - tx) + self[x1, y0] * tx
        let bot = self[x0, y1] * (1 - tx) + self[x1, y1] * tx
        return top * (1 - ty) + bot * ty
    }

    /// Vision 입력용 8비트 그레이 CGImage.
    public func toCGImage() -> CGImage? {
        let bytes = pixels.map { UInt8((min(max($0, 0), 1) * 255).rounded()) }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// 시계 방향 90° × `quarterTurns` 회전.
    public func rotated(quarterTurns: Int) -> GrayImage {
        let turns = ((quarterTurns % 4) + 4) % 4
        if turns == 0 { return self }
        let (nw, nh) = turns % 2 == 0 ? (width, height) : (height, width)
        var out = [Float](repeating: 0, count: nw * nh)
        for y in 0..<height {
            for x in 0..<width {
                let (nx, ny): (Int, Int)
                switch turns {
                case 1: (nx, ny) = (height - 1 - y, x)
                case 2: (nx, ny) = (width - 1 - x, height - 1 - y)
                default: (nx, ny) = (y, width - 1 - x)
                }
                out[ny * nw + nx] = self[x, y]
            }
        }
        return GrayImage(width: nw, height: nh, pixels: out)
    }
}

public enum ImageLoader {
    /// 방향(EXIF orientation)을 적용해 `maxPixelSize`(긴 변) 이하로 축소한 CGImage.
    public static func loadDownsampled(url: URL, maxPixelSize: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw MediaTimestampError.cannotOpenImage(url)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let img = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw MediaTimestampError.cannotOpenImage(url)
        }
        return img
    }

    /// 사진을 매칭용 그레이 이미지로. 썸네일은 긴 변 기준이라 여유 있게 받은 뒤 폭을 analysisWidth로 한 번 축소한다.
    public static func loadGray(url: URL, config: MatchConfig = .default) throws -> GrayImage {
        let cg = try loadDownsampled(url: url, maxPixelSize: config.analysisWidth * config.photoThumbnailLongSideFactor)
        return try GrayImage(cgImage: cg, targetWidth: config.analysisWidth)
    }
}
