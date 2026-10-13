import SwiftUI
import PhotosUI
import Photos

struct ContentView: View {
    @State private var model = SessionModel()
    @State private var pickedItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .idle:
                    pickerScreen
                case .loadingVideo:
                    status("영상 불러오는 중…")
                case .searchingPhotos:
                    status("녹화 중 찍은 사진 찾는 중…")
                case .review:
                    ReviewView(model: model, onCancel: startOver)
                case .matching(let done, let total):
                    status("사진 순간 찾는 중… \(done)/\(total)")
                case .rendering(let progress):
                    status("효과 넣는 중…", progress: progress)
                case .saving:
                    status("사진 보관함에 저장 중…")
                case .finished(let summary):
                    finishedScreen(summary)
                case .failed(let message):
                    failedScreen(message)
                }
            }
            .navigationTitle("Click")
        }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task { await model.load(item) }
        }
    }

    /// pickedItem을 비워야 같은 영상을 다시 골랐을 때 onChange가 다시 발화한다.
    private func startOver() {
        pickedItem = nil
        model.reset()
    }

    private var pickerScreen: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "camera.shutter.button")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("녹화 중 찍은 사진 순간에\n찰칵 효과를 넣어 드립니다.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            PhotosPicker(selection: $pickedItem, matching: .videos, preferredItemEncoding: .current) {
                Label("영상 선택", systemImage: "film")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
        .padding()
    }

    private func status(_ text: String, progress: Double? = nil) -> some View {
        VStack(spacing: 16) {
            if let progress {
                ProgressView(value: progress)
            } else {
                ProgressView()
            }
            Text(text).foregroundStyle(.secondary)
        }
        .padding(32)
    }

    private func finishedScreen(_ summary: SessionModel.Summary) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("사진 보관함에 저장했습니다.")
            Text("사진 \(summary.matched)장 적용" + (summary.skipped > 0 ? ", \(summary.skipped)장은 영상 밖이거나 순간을 못 찾아 제외" : ""))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button("다른 영상", action: startOver)
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .padding()
    }

    private func failedScreen(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)
            Text(message).multilineTextAlignment(.center)
            Spacer()
            Button("처음으로", action: startOver)
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .padding()
    }
}

/// 자동 탐색된 사진 목록. 사용자는 뺄 것만 해제한다(CLAUDE.md 비목표: 수동 선택 없음).
struct ReviewView: View {
    @Bindable var model: SessionModel
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if model.candidates.isEmpty {
                ContentUnavailableView("녹화 시간대에 찍은 사진이 없습니다", systemImage: "photo.on.rectangle.angled")
            } else {
                List($model.candidates) { $candidate in
                    CandidateRow(candidate: $candidate)
                }
                .listStyle(.plain)
            }
            Button {
                Task { await model.run() }
            } label: {
                Text("사진 \(model.includedCount)장으로 만들기")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.includedCount == 0)
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소", action: onCancel)
            }
        }
    }
}

struct CandidateRow: View {
    @Binding var candidate: SessionModel.Candidate
    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: UIImage?

    var body: some View {
        Toggle(isOn: $candidate.isIncluded) {
            HStack(spacing: 12) {
                Group {
                    if let thumbnail {
                        Image(uiImage: thumbnail).resizable().scaledToFill()
                    } else {
                        Color.secondary.opacity(0.2)
                    }
                }
                .frame(width: AppConfig.thumbnailCellSide, height: AppConfig.thumbnailCellSide)
                .clipShape(RoundedRectangle(cornerRadius: AppConfig.thumbnailCornerRadius))
                VStack(alignment: .leading) {
                    Text(candidate.asset.creationDate.map { $0.formatted(date: .omitted, time: .standard) } ?? "시각 없음")
                    Text(candidate.isIncluded ? "효과 넣음" : "제외")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: candidate.id) {
            thumbnail = await PhotoLibraryService.thumbnail(
                for: candidate.asset, size: AppConfig.thumbnailRequestSize(displayScale: displayScale))
        }
    }
}
