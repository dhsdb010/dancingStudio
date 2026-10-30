import Foundation
import PoseKit
import ChoreoKit

/// Everything analysis produces for one trimmed clip: the dancer's poses, the
/// music's beat and the tutorial sections. Saved with the routine as JSON.
struct RoutineAnalysis: Codable, Sendable {
    let sequence: PoseSequence
    /// Nil when the clip has no audio or no steady beat.
    let beats: BeatGrid?
    let sections: [RoutineSection]
    /// True when `sections` are 8-count phrases rather than equal parts.
    let sectionsArePhrases: Bool

    /// Finds the beat in the clip's soundtrack and slices the routine into
    /// 8-count phrases, or into equal parts when there's no phrase to follow.
    static func make(url: URL, sequence: PoseSequence) async -> RoutineAnalysis {
        let start = sequence.start, end = sequence.end
        // A missing or unreadable soundtrack just means no beat.
        let samples = (try? await AudioLoader.samples(from: url, start: start, end: end)) ?? nil
        let beats = samples.flatMap {
            BeatTracker().track(samples: $0, sampleRate: AudioLoader.sampleRate, startTime: start)
        }
        let phrases = beats.map { Sectioner.eightCounts($0, start: start, end: end) } ?? []
        // No beat, or a clip shorter than one phrase: equal parts instead.
        let sections = phrases.isEmpty ? Sectioner.fixedLength(start: start, end: end) : phrases
        return RoutineAnalysis(sequence: sequence, beats: beats, sections: sections,
                               sectionsArePhrases: !phrases.isEmpty)
    }
}
