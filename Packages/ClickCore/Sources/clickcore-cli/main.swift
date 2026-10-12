import Foundation
import ClickCore

// 실험용 CLI.
//   clickcore-cli meta <video> <photo...>    사진별 계산 위치와 탐색 구간
//   clickcore-cli frames <video> <photo>     탐색 구간의 프레임 PTS 목록
let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else {
    print("usage: clickcore-cli <meta|frames> <video> <photo...>")
    exit(2)
}
let command = args[0]
let videoURL = URL(fileURLWithPath: args[1])
let photoURLs = args.dropFirst(2).map { URL(fileURLWithPath: $0) }

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
