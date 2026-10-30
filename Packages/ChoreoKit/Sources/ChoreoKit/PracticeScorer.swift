import Foundation
import PoseKit

/// How well one step (a short stretch of the routine) was danced.
public enum StepRating: String, CaseIterable, Sendable {
    case perfect, good, ok, miss
}

/// A correction for the body part that was furthest off.
public struct LimbFeedback: Sendable, Hashable {
    public enum Part: Sendable, Hashable {
        case upperArm, forearm, thigh, shin, shoulders, hips
    }
    /// The side of the screen the part is on in the user's frame. With the
    /// mirrored front camera this is also the dancer's own left or right.
    public enum Side: Sendable, Hashable {
        case left, right
    }
    public enum Hint: Sendable, Hashable {
        case raise, lower, adjust
    }

    public let part: Part
    /// Nil for the shoulder and hip lines, which span both sides.
    public let side: Side?
    public let hint: Hint
}

public struct StepResult: Sendable {
    public let index: Int
    /// Reference time where the step starts.
    public let start: TimeInterval
    /// Mean frame similarity over the step, 0 to 1.
    public let similarity: Double
    public let rating: StepRating
    /// The most common correction in the step. Nil for perfect steps and for
    /// steps where the dancer was mostly out of view.
    public let feedback: LimbFeedback?
}

/// Scores live frames against a reference routine step by step, like a rhythm
/// game rating each beat.
///
/// Each user frame is compared with every reference frame from `late` seconds
/// before to `early` seconds after the current playback time and keeps the
/// best match, so a learner reacting to the video a beat late isn't punished.
/// Poses are compared as they appear on
/// screen: a learner mirroring a teacher who faces the camera matches the
/// teacher's screen image. Vision sometimes swaps left and right labels, so
/// each frame is also tried with its labels swapped.
public struct PracticeScorer: Sendable {
    public var stepLength: TimeInterval = 0.5
    public var perfectThreshold = 0.92
    public var goodThreshold = 0.85
    public var okThreshold = 0.75
    /// How much a limb's vertical direction must differ before the feedback
    /// says "raise" or "lower" rather than "adjust".
    public var hintThreshold = 0.35
    /// A frame missing at least this many of the reference's limbs counts as
    /// out of view: its tip is to get the whole body in frame, not a limb fix.
    public var outOfViewLimbs = 3

    public private(set) var results: [StepResult] = []
    /// Similarity of the latest frame, for instant feedback between step
    /// results; nil when that frame couldn't be scored.
    public private(set) var frameSimilarity: Double?

    private let reference: PoseSequence
    private let referenceAspect: Double
    private let userAspect: Double
    private var step: Step?

    /// `referenceAspect` and `userAspect` are the width / height of the
    /// reference video and the camera frames, so limb directions are compared
    /// in real proportions rather than normalized image units.
    public init(reference: PoseSequence, referenceAspect: Double, userAspect: Double) {
        self.reference = reference
        self.referenceAspect = referenceAspect
        self.userAspect = userAspect
    }

    /// Scores one live frame taken while the reference was at `time`. Pass nil
    /// when no dancer was detected; that counts as a miss. `late` and `early`
    /// are how far behind or ahead of the reference the user may be, in
    /// reference seconds. Returns the result of the previous step when this
    /// frame starts a new one, including when playback loops back to the start.
    @discardableResult
    public mutating func add(user: PoseFrame?, at time: TimeInterval,
                             late: TimeInterval = 0.5, early: TimeInterval = 0.2) -> StepResult? {
        let index = Int(((time - reference.start) / stepLength).rounded(.down))
        var finished: StepResult?
        if let step, step.index != index { finished = finish() }

        let match = match(user, in: (time - late)...(time + early))
        frameSimilarity = match?.similarity
        guard let match else { return finished }
        var current = step ?? Step(index: index)
        current.total += match.similarity
        current.count += 1
        if match.outOfView {
            current.outOfView += 1
        } else if let feedback = match.feedback {
            current.add(feedback)
        }
        step = current
        return finished
    }

    /// Closes the step in progress, e.g. when the user pauses.
    @discardableResult
    public mutating func finish() -> StepResult? {
        defer { step = nil }
        guard let step, step.count > 0 else { return nil }
        let similarity = step.total / Double(step.count)
        let rating = rating(for: similarity)
        let result = StepResult(
            index: step.index,
            start: reference.start + Double(step.index) * stepLength,
            similarity: similarity,
            rating: rating,
            feedback: rating == .perfect ? nil : step.topFeedback
        )
        results.append(result)
        return result
    }

    public mutating func reset() {
        results = []
        step = nil
        frameSimilarity = nil
    }

    /// The corrections that came up most across all steps, most common first.
    public func commonFeedback(limit: Int = 3) -> [LimbFeedback] {
        var counts = Tally()
        for case let feedback? in results.map(\.feedback) { counts.add(feedback) }
        return Array(counts.ranked.prefix(limit))
    }

    public func rating(for similarity: Double) -> StepRating {
        switch similarity {
        case perfectThreshold...: .perfect
        case goodThreshold...: .good
        case okThreshold...: .ok
        default: .miss
        }
    }

    /// The best similarity against the reference frames in `range`, or nil
    /// when the reference dancer isn't visible there (nothing to score).
    private func match(_ user: PoseFrame?, in range: ClosedRange<TimeInterval>) -> (similarity: Double, feedback: LimbFeedback?, outOfView: Bool)? {
        let candidates = reference.frames(in: range).filter { !$0.joints.isEmpty }
        guard !candidates.isEmpty else { return nil }
        guard let user, !user.joints.isEmpty else { return (0, nil, true) }

        let stretched = user.stretched(by: userAspect)
        let options = [stretched, stretched.swappingSides()]
        var best: (score: FrameScore, reference: PoseFrame, user: PoseFrame)?
        for candidate in candidates {
            let reference = candidate.stretched(by: referenceAspect)
            for option in options {
                guard let score = scoreFrame(reference: reference, user: option),
                      score.similarity > best?.score.similarity ?? -1 else { continue }
                best = (score, reference, option)
            }
        }
        // The reference shows no limbs, e.g. only its dancer's head.
        guard let best else { return nil }
        if best.score.missingLimbs >= outOfViewLimbs { return (best.score.similarity, nil, true) }
        let feedback = best.score.worstLimb.flatMap { self.feedback(for: $0, reference: best.reference, user: best.user) }
        return (best.score.similarity, feedback, false)
    }

    private func feedback(for limb: Limb, reference: PoseFrame, user: PoseFrame) -> LimbFeedback? {
        guard let r = direction(of: limb, in: reference), let u = direction(of: limb, in: user) else { return nil }
        // y points up in Vision coordinates.
        let dy = r.y - u.y
        let hint: LimbFeedback.Hint = dy > hintThreshold ? .raise : dy < -hintThreshold ? .lower : .adjust
        return LimbFeedback(part: limb.part, side: limb.screenSide(in: user), hint: hint)
    }

    private struct Step: Sendable {
        let index: Int
        var total = 0.0
        var count = 0
        var feedback = Tally()
        var outOfView = 0

        mutating func add(_ item: LimbFeedback) { feedback.add(item) }
        /// Nil when being out of view was the bigger problem.
        var topFeedback: LimbFeedback? {
            outOfView >= feedback.topCount ? nil : feedback.ranked.first
        }
    }
}

/// Counts feedback; ties go to whichever came up first.
private struct Tally: Sendable {
    private var items: [(feedback: LimbFeedback, count: Int)] = []

    mutating func add(_ feedback: LimbFeedback) {
        if let i = items.firstIndex(where: { $0.feedback == feedback }) {
            items[i].count += 1
        } else {
            items.append((feedback, 1))
        }
    }

    var topCount: Int { items.map(\.count).max() ?? 0 }

    var ranked: [LimbFeedback] {
        items.enumerated()
            .sorted { ($0.element.count, -$0.offset) > ($1.element.count, -$1.offset) }
            .map(\.element.feedback)
    }
}

extension Limb {
    var part: LimbFeedback.Part {
        switch (from, to) {
        case (.leftShoulder, .rightShoulder): .shoulders
        case (.leftHip, .rightHip): .hips
        case (_, .leftElbow), (_, .rightElbow): .upperArm
        case (_, .leftWrist), (_, .rightWrist): .forearm
        case (_, .leftKnee), (_, .rightKnee): .thigh
        default: .shin
        }
    }

    /// Which side of the body's centre line the limb is on, on screen.
    func screenSide(in frame: PoseFrame) -> LimbFeedback.Side? {
        guard part != .shoulders, part != .hips,
              let a = frame.point(from), let b = frame.point(to) else { return nil }
        guard let centreX = frame.centreLineX else { return nil }
        return (a.x + b.x) / 2 < centreX ? .left : .right
    }
}

extension PoseFrame {
    /// The x of the body's centre line from whatever torso joints are visible,
    /// falling back to the nose when the dancer is close and cropped. Single
    /// shoulders or hips are skipped since they'd pull it to one side.
    var centreLineX: Double? {
        var xs = [BodyJoint.neck, .root].compactMap { point($0)?.x }
        for (l, r) in [(BodyJoint.leftShoulder, BodyJoint.rightShoulder), (.leftHip, .rightHip)] {
            if let a = point(l), let b = point(r) { xs.append((a.x + b.x) / 2) }
        }
        if xs.isEmpty, let nose = point(.nose) { xs.append(nose.x) }
        guard !xs.isEmpty else { return nil }
        return xs.reduce(0, +) / Double(xs.count)
    }
}

extension PoseFrame {
    /// Scales x by the image's width / height so directions match real angles.
    func stretched(by aspect: Double) -> PoseFrame {
        PoseFrame(time: time, joints: joints.mapValues { JointPoint(x: $0.x * aspect, y: $0.y, confidence: $0.confidence) })
    }

    /// The same points with left and right labels exchanged.
    func swappingSides() -> PoseFrame {
        PoseFrame(time: time, joints: Dictionary(uniqueKeysWithValues: joints.map { ($0.key.mirrored, $0.value) }))
    }
}
