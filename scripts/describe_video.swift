// 영상 트랙의 코덱·비트 깊이·색 속성·dvvC·오디오 트랙을 출력하는 일회성 확인 스크립트.
// 사용: swift scripts/describe_video.swift <video>
import Foundation
import AVFoundation

let args = CommandLine.arguments
guard args.count == 2 else { print("usage: swift scripts/describe_video.swift <video>"); exit(2) }
let url = URL(fileURLWithPath: args[1])

let sem = DispatchSemaphore(value: 0)
Task {
    do {
        let asset = AVURLAsset(url: url)
        print("duration=\(try await asset.load(.duration).seconds)")
        for track in try await asset.loadTracks(withMediaType: .video) {
            for d in try await track.load(.formatDescriptions) {
                let ext = CMFormatDescriptionGetExtensions(d) as? [String: Any] ?? [:]
                let c = CMFormatDescriptionGetMediaSubType(d)
                let fourcc = String(format: "%c%c%c%c", (c >> 24) & 255, (c >> 16) & 255, (c >> 8) & 255, c & 255)
                let dims = CMVideoFormatDescriptionGetDimensions(d)
                let atoms = ext["SampleDescriptionExtensionAtoms"] as? [String: Any]
                print("video codec=\(fourcc) \(dims.width)x\(dims.height) bits=\(ext["BitsPerComponent"] ?? "-")",
                      "primaries=\(ext[kCMFormatDescriptionExtension_ColorPrimaries as String] ?? "-")",
                      "transfer=\(ext[kCMFormatDescriptionExtension_TransferFunction as String] ?? "-")",
                      "matrix=\(ext[kCMFormatDescriptionExtension_YCbCrMatrix as String] ?? "-")",
                      "dvvC=\(atoms?["dvvC"] != nil)")
            }
            print("video size=\(try await track.load(.naturalSize)) transform=\(try await track.load(.preferredTransform))")
        }
        for track in try await asset.loadTracks(withMediaType: .audio) {
            print("audio enabled=\(try await track.load(.isEnabled)) descs=\(try await track.load(.formatDescriptions).count)")
        }
    } catch {
        print("error: \(error)")
        exit(1)
    }
    sem.signal()
}
sem.wait()
