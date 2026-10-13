# Click.xcodeproj 설정 노트

`Click.xcodeproj/project.pbxproj`는 손으로 작성했고(2026-10-13, Xcode 27.0) `xcodebuild`로 시뮬레이터·기기 아키텍처 빌드와
시뮬레이터 실행을 확인했다. Xcode GUI로 열어 수정해도 된다. 커밋 대상은 `project.pbxproj`뿐이며, GUI로 처음 열면
`project.xcworkspace/contents.xcworkspacedata`가 생긴다(커밋해도 무방). 앱 아이콘·Assets.xcassets는 아직 없다.

## 서명 (2026-10-13 설정됨)
- `PRODUCT_BUNDLE_IDENTIFIER = com.nanbob.click`, `DEVELOPMENT_TEAM = XNZ8K49A2D`(Nan Park, Individual) — 사용자 결정.
- 자동 서명. 새 Mac에서는 Xcode → Settings → Accounts에 Apple ID 로그인 후
  `xcodebuild -allowProvisioningUpdates`나 Xcode 실행이 인증서·프로파일을 만든다.
- 기기 설치·실행은 `xcrun devicectl device install app` / `device process launch --console`로 확인했다.

## 고정해 둔 설정과 이유
| 설정 | 값 | 이유 |
| --- | --- | --- |
| IPHONEOS_DEPLOYMENT_TARGET | 17.0 | CLAUDE.md 최소 iOS |
| TARGETED_DEVICE_FAMILY | 1 (iPhone) | 비목표: iPad |
| SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD / SUPPORTS_XR_… | NO | 비목표: Mac. Xcode 기본은 YES라 명시 |
| UISupportedInterfaceOrientations_iPhone | Portrait·LandscapeLeft·LandscapeRight | 사용자 결정 2026-10-13. 가로 전용 레이아웃은 없음 |
| developmentRegion | ko | 사용자 결정 2026-10-13. UI 문구는 한국어 리터럴 |
| SWIFT_VERSION | 5.0 | 코어 패키지(tools 5.9)와 같은 언어 모드 |
| SWIFT_DEFAULT_ACTOR_ISOLATION | nonisolated | Xcode 26+ 템플릿 기본(MainActor)이면 동기 매칭이 메인 스레드로 가고, 비-Sendable `PHAsset` 전달이 경고(Swift 5 모드)·오류(6 모드)가 된다. `MatchPipeline`은 별도로 `nonisolated` 명시 |
| GENERATE_INFOPLIST_FILE | YES | 권한 문구는 `INFOPLIST_KEY_NSPhotoLibraryUsageDescription`·`…AddUsageDescription`으로 생성 plist에 병합 |
| 패키지 | `Packages/ClickCore` 로컬 참조 | 외부 라이브러리 없음 |

소스는 `Click/` 그룹에 파일 단위로 참조한다(동기화 폴더 아님). 새 `.swift`를 추가하면 Xcode에서 타겟에 넣어야 한다.
`XCODE_SETUP.md`는 그룹에만 있고 Resources 단계에는 없다. `Click/Resources/shutter.m4a`는 Resources 단계에 있다(찰칵 음원).
