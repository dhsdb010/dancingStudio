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
    /// One section per 8-count phrase, the way dancers learn choreography:
    /// each runs from a "1" to the next "1", exactly eight counts. A pickup
    /// before the first "1" and a partial phrase at the end aren't sections of
    /// their own; they still play when the whole routine does. Empty when the
    /// clip is shorter than one phrase.
    public static func eightCounts(_ grid: BeatGrid, start: TimeInterval, end: TimeInterval) -> [RoutineSection] {
        let phrase = 8 * 60 / grid.bpm
        // A little slack so a phrase ending right at the trim point counts.
        let slack = phrase / 32
        var sections: [RoutineSection] = []
        for downbeat in stride(from: grid.firstDownbeat, to: grid.beats.count, by: 8) {
            let phraseStart = grid.beats[downbeat]
            // The next "1" when the grid has it, else one phrase later.
            let phraseEnd = downbeat + 8 < grid.beats.count ? grid.beats[downbeat + 8] : phraseStart + phrase
            guard phraseStart >= start - slack else { continue }
            guard phraseEnd <= end + slack else { break }
            sections.append(RoutineSection(index: sections.count, start: max(start, phraseStart), end: min(end, phraseEnd)))
        }
        return sections
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
