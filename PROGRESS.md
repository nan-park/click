# 진행 상황  (갱신: 2026-10-12)

## 현재 단계
1단계(프레임 매칭 보강) 진행 중. 메타데이터·탐색 구간·프레임 추출까지 완료, 매칭 알고리즘 미착수.

## 직전 완료 (2026-10-12)
- 킥오프로 CLAUDE.md 확정. git 초기화, origin=github.com/nan-park/click.
- `Packages/ClickCore`: EXIF/QuickTime 시각 읽기, SearchWindow, AVAssetReader 기반 프레임 추출(실제 PTS), GrayImage(NCC·crop·회전).
  검증: `swift build` 통과, `clickcore-cli meta|frames`로 샘플 7장 구간·PTS 확인. 적대 리뷰 13건 반영(12번 naturalSize 유지는 기각).
  단위 테스트 2파일은 작성만 됨 — 이 Mac에 XCTest 없음, 다른 Mac에서 `swift test` 필요.

## 지금 할 일
1. FrameMatcher 구현: 구간 내 프레임 vs 사진 중심 crop(비율 0.93~1.0 좁게) NCC + Vision 정합(VNTranslational/Homographic)으로 점수.
2. 샘플 정합 테스트(`swift test`, Xcode 있는 Mac): 확정 4장 ±1프레임, 미확정 3장은 구간 통과(4176 1.5~1.9s, 4177 2.7~3.5s, 4181 14.7~15.0s).

## 열린 결정
- HDR 유지 가능 여부 조사 결과에 따른 최종 내보내기 형식 (조사 후 보고).

## 막힌 것
- 이 Mac(CLT만)에는 XCTest·Xcode 없음 → 테스트와 2·3단계 앱 빌드는 Xcode 있는 Mac에서. 당분간 clickcore-cli로 실험.

## 실측 (다시 조사하지 말 것)
- EXIF: DateTimeOriginal + SubsecTimeOriginal(ms) + OffsetTimeOriginal 있음.
- 영상: com.apple.quicktime.creationdate = 녹화 시작, 초 단위(2026-10-12T16:06:46+0900). 18.0s, 30fps, 1080×1920, HDR BT.2020 HLG.
- 사진 1980×3520, 영상보다 해상도 높고 화각 약간 넓음(눈 추정 3~5%, 4178·4180 비교) → 중심 crop 비율은 1에 가깝다.
- 프레임 PTS는 1/30s 격자에 가깝지만 균일하지 않음(간격 최대 0.035s, 15.865s 같은 값 존재, 총 544프레임). AVAssetImageGenerator는 요청 시각 절삭으로 한 프레임 앞을 주므로 AVAssetReader PTS를 쓴다.
- 계산 위치보다 실제 프레임이 약 1초 앞: 실측 −0.92, −1.03, −1.04, −1.30s. 원인·기기별 일정 여부 미확인(샘플 1개).
- 정답: 4178→5.333s, 4180→11.067s, 4182→15.865s, 4179→8.567s(눈으로 확인).
- 미확정(구간으로만 판정, 눈으로 확정하지 않기로 결정 2026-10-12): 4176 약 1.7s(근사), 4177 2.7~3.5s(민무늬 벽 패닝), 4181 14.7~15.0s(정지 장면).
- 미확인: 샘플 jpg가 HEIC 변환본인지 / 4K·60fps·타 기기에서의 밀림·해상도.

## 기각된 방법
- 72×128 그레이 NCC + 중앙 잘라내기 비율만 탐색: 민무늬 벽 빠른 패닝(4177) 실패.
- NCC + 잘라내기 비율(0.6~1.0)·위치 자유 탐색 + 영상 전체 검색: 4179가 7.400s 오답. 자유도 넓힌 전역 검색 금지.
- 오디오 트랙에서 셔터음 탐지: 녹화 중에는 셔터음이 나지 않음(사용자 확인). 시작·끝 소리만 있어 사진 타이밍 정보 없음.
