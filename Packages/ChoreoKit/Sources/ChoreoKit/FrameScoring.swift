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
    /// 0 (opposite) to 1 (identical), averaged over limbs visible in both frames.
    public let similarity: Double
    /// The limb that differs most, for feedback such as "left arm too low".
    public let worstLimb: Limb?
}

/// Compares one reference frame with one user frame using the cosine similarity
/// of limb directions, so body proportions and limb lengths don't matter.
/// Returns nil when no limb is visible in both frames.
public func scoreFrame(reference: PoseFrame, user: PoseFrame) -> FrameScore? {
    var total = 0.0
    var count = 0
    var worst: (limb: Limb, sim: Double)?

    for limb in Limb.all {
        guard let r = direction(of: limb, in: reference), let u = direction(of: limb, in: user) else { continue }
        // Map cosine from [-1, 1] to [0, 1].
        let sim = ((r.x * u.x + r.y * u.y) + 1) / 2
        total += sim
        count += 1
        if worst == nil || sim < worst!.sim { worst = (limb, sim) }
    }
    guard count > 0 else { return nil }
    return FrameScore(similarity: total / Double(count), worstLimb: worst?.limb)
}

private func direction(of limb: Limb, in frame: PoseFrame) -> (x: Double, y: Double)? {
    guard let a = frame.point(limb.from), let b = frame.point(limb.to) else { return nil }
    let dx = b.x - a.x, dy = b.y - a.y
    let len = hypot(dx, dy)
    guard len > 0 else { return nil }
    return (dx / len, dy / len)
}
