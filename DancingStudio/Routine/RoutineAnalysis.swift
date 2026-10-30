import Foundation
import PoseKit
import ChoreoKit

/// Everything analysis produces for one trimmed clip: the dancer's poses, the
/// music's beat and the tutorial sections.
struct RoutineAnalysis {
    let sequence: PoseSequence
    /// Nil when the clip has no audio or no steady beat.
    let beats: BeatGrid?
    let sections: [RoutineSection]

    /// Finds the beat in the clip's soundtrack and slices the routine into
    /// 8-counts, or into equal sections when there's no beat to follow.
    static func make(url: URL, sequence: PoseSequence) async -> RoutineAnalysis {
        let start = sequence.start, end = sequence.end
        // A missing or unreadable soundtrack just means no beat.
        let samples = (try? await AudioLoader.samples(from: url, start: start, end: end)) ?? nil
        let beats = samples.flatMap {
            BeatTracker().track(samples: $0, sampleRate: AudioLoader.sampleRate, startTime: start)
        }
        let sections = beats.map { Sectioner.eightCounts($0, start: start, end: end) }
            ?? Sectioner.fixedLength(start: start, end: end)
        return RoutineAnalysis(sequence: sequence, beats: beats, sections: sections)
    }
}
