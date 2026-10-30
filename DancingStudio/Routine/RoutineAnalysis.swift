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

    /// Slices the routine into 8-count phrases counting 1 from the trim
    /// start, or into equal parts when there's no phrase to follow. Uses the
    /// whole video's `beats` when the trimmer already found them, so the counts
    /// match what the trim screen showed; otherwise tracks the clip's audio.
    static func make(url: URL, sequence: PoseSequence, beats wholeVideo: BeatGrid? = nil) async -> RoutineAnalysis {
        let start = sequence.start, end = sequence.end
        var found = wholeVideo
        if found == nil {
            // A missing or unreadable soundtrack just means no beat.
            let samples = (try? await AudioLoader.samples(from: url, start: start, end: end)) ?? nil
            found = samples.flatMap {
                BeatTracker().track(samples: $0, sampleRate: AudioLoader.sampleRate, startTime: start)
            }
        }
        let beats = found?.trimmed(from: start, to: end)
        let phrases = beats.map { Sectioner.eightCounts($0, start: start, end: end) } ?? []
        // No beat, or a clip shorter than one phrase: equal parts instead.
        let sections = phrases.isEmpty ? Sectioner.fixedLength(start: start, end: end) : phrases
        return RoutineAnalysis(sequence: sequence, beats: beats, sections: sections,
                               sectionsArePhrases: !phrases.isEmpty)
    }
}
