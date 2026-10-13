import Foundation
import Photos
import UIKit

enum PhotoLibraryError: Error, LocalizedError {
    case notAuthorized(PHAuthorizationStatus)
    case noPhotoResource(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "사진 보관함 접근 권한이 없습니다. 설정에서 허용해 주세요."
        case .noPhotoResource(let id): return "사진 원본을 찾을 수 없습니다 (\(id))."
        }
    }
}

/// PhotoKit 접근을 한곳에 모은다. 권한 · 녹화 시간대 사진 탐색 · 원본 파일 추출 · 썸네일 · 결과 저장.
enum PhotoLibraryService {
    /// 전체 읽기 + 저장 권한(CLAUDE.md 고정값). 자동 탐색에 필수.
    static func ensureAuthorized() async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        // limited는 탐색이 사용자가 고른 사진에만 되므로 전체 권한만 통과시킨다.
        guard status == .authorized else { throw PhotoLibraryError.notAuthorized(status) }
    }

    /// 녹화 시간대(여유 포함)에 생성된 사진을 촬영 순으로.
    static func photos(between start: Date, and end: Date) -> [PHAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@",
            PHAssetMediaType.image.rawValue, start as NSDate, end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    /// 사진 원본(EXIF 포함)을 파일로 쓴다. 코어는 URL로만 읽으므로 변환본이 아닌 원본 리소스를 쓴다.
    /// 파일명에 `index`를 앞세운다 — 다른 기기에서 합쳐진 사진은 originalFilename이 겹칠 수 있고 writeData는 기존 파일을 덮지 않는다.
    static func writeOriginalPhoto(_ asset: PHAsset, index: Int, to directory: URL) async throws -> URL {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .photo }) ?? resources.first else {
            throw PhotoLibraryError.noPhotoResource(asset.localIdentifier)
        }
        let url = directory.appendingPathComponent("\(index)-" + resource.originalFilename)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
                if let error { c.resume(throwing: error) } else { c.resume() }
            }
        }
        return url
    }

    /// 목록용 썸네일. deliveryMode를 고정해 콜백이 한 번만 오게 한다.
    static func thumbnail(for asset: PHAsset, size: CGSize) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        return await withCheckedContinuation { c in
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
                c.resume(returning: image)
            }
        }
    }

    /// 내보낸 영상을 사진 보관함에 추가한다(성공 기준 2).
    static func saveVideo(at url: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}
