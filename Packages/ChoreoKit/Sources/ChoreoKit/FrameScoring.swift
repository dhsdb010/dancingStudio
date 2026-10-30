import Foundation
import PoseKit

/// A body segment compared by its direction, e.g. upper arm = shoulder → elbow.
public struct Limb: Sendable, Hashable {
    public let from: BodyJoint
    public let to: BodyJoint

    public init(from: BodyJoint, to: BodyJoint) {
        self.from = from
        self.to = to
    }

    public static let all: [Limb] = [
        Limb(from: .leftShoulder, to: .leftElbow), Limb(from: .leftElbow, to: .leftWrist),
        Limb(from: .rightShoulder, to: .rightElbow), Limb(from: .rightElbow, to: .rightWrist),
        Limb(from: .leftHip, to: .leftKnee), Limb(from: .leftKnee, to: .leftAnkle),
        Limb(from: .rightHip, to: .rightKnee), Limb(from: .rightKnee, to: .rightAnkle),
        Limb(from: .leftShoulder, to: .rightShoulder), Limb(from: .leftHip, to: .rightHip),
    ]
}

public struct FrameScore: Sendable {
    /// 0 (opposite) to 1 (identical), averaged over the limbs visible in the
    /// reference.
    public let similarity: Double
    /// The visible limb that differs most, for feedback such as "left arm too low".
    public let worstLimb: Limb?
    /// Limbs visible in the reference but not in the user's frame.
    public let missingLimbs: Int
}

/// Compares one reference frame with one user frame using the cosine similarity
/// of limb directions, so body proportions and limb lengths don't matter.
///
/// Limbs the reference shows but the user's frame doesn't (out of view or not
/// detected) are handled in two tiers. The first `forgivenMissingLimbs` are
/// skipped, since feet at the frame edge or a forearm Vision loses for a moment
/// are normal at home. Each one beyond that scores `missingLimbSimilarity`, the
/// same as a perpendicular limb, so matching one visible arm while the rest of
/// the body is out of frame isn't a perfect pose.
/// Returns nil when no limb can be scored.
public func scoreFrame(reference: PoseFrame, user: PoseFrame,
                       forgivenMissingLimbs: Int = 2, missingLimbSimilarity: Double = 0.5) -> FrameScore? {
    var total = 0.0
    var count = 0
    var missing = 0
    var worst: (limb: Limb, sim: Double)?

    for limb in Limb.all {
        guard let r = direction(of: limb, in: reference) else { continue }
        guard let u = direction(of: limb, in: user) else {
            missing += 1
            continue
        }
        // Map cosine from [-1, 1] to [0, 1].
        let sim = ((r.x * u.x + r.y * u.y) + 1) / 2
        total += sim
        count += 1
        if worst == nil || sim < worst!.sim { worst = (limb, sim) }
    }
    let penalized = max(0, missing - forgivenMissingLimbs)
    total += Double(penalized) * missingLimbSimilarity
    count += penalized
    guard count > 0 else { return nil }
    return FrameScore(similarity: total / Double(count), worstLimb: worst?.limb, missingLimbs: missing)
}

/// The limb's unit direction vector, or nil when either joint is missing.
func direction(of limb: Limb, in frame: PoseFrame) -> (x: Double, y: Double)? {
    guard let a = frame.point(limb.from), let b = frame.point(limb.to) else { return nil }
    let dx = b.x - a.x, dy = b.y - a.y
    let len = hypot(dx, dy)
    guard len > 0 else { return nil }
    return (dx / len, dy / len)
}
