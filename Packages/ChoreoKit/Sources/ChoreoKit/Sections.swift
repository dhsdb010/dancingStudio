import Foundation

/// One step of the tutorial: a stretch of the routine to learn on its own.
public struct RoutineSection: Codable, Hashable, Identifiable, Sendable {
    public var index: Int
    public var start: TimeInterval
    public var end: TimeInterval
    public var id: Int { index }

    public init(index: Int, start: TimeInterval, end: TimeInterval) {
        self.index = index
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end - start }
}

/// Splits a routine into tutorial sections.
public enum Sectioner {
    /// One section per 8-count, the way dancers learn choreography. Cuts fall
    /// on every 8th beat from the first downbeat. A lead-in shorter than two
    /// beats joins the first 8-count, and a tail shorter than four beats joins
    /// the last, so no section is a sliver.
    public static func eightCounts(_ grid: BeatGrid, start: TimeInterval, end: TimeInterval) -> [RoutineSection] {
        let beat = 60 / grid.bpm
        let cuts = stride(from: grid.firstDownbeat, to: grid.beats.count, by: 8)
            .map { grid.beats[$0] }
            .filter { $0 > start + 2 * beat && $0 < end - 4 * beat }
        return sections(cutAt: cuts, start: start, end: end)
    }

    /// Equal sections of about `length` seconds, for videos without a usable
    /// beat (no music, or no steady tempo).
    public static func fixedLength(start: TimeInterval, end: TimeInterval, length: TimeInterval = 4) -> [RoutineSection] {
        let count = max(1, Int(((end - start) / length).rounded()))
        let step = (end - start) / Double(count)
        return sections(cutAt: (1..<count).map { start + Double($0) * step }, start: start, end: end)
    }

    private static func sections(cutAt cuts: [TimeInterval], start: TimeInterval, end: TimeInterval) -> [RoutineSection] {
        let bounds = [start] + cuts + [end]
        return zip(bounds, bounds.dropFirst()).enumerated().map { i, pair in
            RoutineSection(index: i, start: pair.0, end: pair.1)
        }
    }
}
