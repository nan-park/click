// EffectRendererCompositeTests와 같은 단언. XCTest 없는 Mac용(scripts/composite_check/Package.swift 참고).
import CoreImage
import ClickCore
let frameSize = CGSize(width: 100, height: 200)
let photoURL = URL(fileURLWithPath: "/p.jpg")
let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ rect: CGRect) -> CIImage { CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: rect) }
func pixel(_ image: CIImage, x: Int, y: Int) -> [UInt8] {
    var px = [UInt8](repeating: 0, count: 4)
    let ciY = Int(image.extent.height) - 1 - y
    context.render(image, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: x, y: ciY, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
    return Array(px[0..<3])
}
var fails = 0
func check(_ name: String, _ got: [UInt8], _ want: [UInt8]) { let ok = got == want; if !ok { fails += 1 }; print(ok ? "PASS" : "FAIL", name, got, want) }
// 1
do {
    let frame = solid(1, 0, 0, CGRect(origin: .zero, size: frameSize))
    let top = solid(0, 1, 0, CGRect(x: 0, y: 200, width: 200, height: 200))
    let bottom = solid(0, 0, 1, CGRect(x: 0, y: 0, width: 200, height: 200))
    let photo = top.composited(over: bottom).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 400))
    let p = PhotoPlacement(photoURL: photoURL, time: 1.0)
    let out = EffectRenderer.composite(frame: frame, at: 1.1, placements: [p], photos: [photoURL: photo], config: .default)
    check("freeze top green", pixel(out, x: 50, y: 10), [0, 255, 0])
    check("freeze bottom blue", pixel(out, x: 50, y: 190), [0, 0, 255])
}
// 2
do {
    let frame = solid(1, 0, 0, CGRect(origin: .zero, size: frameSize))
    let photo = solid(0, 0, 1, CGRect(x: 0, y: 0, width: 200, height: 400))
    let p = PhotoPlacement(photoURL: photoURL, time: 1.0)
    let config = EffectConfig.default
    let t = 1.0 + config.totalDuration - 0.0001
    let out = EffectRenderer.composite(frame: frame, at: t, placements: [p], photos: [photoURL: photo], config: config)
    let thumb = EffectTimeline.thumbnailRect(frameSize: frameSize, config: config)
    check("thumb center blue", pixel(out, x: Int(thumb.midX), y: Int(thumb.midY)), [0, 0, 255])
    check("top right red", pixel(out, x: 95, y: 5), [255, 0, 0])
    check("right of thumb red", pixel(out, x: Int(thumb.maxX) + 2, y: Int(thumb.midY)), [255, 0, 0])
}
// 3
do {
    let topLeft = solid(0, 1, 0, CGRect(x: 0, y: 200, width: 100, height: 200))
    let rest = solid(0, 0, 1, CGRect(x: 0, y: 0, width: 200, height: 400))
    let photo = topLeft.composited(over: rest).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 400))
    let p = PhotoPlacement(photoURL: photoURL, time: 0, cropRatio: 0.5, offsetX: -0.25, offsetY: -0.25)
    let cropped = EffectRenderer.cropped(photo, placement: p)
    print(cropped.extent == CGRect(x: 0, y: 0, width: 100, height: 200) ? "PASS" : "FAIL", "crop extent", cropped.extent)
    if cropped.extent != CGRect(x: 0, y: 0, width: 100, height: 200) { fails += 1 }
    let frame = solid(1, 0, 0, CGRect(origin: .zero, size: frameSize))
    let out = EffectRenderer.composite(frame: frame, at: 0.1, placements: [p], photos: [photoURL: cropped], config: .default)
    check("crop tl green", pixel(out, x: 5, y: 5), [0, 255, 0])
    check("crop br green", pixel(out, x: 95, y: 195), [0, 255, 0])
}
// 4
do {
    let frame = solid(1, 0, 0, CGRect(origin: .zero, size: frameSize))
    let out = EffectRenderer.composite(frame: frame, at: 0, placements: [], photos: [:], config: .default)
    check("no overlay red", pixel(out, x: 50, y: 100), [255, 0, 0])
}
exit(fails == 0 ? 0 : 1)
