# Click.xcodeproj 만들기

`Click.xcodeproj`는 Xcode 없는 Mac에서 소스만 작성됐기 때문에 아직 없다. Xcode 있는 Mac에서 한 번만 만든다.
작성 기준: Xcode 26(macOS 26) · iOS 17 SDK 이상. 소스는 `@Observable`·`onChange(of:_:)` 두 인자 등 iOS 17 API만 쓴다.

1. **프로젝트는 저장소 밖**(예: `~/Desktop`)에 만든다. File → New → Project → iOS App,
   Product Name `Click`, Interface SwiftUI, Language Swift, "Create Git repository" 해제.
   저장소 루트에 바로 만들면 이미 있는 `Click/` 폴더와 충돌한다.
2. 생성된 `Click.xcodeproj`만 저장소 루트(`click/`)로 옮긴다. 템플릿의 `Click/` 소스 폴더는 버린다.
   Xcode 16+ 템플릿은 `Click/`을 동기화 폴더로 잡으므로 저장소의 `Click/*.swift`가 자동으로 타겟에 들어간다.
   `Click/XCODE_SETUP.md`는 번들 리소스로 끌려가지 않게 해당 파일 → File Inspector → Target Membership 해제.
3. File → Add Package Dependencies… → Add Local… → `Packages/ClickCore` → 타겟 `Click`에 `ClickCore` 라이브러리 연결.
4. 타겟 General → Minimum Deployments iOS 17.0. Supported Destinations는 **iPhone만**(iPad·Mac 제거 — CLAUDE.md 비목표).
   Device Orientation은 Portrait만.
5. 타겟 Info → Custom iOS Target Properties에 두 키를 추가한다(`GENERATE_INFOPLIST_FILE`은 기본값 Yes 유지):
   - `NSPhotoLibraryUsageDescription` = `녹화 중 찍은 사진을 자동으로 찾기 위해 사진 보관함 전체를 읽습니다.`
   - `NSPhotoLibraryAddUsageDescription` = `효과를 넣은 영상을 사진 보관함에 저장합니다.`
6. Build Settings → Swift Language Version **Swift 5**, Default Actor Isolation **nonisolated**(Xcode 26 템플릿 기본은 MainActor).
   `MatchPipeline`은 `nonisolated`를 명시해 두었지만, 기본 격리가 MainActor면 `PhotoLibraryService`가 비-Sendable `PHAsset`을
   넘기는 지점에서 Swift 6 모드 오류가 날 수 있어 위 조합을 기준으로 한다.
7. Signing & Capabilities → 개발 팀 선택. 실기기(iPhone 16, iOS 26)에서 실행.

생성된 `Click.xcodeproj/project.pbxproj`는 커밋한다. `xcuserdata/`는 `.gitignore`에 이미 있다.
