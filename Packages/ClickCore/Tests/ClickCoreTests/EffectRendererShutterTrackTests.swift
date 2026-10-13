import XCTest
import AVFoundation
@testable import ClickCore

/// 찰칵 음원 트랙 배치만 검증한다(내보내기 없음). 겹치지 않는 클립은 한 트랙을 재사용하고, 겹치면 트랙을 늘린다.
/// 영상은 examples 샘플(오디오 1트랙 활성), 음원은 테스트가 만든 합성 톤.
final class EffectRendererShutterTrackTests: XCTestCase {
    static let video = SampleMatchTests.video
    static let soundDuration = 0.6
    static let soundSampleRate = 48_000.0

    var soundURL: URL!

    override func setUpWithError() throws {
        soundURL = FileManager.default.temporaryDirectory.appendingPathComponent("click-test-\(UUID().uuidString).caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: Self.soundSampleRate, channels: 1)!
        let file = try AVAudioFile(forWriting: soundURL, settings: format.settings)
        let frames = AVAudioFrameCount(Self.soundDuration * Self.soundSampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) { buffer.floatChannelData![0][i] = sinf(Float(i) * 0.1) * 0.5 }
        try file.write(from: buffer)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: soundURL)
    }

    func audioTrackCount(times: [TimeInterval]) async throws -> Int {
        var config = EffectConfig.default
        config.shutterSoundURL = soundURL
        let placements = times.map { PhotoPlacement(photoURL: URL(fileURLWithPath: "/p.jpg"), time: $0) }
        let composition = try await EffectRenderer.makeComposition(videoURL: Self.video, config: config, placements: placements)
        return try await composition.loadTracks(withMediaType: .audio).count
    }

    func testNoSoundAddsNoTrack() async throws {
        var config = EffectConfig.default
        config.shutterSoundURL = nil
        let composition = try await EffectRenderer.makeComposition(videoURL: Self.video, config: config,
                                                                   placements: [PhotoPlacement(photoURL: URL(fileURLWithPath: "/p.jpg"), time: 5)])
        let count = try await composition.loadTracks(withMediaType: .audio).count
        XCTAssertEqual(count, 1, "원본 활성 오디오 1트랙만")
    }

    func testNonOverlappingClipsShareOneTrack() async throws {
        let count = try await audioTrackCount(times: [1.0, 5.0, 5.0 + Self.soundDuration, 15.0])
        XCTAssertEqual(count, 2, "원본 1 + 셔터 1")
    }

    func testOverlappingClipsGetSeparateTracks() async throws {
        let count = try await audioTrackCount(times: [5.0, 5.2, 5.4])
        XCTAssertEqual(count, 4, "원본 1 + 셔터 3(모두 겹침)")
    }

    func testUnsortedInputIsHandledInTimeOrder() async throws {
        let count = try await audioTrackCount(times: [15.0, 1.0, 8.0])
        XCTAssertEqual(count, 2)
    }

    func testClipsOutsideVideoAreSkipped() async throws {
        let videoDuration = try await VideoTimestamp.read(from: Self.video).duration
        let count = try await audioTrackCount(times: [-1.0, videoDuration + 1])
        XCTAssertEqual(count, 1)
    }

    /// 영상 끝 직전의 사진: 클립이 영상 길이에서 잘려 합성 길이가 늘지 않아야 한다.
    func testClipNearEndIsTrimmedToVideoDuration() async throws {
        let videoDuration = try await VideoTimestamp.read(from: Self.video).duration
        var config = EffectConfig.default
        config.shutterSoundURL = soundURL
        let placements = [PhotoPlacement(photoURL: URL(fileURLWithPath: "/p.jpg"), time: videoDuration - 0.1)]
        let composition = try await EffectRenderer.makeComposition(videoURL: Self.video, config: config, placements: placements)
        let total = try await composition.load(.duration).seconds
        XCTAssertEqual(total, videoDuration, accuracy: 0.002)
        // 트랙 timeRange는 앞 빈 구간을 포함하므로 마지막 세그먼트(실제 클립)를 본다.
        let shutter = try await composition.loadTracks(withMediaType: .audio).last!
        let clip = try await shutter.load(.segments).last!.timeMapping.target
        XCTAssertEqual(clip.end.seconds, videoDuration, accuracy: 0.002)
        XCTAssertEqual(clip.duration.seconds, 0.1, accuracy: 0.002)
    }

    func testMissingSoundThrows() async throws {
        var config = EffectConfig.default
        config.shutterSoundURL = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).caf")
        do {
            _ = try await EffectRenderer.makeComposition(videoURL: Self.video, config: config,
                                                         placements: [PhotoPlacement(photoURL: URL(fileURLWithPath: "/p.jpg"), time: 5)])
            XCTFail("없는 음원은 throw해야 한다")
        } catch {}
    }
}
