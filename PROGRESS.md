# 진행 상황  (갱신: 2026-10-13)

## 현재 단계
1·2단계 코어 완성(macOS 실측). 3단계(UI) 소스 작성 완료 — **미컴파일**. 이 Mac에 Xcode·iOS SDK가 없어 `swiftc -parse` 문법 검사만 통과.
`Click.xcodeproj`는 아직 없음 → `Click/XCODE_SETUP.md` 절차로 Xcode 있는 Mac에서 생성.

## 직전 완료 (2026-10-13)
- 3단계 UI 소스 `Click/` 6파일: `ClickApp`(진입) · `AppConfig`(앱 층 고정값) · `PhotoLibraryService`(권한·녹화 시간대 사진 탐색·원본 추출·썸네일·저장) ·
  `MatchPipeline`(cli `render`와 같은 순서로 매칭→배치, `nonisolated`) · `SessionModel`(@Observable 상태기계: 영상 선택→탐색→제외 검토→매칭→렌더→저장) ·
  `ContentView`(PhotosPicker `.videos`/`.current` → 후보 목록 Toggle(제외만) → 진행 → 완료/실패).
  영상은 PhotosPicker Transferable로 파일 사본을 받아 `VideoTimestamp.read` → `creationDate` ± `candidateSearchPadding`(5s, 추정)로 PHAsset 사진 조회.
  사진은 `PHAssetResourceManager.writeData` 원본(EXIF 유지)으로 임시 폴더에 쓰고 코어에 URL로 넘김. 결과는 `creationRequestForAssetFromVideo`로 보관함 저장.
  적대 리뷰 15건 중 반영: 매칭 함수 `nonisolated`(기본 격리 MainActor 대비) / 취소 시 pickedItem 초기화(같은 영상 재선택 불가 버그) /
  사진 임시 파일명에 인덱스(originalFilename 충돌) / 전부 실패 시 첫 실패 사유를 에러에 포함 / 썸네일 요청을 px(displayScale 곱) / 출력 확장자를 코어 outputFileType에서 파생 /
  렌더 진행률 Task가 saving 뒤 늦게 와도 단계 안 되돌림 / 임포트 사본·이전 워크스페이스 정리 / Info.plist 파일 삭제(필수 키 없이 GENERATE=No면 설치 실패) → 키는 SETUP 문서로.
  기각: SwiftUI 간격 리터럴 상수화(관례상 인라인, 썸네일 치수만 AppConfig로) / `MatchPipeline`을 코어로 이동(등급 A, 아래 제안).
  리뷰 지적 범위 안의 수정이라 재리뷰 생략.
- 미커밋이던 썸네일 22%/4% 확정 기록 커밋(리뷰 생략은 사용자 결정).

## 직전 완료 (2026-10-12)
- 2단계 코어: `PhotoPlacement`(매칭 결과 → crop 비율·오프셋), `EffectTimeline`(시각별 오버레이 사각형, 순수 함수),
  `EffectRenderer`(AVMutableComposition + CIFilter 핸들러 합성 → AVAssetExportSession HEVC, 불가 시 H.264), `EffectConfig`(고정값).
  `clickcore-cli render`로 샘플 7장 합성 — 출력 hvc1 10bit HLG + dvvC 유지(AVMutableComposition 경유 확인), 정지·축소·썸네일 프레임 눈으로 확인.
  사용자 결정: 정지 0.7s + 좌하단 축소 이동 0.3s / 찰칵 음원 미정(무음, `shutterSoundURL`만 열어둠) / 최소 iOS 17 유지(deprecated 합성 API 사용).
  썸네일 폭 22%·여백 4%는 사용자 확정(2026-10-12), 2차 ease-out 곡선은 추정. 적대 리뷰 31건 중 프리셋 폴백 미작동·셔터음 insert 밀림·출력 파일 무단 삭제 등 반영,
  합성 좌표 변환은 단위 테스트 4개 작성 + 이 Mac에서 같은 단언을 `scripts/composite_check`(swift run)로 9/9 통과 확인. 셔터음 트랙 삽입 코드는 음원이 없어 미실행.
- HDR(HLG) 유지 내보내기 가능 여부 조사 → 가능(아래 실측). `scripts/hdr_export_probe.swift`로 이 Mac(macOS, CLT)에서 실측.
  결정: 내보내기는 AVAssetExportSession + `AVAssetExportPresetHEVCHighestQuality` + CIFilter 핸들러 합성, 색 속성은 지정하지 않음(기본 정책이 HLG 유지). 실제 기기(iOS 26) 확인은 3단계(UI)에서.
- FrameMatcher: 프레임마다 Vision 평행이동 d 추정(crop 1.0) → |d| 최소 프레임, 동률(같은 크기)은 NCC. 최소 |d|가 폭의 5% 초과면 NCC 폴백.
  검증: `clickcore-cli match`로 확정 4장 ±1프레임(4178→5.300, 4179→8.533, 4180→11.067, 4182→15.865), 4176→1.433·4177→3.433·4181→14.932 구간 안.
  적대 리뷰 12건 반영(Vision dy 부호를 이미지 좌표계로 뒤집음 등). 단위·샘플 테스트 5파일은 작성만(이 Mac에 XCTest 없음).

## 지금 할 일 (전부 Xcode 있는 Mac 필요)
1. `Packages/ClickCore`에서 `swift test` — 매칭 + EffectTimeline·PhotoPlacement·EffectRendererComposite 통과 확인.
2. `Click/XCODE_SETUP.md`대로 `Click.xcodeproj` 생성 → `Click/` 컴파일. 컴파일 오류는 UI 소스가 미컴파일이라 있을 수 있음(특히 액터 격리·PhotosPicker API).
3. 실기기(iPhone 16, iOS 26)에서 전체 흐름 실행 → 보관함 저장(성공 기준 2) + HLG 유지·정지 화면 밝기 확인.
   첫 실행에서 확인할 추정값: PhotoKit `creationDate`가 EXIF 시각과 같은지(탐색 패딩 5s가 충분한지), Transferable `.current`가 원본 파일(creationdate 메타 포함)을 주는지.

## 제안 (미승인)
- `MatchPipeline`(UI·PhotoKit 의존 없는 코어 조합)을 `Packages/ClickCore`로 옮기면 `swift test`·cli가 같은 코드를 쓴다. 등급 A라 보류.

## 열린 결정
- (해결) 내보내기 형식: HLG 유지, HEVC. SDR로 바꿔야 할 때는 `AVAssetExportPresetHighestQuality`(H.264·BT.709)를 쓰면 됨(실측).
- 정지 화면(SDR 사진)이 HDR 디스플레이에서 영상 하이라이트보다 어둡게 보일지 — 기기에서 봐야 안다. 어두우면 사진에 헤드룸을 주는 처리(예: 톤 올리기)를 그때 결정.
- (해결 2026-10-13) 찰칵 음원: 첫 버전은 무음 유지(사용자 결정). `shutterSoundURL`은 열어둠. 시스템 셔터음(AudioServices 1108)은 파일로 못 꺼낸다(추정, 출처 미확인).
- (해결 2026-10-12) 합성 API: 최소 iOS 17 유지, `init(asset:applyingCIFiltersWithHandler:)`(iOS 18 deprecated) 사용. `export(to:as:)`·`states(updateInterval:)`도 iOS 18이라 `export()` + `progress` 폴링.

## 막힌 것
- 이 Mac(CLT만)에는 XCTest·Xcode·iOS SDK 없음 → 테스트·앱 빌드·xcodeproj 생성은 Xcode 있는 Mac에서. 2026-10-13 세션도 같은 Mac이라 UI는 소스만 작성.
- 이 Mac의 `/usr/bin/python3`에 PIL 없음(다른 python3 없음). 이미지 확인은 `sips`로 JPEG 축소 후 보는 식으로 대신함. CLAUDE.md "검증은 PIL로"는 현재 이 Mac에서 못 씀.

## 실측 (다시 조사하지 말 것)
- EXIF: DateTimeOriginal + SubsecTimeOriginal(ms) + OffsetTimeOriginal 있음. 영상: com.apple.quicktime.creationdate = 녹화 시작, 초 단위(2026-10-12T16:06:46+0900). 18.0s, 30fps, 1080×1920(표시 크기, 저장은 1920×1080 + 회전 행렬), HDR BT.2020 HLG.
- 사진 1980×3520, 화각은 프레임보다 약 3~5% 넓음(눈 추정) → 중심 crop 비율 1에 가까움. 정답 프레임의 Vision d(이미지 좌표, 폭 180): 4178 (+1,0), 4179 (0,−3), 4180 (0,0), 4182 (+2,0), 4181 정지 (+1,−2).
- 계산 위치보다 실제 프레임이 약 1초 앞: −0.92, −1.03, −1.04, −1.30s. 원인·기기별 일정 여부 미확인(샘플 1개).
- 정답(눈으로 확인): 4178→5.333s, 4179→8.567s, 4180→11.067s, 4182→15.865s. 미확정은 구간 판정: 4176 1.4~1.9s(카메라 정지, d≈(−9,−11) 일정, NCC 0.4~0.5; 하한을 매처 결과에 맞춰 1.5→1.4로 넓힘 — 사용자 결정), 4177 2.7~3.5s(민무늬 벽 패닝, Vision d ±100px 쓰레기값), 4181 14.7~15.0s(정지 장면).
- 패닝(4179)에서 dx가 +4→−3 단조 변화하며 정답에서 0 통과 — NCC 봉우리(평평)보다 변별력 큼.
- 프레임 PTS는 1/30s 격자에 가깝지만 균일하지 않음(간격 최대 0.035s, 총 544프레임). AVAssetImageGenerator는 요청 시각 절삭으로 한 프레임 앞을 주므로 AVAssetReader PTS를 쓴다.
- HDR 내보내기(macOS 26 CLT 실측, iOS 기기 미확인): 샘플 영상은 hvc1 BitsPerComponent=10 BT.2020/HLG + `dvvC` 아톰(추정: Dolby Vision 8.4, 프로파일은 안 읽음). CIFilter 핸들러 합성(사진 1초 덮어쓰기)을 `AVAssetExportPresetHEVCHighestQuality`로 내보내면 색 속성 지정 없이도 출력이 hvc1 10bit BT.2020/HLG + dvvC로 유지됨(HLG 명시 지정과 포맷 설명 수준에서 동일, 픽셀 비교는 안 함). `AVAssetExportPresetHighestQuality`는 avc1 8bit BT.709로 SDR 변환. 오디오는 원본 2트랙(AAC 스테레오 enabled, APAC 4ch 공간음향 disabled) 중 AAC 스테레오만 남음(네 변형 모두). 출력은 회전이 구워져 1080×1920(원본 1920×1080 + 변환 행렬). 18s 내보내기 약 3s.
- 2단계 합성(macOS 26 CLT 실측): AVMutableComposition(비디오 + 활성 오디오 트랙 복사, preferredTransform 복사) + CIFilter 핸들러 → HEVC 프리셋 출력도 hvc1 10bit HLG + dvvC 유지. 18s 영상 사진 7장 합성 약 3.5s. 4176은 crop 0.92 + 오프셋 +0.05로 창이 사진 오른쪽을 1% 넘어 → 창을 안쪽으로 미는 보정 추가.
- 샘플 사진: Display P3 8bit, HDR 게인맵 없음. `expandToHDR` 옵션으로도 1.0 초과 값 없음 → SDR. HLG 합성에 넣은 사진 프레임을 SDR로 톤매핑해 보면 같은 장면의 영상 프레임과 밝기가 비슷해 보임(눈 비교, 수치 없음).
- 미확인: 샘플 jpg가 HEIC 변환본인지 / 4K·60fps·타 기기에서의 밀림·해상도.
- 미확인(확인 필요, 샘플 요청): ① 가로 영상+가로 사진 — 회전 분기(0/180°)는 있으나 실측 없음. ② 녹화 중 폰을 돌려 찍은 사진 — 사진 EXIF 방향이 영상과 다르면 크기 불일치로 매칭이 nil. iOS가 그렇게 저장하는지부터 미확인.

## 기각된 방법
- 72×128 그레이 NCC + 중앙 잘라내기 비율만 탐색: 민무늬 벽 빠른 패닝(4177) 실패. NCC + 위치 자유 탐색 + 전체 검색: 4179가 7.400s 오답. 자유도 넓힌 전역 검색 금지.
- 오디오 셔터음 탐지: 녹화 중에는 셔터음이 나지 않음(사용자 확인). 탐색 구간 −2~+2 대칭: 이웃 사진 순간이 창에 들어와 오답 위험, 실측 밀림이 음수뿐이라 −2~+0.5 유지.
- 정합 폴백 조건 "정합 성공 프레임 50% 미만": 정답에서 먼 프레임은 당연히 한도를 넘어 실패로 세어짐. 동률 허용 0.5px: (1,3)과 (0,3)이 묶여 NCC 편향으로 2프레임 밀림.
