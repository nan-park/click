// HDR(HLG) 유지 내보내기 가능 여부 조사용 일회성 스크립트 (macOS, CLT만으로 실행).
// 사용: swift scripts/hdr_export_probe.swift <video> <photo> <outdir>
// 하는 일: 영상의 색 속성 출력 → 사진을 CIFilter 핸들러로 1초 구간에 덮어 씌운 합성을
//          HEVC 프리셋으로 내보내기 → 결과 색 속성·비트 깊이 출력 → 비교용 프레임 PNG 저장.
import Foundation
import AVFoundation
import CoreImage

let args = CommandLine.arguments
guard args.count == 4 else { print("usage: <video> <photo> <outdir>"); exit(2) }
let videoURL = URL(fileURLWithPath: args[1])
let photoURL = URL(fileURLWithPath: args[2])
let outDir = URL(fileURLWithPath: args[3])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let freezeStart = 5.3, freezeDuration = 1.0 // 4178 정답 구간에 사진을 덮음

func describeTrack(_ label: String, _ url: URL) async throws {
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else { print("\(label): no video track"); return }
    let descs = try await track.load(.formatDescriptions)
    for d in descs {
        let ext = CMFormatDescriptionGetExtensions(d) as? [String: Any] ?? [:]
        let codec = CMFormatDescriptionGetMediaSubType(d)
        let fourcc = String(format: "%c%c%c%c", (codec >> 24) & 255, (codec >> 16) & 255, (codec >> 8) & 255, codec & 255)
        let dims = CMVideoFormatDescriptionGetDimensions(d)
        print("\(label): codec=\(fourcc) \(dims.width)x\(dims.height)",
              "primaries=\(ext[kCMFormatDescriptionExtension_ColorPrimaries as String] ?? "-")",
              "transfer=\(ext[kCMFormatDescriptionExtension_TransferFunction as String] ?? "-")",
              "matrix=\(ext[kCMFormatDescriptionExtension_YCbCrMatrix as String] ?? "-")",
              "bits=\(ext[kCMFormatDescriptionExtension_BitsPerComponent as String] ?? "-")",
              "depth=\(ext["Depth"] ?? "-")")
        if let atoms = ext[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String] as? [String: Any] {
            print("  atoms keys=\(atoms.keys.sorted())")
        }
    }
    let size = try await track.load(.naturalSize)
    let rate = try await track.load(.nominalFrameRate)
    print("  size=\(size) fps=\(rate) bitrate=\(try await track.load(.estimatedDataRate))")
    for t in try await asset.loadTracks(withMediaType: .audio) {
        guard let d = try await t.load(.formatDescriptions).first,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(d)?.pointee else { continue }
        let sub = CMFormatDescriptionGetMediaSubType(d)
        let fourcc = String(format: "%c%c%c%c", (sub >> 24) & 255, (sub >> 16) & 255, (sub >> 8) & 255, sub & 255)
        print("  audio#\(t.trackID) \(fourcc) ch=\(asbd.mChannelsPerFrame) sr=\(asbd.mSampleRate) enabled=\(try await t.load(.isEnabled))")
    }
}

func dumpFrame(_ url: URL, at seconds: Double, to png: URL) async throws {
    let asset = AVURLAsset(url: url)
    let gen = AVAssetImageGenerator(asset: asset)
    gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
    gen.appliesPreferredTrackTransform = true
    let (cg, _) = try await gen.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
    let ci = CIImage(cgImage: cg)
    let ctx = CIContext()
    try ctx.writePNGRepresentation(of: ci, to: png, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    print("  frame \(seconds)s -> \(png.lastPathComponent) \(cg.width)x\(cg.height) bpc=\(cg.bitsPerComponent)")
}

func export(variant: String, setHLG: Bool, preset: String, expandPhotoToHDR: Bool = false) async throws -> URL {
    let asset = AVURLAsset(url: videoURL)
    let photo = CIImage(contentsOf: photoURL, options: [.applyOrientationProperty: true, .expandToHDR: expandPhotoToHDR])!
    let comp = AVMutableVideoComposition(asset: asset) { req in
        let t = req.compositionTime.seconds
        if t >= freezeStart && t < freezeStart + freezeDuration {
            // 사진을 렌더 프레임(회전 적용된 크기)에 맞춤(종횡비 무시, 실험용)
            let ext = req.sourceImage.extent
            let scaled = photo.transformed(by: CGAffineTransform(scaleX: ext.width / photo.extent.width, y: ext.height / photo.extent.height))
            req.finish(with: scaled.cropped(to: ext), context: nil)
        } else {
            req.finish(with: req.sourceImage, context: nil)
        }
    }
    if setHLG {
        comp.colorPrimaries = AVVideoColorPrimaries_ITU_R_2020
        comp.colorTransferFunction = AVVideoTransferFunction_ITU_R_2100_HLG
        comp.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_2020
    }
    let out = outDir.appendingPathComponent("\(variant).mov")
    try? FileManager.default.removeItem(at: out)
    guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw NSError(domain: "probe", code: 1, userInfo: [NSLocalizedDescriptionKey: "preset unavailable: \(preset)"]) }
    session.videoComposition = comp
    let t0 = Date()
    try await session.export(to: out, as: .mov)
    print("\(variant): exported in \(String(format: "%.1f", Date().timeIntervalSince(t0)))s preset=\(preset) setHLG=\(setHLG)")
    return out
}

// 사진에 HDR 게인맵이 있는지, expandToHDR로 1.0 이상 값이 나오는지
func probePhoto() {
    guard let src = CGImageSourceCreateWithURL(photoURL as CFURL, nil) else { print("photo: cannot open"); return }
    let gain = CGImageSourceCopyAuxiliaryDataInfoAtIndex(src, 0, kCGImageAuxiliaryDataTypeHDRGainMap)
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] ?? [:]
    print("photo: gainMap=\(gain != nil) profile=\(props[kCGImagePropertyProfileName as String] ?? "-") depth=\(props[kCGImagePropertyDepth as String] ?? "-") hasHDR props keys=\(props.keys.filter { $0.lowercased().contains("hdr") || $0.lowercased().contains("gain") })")
    for expand in [false, true] {
        guard let img = CIImage(contentsOf: photoURL, options: [.expandToHDR: expand]) else { continue }
        let linear = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
        let ctx = CIContext(options: [.workingColorSpace: linear])
        let f = CIFilter(name: "CIAreaMaximum", parameters: [kCIInputImageKey: img, kCIInputExtentKey: CIVector(cgRect: img.extent)])!
        var px = [Float](repeating: 0, count: 4)
        ctx.render(f.outputImage!, toBitmap: &px, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: linear)
        print("  expandToHDR=\(expand) extent=\(img.extent.size) maxLinearP3=\(px[0...2].map { String(format: "%.2f", $0) }) colorSpace=\(img.colorSpace?.name.map { String($0) } ?? "-")")
    }
}

let sem = DispatchSemaphore(value: 0)
Task {
    do {
        try await describeTrack("source", videoURL)
        try await dumpFrame(videoURL, at: freezeStart + 0.2, to: outDir.appendingPathComponent("source_freeze.png"))
        try await dumpFrame(videoURL, at: 2.0, to: outDir.appendingPathComponent("source_2.0.png"))
        let presets = AVAssetExportSession.allExportPresets()
        print("presets: \(presets.sorted())")
        probePhoto()
        for (variant, setHLG, preset, expand) in [
            ("A_default_hevc", false, AVAssetExportPresetHEVCHighestQuality, false),
            ("B_hlg_hevc", true, AVAssetExportPresetHEVCHighestQuality, false),
            ("C_default_h264", false, AVAssetExportPresetHighestQuality, false),
            ("D_hevc_photoHDR", false, AVAssetExportPresetHEVCHighestQuality, true),
        ] {
            do {
                let out = try await export(variant: variant, setHLG: setHLG, preset: preset, expandPhotoToHDR: expand)
                try await describeTrack(variant, out)
                try await dumpFrame(out, at: freezeStart + 0.2, to: outDir.appendingPathComponent("\(variant)_freeze.png"))
                try await dumpFrame(out, at: 2.0, to: outDir.appendingPathComponent("\(variant)_2.0.png"))
            } catch { print("\(variant): FAILED \(error)") }
        }
    } catch { print("error: \(error)"); exit(1) }
    sem.signal()
}
sem.wait()
