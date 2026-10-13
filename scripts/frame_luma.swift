// 영상의 특정 시각 프레임 평균 밝기와 PNG를 뽑는 일회성 확인 스크립트. 정지 화면(사진)과 영상 프레임의 밝기 비교용.
// 사용: swift scripts/frame_luma.swift <video> <outdir> <t1> <t2> ...
//
// 숫자의 뜻: AVAssetImageGenerator가 HLG 영상을 SDR(BT.709 전달함수)로 바꾼 프레임을 다시 8bit sRGB로 변환한 뒤
// 감마 인코딩된 RGB 평균에서 구한 luma(0-1). 즉 "Mac에서 AVFoundation의 HLG→SDR 변환을 거친 값"이며
// HDR 디스플레이가 실제로 내는 밝기가 아니다. 선형광 비율은 이보다 차이가 크다. PNG도 같은 sRGB 8bit로 저장한다.
import Foundation
import AVFoundation
import CoreImage

let args = CommandLine.arguments
guard args.count >= 4 else { print("usage: swift scripts/frame_luma.swift <video> <outdir> <t1> <t2> ..."); exit(2) }
let videoURL = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])
var times: [Double] = []
for raw in args.dropFirst(3) {
    guard let t = Double(raw) else { print("bad time: \(raw)"); exit(2) }
    times.append(t)
}

/// 프레임 요청 허용 오차. 샘플이 30fps라 한 프레임 뒤까지 허용한다(앞은 0 — 요청 시각 이전 프레임을 받지 않기 위해).
let frameInterval = CMTime(value: 1, timescale: 30)
/// 분석·저장 크기(세로 영상 기준 1/4). 평균만 보므로 작게 뽑는다.
let maxSize = CGSize(width: 270, height: 480)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

do {
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let gen = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
    gen.appliesPreferredTrackTransform = true
    gen.requestedTimeToleranceBefore = .zero
    gen.requestedTimeToleranceAfter = frameInterval
    gen.maximumSize = maxSize
    let ctx = CIContext()
    for t in times {
        let cg = try gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil)
        let img = CIImage(cgImage: cg)
        guard let avg = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: img, kCIInputExtentKey: CIVector(cgRect: img.extent)])?.outputImage
        else { print("CIAreaAverage unavailable"); exit(1) }
        var px = [UInt8](repeating: 0, count: 4)
        ctx.render(avg, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: sRGB)
        let luma = (0.2126 * Double(px[0]) + 0.7152 * Double(px[1]) + 0.0722 * Double(px[2])) / 255
        print(String(format: "t=%.2f meanRGB=(%d,%d,%d) luma=%.3f", t, px[0], px[1], px[2], luma))
        let pngURL = outDir.appendingPathComponent(String(format: "f%.2f.png", t))
        try ctx.writePNGRepresentation(of: img, to: pngURL, format: .RGBA8, colorSpace: sRGB)
    }
} catch {
    print("error: \(error)")
    exit(1)
}
