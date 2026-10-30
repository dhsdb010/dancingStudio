import AVFoundation
import ImageIO
import Testing
@testable import PoseKit

/// Writes a blank `seconds`-long H.264 video at `fps` and returns its URL.
private func makeBlankVideo(seconds: Int, fps: Int32) async throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 240,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 240,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    for i in 0..<(Int32(seconds) * fps) {
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
    }
    input.markAsFinished()
    await writer.finishWriting()
    return url
}

@Test func extractsAtMostThirtyFramesPerSecond() async throws {
    let url = try await makeBlankVideo(seconds: 1, fps: 60)
    defer { try? FileManager.default.removeItem(at: url) }

    let sequence = try await VideoPoseExtractor().extract(from: url)
    #expect((29...31).contains(sequence.frames.count))
    #expect(sequence.frames.allSatisfy { $0.joints.isEmpty })
    #expect(sequence.frames.map(\.time) == sequence.frames.map(\.time).sorted())
}

@Test func extractsOnlyTheRequestedRange() async throws {
    let url = try await makeBlankVideo(seconds: 2, fps: 30)
    defer { try? FileManager.default.removeItem(at: url) }

    let sequence = try await VideoPoseExtractor().extract(from: url, start: 0.5, end: 1.5)
    #expect((29...31).contains(sequence.frames.count))
    #expect(sequence.frames.first!.time >= 0.49)
    #expect(sequence.frames.last!.time < 1.5)
}

@Test func portraitTransformMapsToRight() {
    let portrait = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
    #expect(CGImagePropertyOrientation(videoTransform: portrait) == .right)
    #expect(CGImagePropertyOrientation(videoTransform: .identity) == .up)
}

@Test func nearestFrameLookup() {
    let frames = stride(from: 0.0, to: 1.0, by: 0.1).map { PoseFrame(time: $0, joints: [:]) }
    let sequence = PoseSequence(start: 0, end: 1, frames: frames)
    #expect(abs(sequence.frame(at: 0.33)!.time - 0.3) < 1e-9)
    #expect(abs(sequence.frame(at: 0.36)!.time - 0.4) < 1e-9)
    #expect(sequence.frame(at: 5) == nil)
}

@Test func framesInRangeLookup() {
    let frames = (0..<10).map { PoseFrame(time: Double($0) / 10, joints: [:]) }
    let sequence = PoseSequence(start: 0, end: 1, frames: frames)
    #expect(sequence.frames(in: 0.25...0.55).map(\.time) == [0.3, 0.4, 0.5])
    #expect(sequence.frames(in: -1...(-0.5)).isEmpty)
    #expect(sequence.frames(in: 0.9...2).count == 1)
}

@Test func slicingKeepsTheFramesInRange() {
    let frames = (0..<10).map { PoseFrame(time: Double($0) / 10, joints: [:]) }
    let slice = PoseSequence(start: 0, end: 1, frames: frames).slice(from: 0.25, to: 0.55)
    #expect(slice.start == 0.25 && slice.end == 0.55)
    #expect(slice.frames.map(\.time) == [0.3, 0.4, 0.5])
}
