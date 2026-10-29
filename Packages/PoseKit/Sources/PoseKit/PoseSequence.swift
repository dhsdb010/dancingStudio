import Foundation

/// The poses extracted from a stretch of video, in time order.
/// Frames where nobody was detected have no joints, so the timeline has no gaps.
public struct PoseSequence: Codable, Equatable, Sendable {
    /// Times are in seconds on the source video's timeline.
    public var start: TimeInterval
    public var end: TimeInterval
    public var frames: [PoseFrame]

    public init(start: TimeInterval, end: TimeInterval, frames: [PoseFrame]) {
        self.start = start
        self.end = end
        self.frames = frames
    }

    /// The frame closest to `time`, or nil if the nearest one is more than
    /// `tolerance` seconds away.
    public func frame(at time: TimeInterval, tolerance: TimeInterval = 0.1) -> PoseFrame? {
        guard !frames.isEmpty else { return nil }
        // Binary search for the first frame at or after `time`.
        var low = 0, high = frames.count
        while low < high {
            let mid = (low + high) / 2
            if frames[mid].time < time { low = mid + 1 } else { high = mid }
        }
        let candidates = [low - 1, low].filter { frames.indices.contains($0) }
        let nearest = candidates.min { abs(frames[$0].time - time) < abs(frames[$1].time - time) }!
        return abs(frames[nearest].time - time) <= tolerance ? frames[nearest] : nil
    }
}
