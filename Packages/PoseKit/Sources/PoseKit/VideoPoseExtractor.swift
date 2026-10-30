import AVFoundation
import ImageIO

/// Runs body pose detection over a video file, sampling at most
/// `maxFramesPerSecond` frames per second. Follows one dancer when several
/// people are in frame and smooths their joints.
public struct VideoPoseExtractor: Sendable {
    public enum ExtractionError: Error {
        case noVideoTrack
        case readerFailed(Error?)
    }

    public var maxFramesPerSecond: Double
    private let detector = VisionBodyPoseDetector()

    public init(maxFramesPerSecond: Double = 30) {
        self.maxFramesPerSecond = maxFramesPerSecond
    }

    /// Extracts poses between `start` and `end` (seconds; nil means the whole
    /// video). `progress` receives values from 0 to 1. Checks for task
    /// cancellation between frames.
    public func extract(
        from url: URL,
        start: TimeInterval = 0,
        end: TimeInterval? = nil,
        progress: @Sendable (Double) -> Void = { _ in }
    ) async throws -> PoseSequence {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExtractionError.noVideoTrack
        }
        let duration = try await asset.load(.duration).seconds
        let transform = try await track.load(.preferredTransform)
        let orientation = CGImagePropertyOrientation(videoTransform: transform)
        let end = min(end ?? duration, duration)

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw ExtractionError.readerFailed(reader.error) }

        let minInterval = 1 / maxFramesPerSecond
        var tracker = PoseTracker()
        var smoother = PoseSmoother()
        var frames: [PoseFrame] = []
        var lastTime = -Double.infinity
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            // Small slack so 30 fps sources aren't thinned by timestamp jitter.
            guard time - lastTime >= minInterval * 0.9,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            lastTime = time

            #if targetEnvironment(simulator)
            // Vision body pose can't run in the iOS Simulator; carry on with no
            // dancer so the rest of the flow (beat, phrases, saving) can be tried.
            let candidates = (try? detector.detectAll(in: pixelBuffer, orientation: orientation, time: time)) ?? []
            #else
            let candidates = try detector.detectAll(in: pixelBuffer, orientation: orientation, time: time)
            #endif
            if let dancer = tracker.select(from: candidates) {
                frames.append(smoother.smooth(dancer))
            } else {
                smoother.reset()
                frames.append(PoseFrame(time: time, joints: [:]))
            }
            // The first frame can be stamped just before `start`, so clamp.
            if end > start { progress(max(0, min(1, (time - start) / (end - start)))) }
        }
        if reader.status == .failed { throw ExtractionError.readerFailed(reader.error) }
        progress(1)
        return PoseSequence(start: start, end: end, frames: frames)
    }
}

extension CGImagePropertyOrientation {
    /// The orientation that makes frames upright, from a video track's
    /// `preferredTransform`. iPhone portrait recordings are stored landscape
    /// with a 90° rotation.
    public init(videoTransform t: CGAffineTransform) {
        switch (t.a, t.b, t.c, t.d) {
        case (0, 1, -1, 0): self = .right
        case (0, -1, 1, 0): self = .left
        case (-1, 0, 0, -1): self = .down
        default: self = .up
        }
    }
}
