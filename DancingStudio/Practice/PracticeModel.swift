import Foundation
import Observation
import PoseKit
import ChoreoKit

/// Runs a practice session: plays the reference after a count-in, scores every
/// camera frame against it and keeps the step results.
@MainActor @Observable
final class PracticeModel {
    enum Phase: Equatable {
        case ready, countdown(Int), dancing, paused
    }

    let sequence: PoseSequence
    let player: RoutinePlayerModel
    let camera = LivePoseModel()
    private(set) var phase: Phase = .ready
    private(set) var results: [StepResult] = []
    private var scorer: PracticeScorer
    private var countdown: Task<Void, Never>?

    init(url: URL, sequence: PoseSequence, displaySize: CGSize) {
        self.sequence = sequence
        player = RoutinePlayerModel(url: url, start: sequence.start, end: sequence.end)
        // Camera frames are 720×1280 portrait.
        scorer = PracticeScorer(reference: sequence,
                                referenceAspect: displaySize.width / displaySize.height,
                                userAspect: 9 / 16)
        camera.onSample = { [weak self] pose in self?.score(pose) }
    }

    /// How closely the dancer matches right now, updated every camera frame.
    private(set) var liveSimilarity: Double?

    var latest: StepResult? { results.last }

    /// The rating the dancer is on track for at this moment, while dancing.
    var liveRating: StepRating? {
        guard phase == .dancing, let liveSimilarity else { return nil }
        return scorer.rating(for: liveSimilarity)
    }
    var isActive: Bool { phase == .dancing || phase.isCountdown }
    var commonFeedback: [LimbFeedback] { scorer.commonFeedback() }

    func count(of rating: StepRating) -> Int {
        results.filter { $0.rating == rating }.count
    }

    /// 0–100, averaging the points of every step.
    var score: Int {
        guard !results.isEmpty else { return 0 }
        let total = results.map(\.rating.points).reduce(0, +)
        return Int((total / Double(results.count) * 100).rounded())
    }

    /// Counts in 3-2-1 so the dancer can step back, then starts the music.
    func start() {
        guard !isActive else { return }
        countdown = Task {
            for n in (1...3).reversed() {
                phase = .countdown(n)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            phase = .dancing
            player.play()
        }
    }

    func pause() {
        countdown?.cancel()
        player.pause()
        if phase != .ready { phase = .paused }
        if scorer.finish() != nil { results = scorer.results }
        liveSimilarity = nil
    }

    /// Clears the scores and rewinds to the start of the routine.
    func reset() {
        pause()
        scorer.reset()
        results = []
        phase = .ready
        player.seek(to: sequence.start)
    }

    private func score(_ pose: PoseFrame?) {
        guard phase == .dancing else { return }
        let time = player.player.currentTime().seconds
        // Learners react to the video, so allow up to 0.5 s of real time late
        // but only 0.2 s early. At slower speeds that's less video time.
        let rate = Double(player.rate)
        if scorer.add(user: pose, at: time, late: 0.5 * rate, early: 0.2 * rate) != nil {
            results = scorer.results
        }
        if let similarity = scorer.frameSimilarity {
            // Light smoothing so the colour doesn't flicker frame to frame.
            liveSimilarity = liveSimilarity.map { $0 + 0.3 * (similarity - $0) } ?? similarity
        }
    }
}

extension PracticeModel.Phase {
    var isCountdown: Bool {
        if case .countdown = self { true } else { false }
    }
}
