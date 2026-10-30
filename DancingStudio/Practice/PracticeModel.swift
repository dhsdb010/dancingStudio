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

    var latest: StepResult? { results.last }
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
        // ±0.3 s of real time; at slower speeds that's less video time.
        let window = 0.3 * Double(player.rate)
        if scorer.add(user: pose, at: time, window: window) != nil {
            results = scorer.results
        }
    }
}

extension PracticeModel.Phase {
    var isCountdown: Bool {
        if case .countdown = self { true } else { false }
    }
}
