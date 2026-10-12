import Foundation
import ClickCore

// 실험용 CLI.
//   clickcore-cli meta <video> <photo...>    사진별 계산 위치와 탐색 구간
//   clickcore-cli frames <video> <photo...>  탐색 구간의 프레임 PTS 목록
//   clickcore-cli match <video> <photo...>   사진별 판정 프레임·방법·점수
//   clickcore-cli align <video> <photo...>   프레임별 NCC와 Vision 이동량 (판정 과정 확인용)
//   clickcore-cli render <video> <out.mov> <photo...>  매칭 후 사진 효과를 합성해 내보내기
let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else {
    print("usage: clickcore-cli <meta|frames|match|align> <video> <photo...> | render <video> <out.mov> <photo...>")
    exit(2)
}
let command = args[0]
let videoURL = URL(fileURLWithPath: args[1])
let outputURL = command == "render" && args.count >= 3 ? URL(fileURLWithPath: args[2]) : nil
let photoURLs = args.dropFirst(outputURL == nil ? 2 : 3).map { URL(fileURLWithPath: $0) }

func describe(_ ncc: (score: Float, cropRatio: Double)?) -> String {
    ncc.map { String(format: "%.3f(r%.2f)", $0.score, $0.cropRatio) } ?? "-"
}
func describe(_ t: VisionAligner.Translation?) -> String {
    t.map { String(format: "(%+.0f,%+.0f)|%.1f|", $0.dx, $0.dy, $0.magnitude) } ?? "-"
}

let iso = ISO8601DateFormatter()
iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

let sem = DispatchSemaphore(value: 0)
Task {
    do {
        let video = try await VideoTimestamp.read(from: videoURL)
        print("video start=\(iso.string(from: video.startDate)) dur=\(video.duration) fps=\(video.nominalFrameRate) size=\(video.naturalSize)")
        switch command {
        case "meta":
            for url in photoURLs {
                let p = try PhotoTimestamp.read(from: url)
                let w = SearchWindow(photo: p, video: video)
                print(String(format: "%@ capture=%@ nominal=%.3f window=[%.3f, %.3f]",
                             url.lastPathComponent, iso.string(from: p.captureDate), w.nominalOffset, w.start, w.end))
            }
        case "frames":
            for url in photoURLs {
                let p = try PhotoTimestamp.read(from: url)
                let w = SearchWindow(photo: p, video: video)
                let frames = try await FrameExtractor.frames(url: videoURL, in: w)
                let times = frames.map { String(format: "%.3f", $0.time) }.joined(separator: " ")
                print("\(url.lastPathComponent) \(frames.count) frames \(frames.first?.image.width ?? 0)x\(frames.first?.image.height ?? 0): \(times)")
            }
        case "match":
            for url in photoURLs {
                let p = try PhotoTimestamp.read(from: url)
                let w = SearchWindow(photo: p, video: video)
                let frames = try await FrameExtractor.frames(url: videoURL, in: w)
                let photo = try ImageLoader.loadGray(url: url)
                guard let r = try FrameMatcher.match(photo: photo, frames: frames) else { print("\(url.lastPathComponent): no match"); continue }
                let b = r.best
                print(String(format: "%@ nominal=%.3f best=%.3f off=%+.3f method=%@ ncc=%@ d=%@",
                             url.lastPathComponent, w.nominalOffset, b.time, b.time - w.nominalOffset,
                             "\(r.method)", describe(b.ncc), describe(b.translation)))
            }
        case "align":
            for url in photoURLs {
                let p = try PhotoTimestamp.read(from: url)
                let w = SearchWindow(photo: p, video: video)
                let frames = try await FrameExtractor.frames(url: videoURL, in: w)
                let photo = try ImageLoader.loadGray(url: url)
                guard let r = try FrameMatcher.match(photo: photo, frames: frames) else { print("\(url.lastPathComponent): no match"); continue }
                print("== \(url.lastPathComponent) nominal=\(String(format: "%.3f", w.nominalOffset)) method=\(r.method)")
                for c in r.candidates {
                    print(String(format: "%.3f ncc=%@ d=%@%@", c.time, describe(c.ncc), describe(c.translation),
                                 c.time == r.best.time ? "  <== best" : ""))
                }
            }
        case "render":
            guard let outputURL else { print("usage: clickcore-cli render <video> <out.mov> <photo...>"); exit(2) }
            var placements: [PhotoPlacement] = []
            for url in photoURLs {
                let p = try PhotoTimestamp.read(from: url)
                let w = SearchWindow(photo: p, video: video)
                let frames = try await FrameExtractor.frames(url: videoURL, in: w)
                let photo = try ImageLoader.loadGray(url: url)
                guard let r = try FrameMatcher.match(photo: photo, frames: frames) else { print("\(url.lastPathComponent): no match, skipped"); continue }
                let placement = PhotoPlacement(photoURL: url, match: r, frameAnalysisHeight: frames[0].image.height)
                print(String(format: "%@ time=%.3f crop=%.2f offset=(%+.4f,%+.4f)", url.lastPathComponent,
                             placement.time, placement.cropRatio, placement.offsetX, placement.offsetY))
                placements.append(placement)
            }
            let t0 = Date()
            let out = try await EffectRenderer.render(EffectRenderer.Job(videoURL: videoURL, placements: placements, outputURL: outputURL)) { p in
                print(String(format: "  %.0f%%", p * 100))
            }
            print(String(format: "rendered %@ preset=%@ in %.1fs", out.url.lastPathComponent, out.preset, Date().timeIntervalSince(t0)))
        default:
            print("unknown command \(command)")
            exit(2)
        }
    } catch {
        print("error: \(error)")
        exit(1)
    }
    sem.signal()
}
sem.wait()
