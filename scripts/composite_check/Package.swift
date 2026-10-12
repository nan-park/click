// swift-tools-version: 5.9
// EffectRendererCompositeTests와 같은 단언을 XCTest 없는 Mac에서 돌리기 위한 일회성 검증 패키지.
// 실행: cd scripts/composite_check && swift run -c release
import PackageDescription
let package = Package(name: "composite_check", platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Packages/ClickCore")],
    targets: [.executableTarget(name: "composite_check", dependencies: ["ClickCore"])])
